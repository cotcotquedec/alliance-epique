-- ForeverSpeech: tells the group when a quest's objectives are all done (2026-10-17, an idea taken from Questie's
-- announcements, no code reused). In a group only, and only for a quest with objectives seen not done then done in
-- this session: one chat line, "{rt1} J'ai terminé « Titre » : Masque rouge : 12/12.", in the group channel (PARTY,
-- RAID or INSTANCE_CHAT, its speech bubble shows to the group) or in /say (setting announceChannel).
-- Unverified on Forever (docs/ingame/queue.md): C_QuestLog.GetNumQuestLogEntries and GetInfo(i).questID / isHeader;
-- SendChatMessage from an addon without a click: allowed for the group channels, SAY outdoors may be blocked (Classic
-- since 1.13.3: a hardware event is needed).
local H = ForeverSpeech
local L = H.L

local Announce = {}
H.Announce = Announce

local MAX_BYTES = 255 -- SendChatMessage's limit
local MARK = "{rt1} "
local DELAY = 0.3 -- objectives settle over a few QUEST_LOG_UPDATE in a row

local states = {}    -- questID -> "todo" | "done", quests of the log with objectives
local announced = {} -- questID -> true, once per session
local baseline = false
local pending = false

-- A secret value (instances and combat, Forever) reads as nil (H.Safe, 2026-10-21).
local call = H.Safe

-- questIDs of the log (headers left out), or nil without the API.
local function logQuests()
  local count = C_QuestLog and call(C_QuestLog.GetNumQuestLogEntries)
  if type(count) ~= "number" then
    return nil
  end
  local ids = {}
  for i = 1, count do
    local info = call(C_QuestLog.GetInfo, i)
    if type(info) == "table" and not info.isHeader and tonumber(info.questID) and info.questID > 0 then
      ids[#ids + 1] = info.questID
    end
  end
  return ids
end

-- "done" when every objective is, "todo" otherwise, nil for a quest without objectives.
local function state(questID)
  local lines = H.QuestData.Progress(questID)
  if not lines then
    return nil
  end
  for _, line in ipairs(lines) do
    if not line.finished then
      return "todo"
    end
  end
  return "done"
end

-- Cuts a UTF-8 string to at most max bytes, never inside a character.
local function cut(text, max)
  if #text <= max then
    return text
  end
  local stop = max
  while stop > 0 do
    local byte = text:byte(stop + 1)
    if not byte or byte < 0x80 or byte >= 0xC0 then
      break
    end
    stop = stop - 1
  end
  return text:sub(1, stop)
end

-- The chat line for a quest, or nil without its title.
function Announce.Message(questID)
  local title = H.QuestData.Title(questID)
  if not title or title == "" then
    return nil
  end
  local message = MARK .. string.format(L.ANNOUNCE_DONE, title)
  local parts = {}
  for _, line in ipairs(H.QuestData.Progress(questID) or {}) do
    parts[#parts + 1] = line.text
  end
  if #parts == 0 then
    return message .. "."
  end
  message = message .. " : " .. table.concat(parts, " ; ") .. "."
  if #message > MAX_BYTES then
    local ellipsis = "…"
    message = cut(message, MAX_BYTES - #ellipsis) .. ellipsis
  end
  return message
end

-- The channel to write in, or nil outside a group.
function Announce.Channel()
  if not (call(IsInGroup) or call(IsInRaid)) then
    return nil
  end
  if ForeverSpeechDB.announceChannel == "say" then
    return "SAY"
  end
  if call(IsInRaid) then
    return "RAID"
  end
  if LE_PARTY_CATEGORY_INSTANCE and call(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) then
    return "INSTANCE_CHAT"
  end
  return "PARTY"
end

-- Sends the line for a quest. Returns "sent" | "no group" | "no message" | "error", and the channel or the error.
function Announce.Send(questID)
  local channel = Announce.Channel()
  if not channel then
    return "no group"
  end
  local message = Announce.Message(questID)
  if not message then
    return "no message"
  end
  local ok, err = pcall(SendChatMessage, message, channel)
  H.Trace("announce: quest=%s channel=%s ok=%s err=%s bytes=%d", questID, channel, ok, err, #message)
  if not ok then
    return "error", err
  end
  return "sent", channel
end

-- One look at the log: a quest seen "todo" now "done" is announced (setting on, in a group, once per session). The
-- first look after login only notes the states: a quest done before is never announced.
function Announce.Scan()
  local ids = logQuests()
  if not ids then
    return
  end
  local seen = {}
  for _, questID in ipairs(ids) do
    seen[questID] = true
    local now = state(questID)
    local before = states[questID]
    states[questID] = now
    if baseline and before == "todo" and now == "done" and not announced[questID]
        and ForeverSpeechDB.announceComplete then
      local status, detail = Announce.Send(questID)
      H.Trace("announce: quest=%s done: %s %s", questID, status, detail)
      if status == "sent" then
        announced[questID] = true
      end
    end
  end
  for questID in pairs(states) do
    if not seen[questID] then
      states[questID] = nil
    end
  end
  baseline = true
end

H.TryRegisterEvent("QUEST_LOG_UPDATE", function()
  if pending then
    return
  end
  pending = true
  C_Timer.After(DELAY, function()
    pending = false
    Announce.Scan()
  end)
end)

-- Blocked by the client (SAY outdoors without a click): said in the trace and once in the chat.
local blockedSaid = false
local function blocked(_, addon, action)
  if addon ~= H.name then
    return
  end
  H.Trace("announce: blocked %s", action)
  if not blockedSaid and ForeverSpeechDB.announceChannel == "say" then
    blockedSaid = true
    H.Print("%s", L.ANNOUNCE_BLOCKED)
  end
end
H.TryRegisterEvent("ADDON_ACTION_BLOCKED", blocked)
H.TryRegisterEvent("ADDON_ACTION_FORBIDDEN", blocked)

H.RegisterCommand("announce", function(arg)
  arg = (arg or ""):lower()
  if arg == "on" or arg == "off" then
    ForeverSpeechDB.announceComplete = arg == "on"
    H.Print("quest announcements: %s", arg)
    return
  end
  if arg == "party" or arg == "say" then
    ForeverSpeechDB.announceChannel = arg
    H.Print("quest announcements in: %s", arg)
    return
  end
  local questID = tonumber(arg) or H.QuestData.Tracked()
  if not questID then
    H.Print("announce: no quest")
    return
  end
  local status, detail = Announce.Send(questID)
  if status == "no group" then
    H.Print("announce (not in a group, shown here only): %s", tostring(Announce.Message(questID)))
  else
    H.Print("announce %s: %s %s", questID, status, tostring(detail))
  end
end, "announce [questID|on|off|party|say] - tell the group a quest is done (default: the followed quest, now)")
