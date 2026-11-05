-- ForeverSpeech: key bindings (2026-10-21), declared in Bindings.xml (the client loads it by itself from the addon's
-- folder, no TOC line; a new file needs a full restart of the game). Options > Raccourcis > AddOns > ForeverSpeech:
-- Lecture / Stop (the window's quest: plays it from the start, or stops what plays), Avancer (the next quest of the
-- list), Stop (the window's Stop button: the list halts), Roue d'émotes (held, ui/emote_wheel.lua, 2026-10-21).
-- The BINDING_* names are globals the key binding UI reads.
-- Unverified on Forever: Bindings.xml loaded, its header and its names shown (docs/ingame/queue.md).
local H = ForeverSpeech

local Bindings = {}
H.Bindings = Bindings

BINDING_HEADER_FOREVERSPEECH = H.L.BINDING_HEADER
BINDING_NAME_FOREVERSPEECH_PLAY = H.L.BINDING_PLAY
BINDING_NAME_FOREVERSPEECH_NEXT = H.L.BINDING_NEXT
BINDING_NAME_FOREVERSPEECH_STOP = H.L.BINDING_STOP
BINDING_NAME_FOREVERSPEECH_EMOTEWHEEL = H.L.BINDING_EMOTE_WHEEL

-- Lecture / Stop: something plays (or the list waits between two quests) -> Stop; else the window's quest or line
-- from the start, else the quest opened last. Returns what it did.
function Bindings.TogglePlay()
  local Player = H.Player
  if Player.IsBusy() then
    Player.Stop()
    return "stopped"
  end
  local PlayerFrame = H.PlayerFrame
  local kind, id, questID, part
  if PlayerFrame then
    kind, id = PlayerFrame.Line()
    questID, part = PlayerFrame.QuestID()
  end
  if kind then
    return Player.PlayLineNow(kind, id)
  end
  if questID then
    return Player.PlayNow(questID, part)
  end
  questID = H.Capture.lastQuestID
  if questID then
    return Player.PlayQuest(questID)
  end
  return "failed", "no quest"
end

function Bindings.Next()
  return H.Player.Next()
end

function Bindings.Stop()
  return H.Player.Stop()
end
