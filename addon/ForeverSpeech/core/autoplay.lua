-- ForeverSpeech: automatic reading of the quests (CLAUDE.md 9.1, 2026-10-21). One option, autoplay (on by default):
-- every quest accepted is read READ_DELAY after it, every quest turned in has its end read READ_DELAY after it,
-- whatever the interface (the game's buttons, Dialogue UI...). Replaces the "Accepter et lire" and "Terminer et lire"
-- buttons and the reading when the reward panel opened (removed 2026-10-21).
-- Dialogue UI hides QuestFrame and calls AcceptQuest and GetQuestReward through copies made when it loads, before any
-- hook of ours: only the game's events see its clicks. They come with the server's answer, so a quest the game refused
-- (quest log full, bags full) is never read. QUEST_ACCEPTED(questID) is verified (S4), QUEST_TURNED_IN fires on Forever
-- (H9) and its questID argument too (T56).
local H = ForeverSpeech

local Autoplay = {}
H.Autoplay = Autoplay

-- Seconds between the accept or the turn-in and the reading: the NPC says a few words first.
local READ_DELAY = 2

-- Plays the quest part now if nothing is playing, else adds it to the play list (Player.PlayQuest). The window shows
-- it only when it starts now: a queued quest appears in the play list. H.Player.AUTO: the addon reads by itself (not
-- in a battleground: core/silence.lua).
local function readQuest(questID, part)
  local status = H.Player.PlayQuest(questID, part, H.Player.AUTO)
  H.Trace("autoplay: quest=%s part=%s %s", questID, part or "detail", status)
  if status == "playing" then
    H.PlayerFrame.ShowQuest(questID, part)
  end
end

-- The event's quest ID, else the quest last opened (capture.lua).
local function eventQuestID(questID, fallback)
  questID = H.NotSecret(questID)
  if type(questID) == "number" and questID > 0 then
    return questID
  end
  return fallback
end

local function onQuestEvent(event, questID, part, fallback)
  questID = eventQuestID(questID, fallback)
  H.Trace("autoplay: %s quest=%s on=%s", event, questID, ForeverSpeechDB.autoplay)
  if questID and ForeverSpeechDB.autoplay and H.IsEnabled() then
    C_Timer.After(READ_DELAY, function()
      readQuest(questID, part)
    end)
  end
end

H.TryRegisterEvent("QUEST_ACCEPTED", function(event, questID)
  onQuestEvent(event, questID, nil, H.Capture.lastQuestID)
end)

H.TryRegisterEvent("QUEST_TURNED_IN", function(event, questID)
  onQuestEvent(event, questID, "complete", H.Capture.lastCompleteQuestID)
end)

H.RegisterCommand("autoplay", function(arg)
  arg = arg:lower()
  if arg == "on" then
    ForeverSpeechDB.autoplay = true
  elseif arg == "off" then
    ForeverSpeechDB.autoplay = false
  end
  H.Print("automatic reading of quests accepted and turned in: %s", ForeverSpeechDB.autoplay and "on" or "off")
end, "autoplay on|off - read every quest accepted or turned in, whatever the interface")
