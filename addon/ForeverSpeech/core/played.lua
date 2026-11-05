-- ForeverSpeech: the character's level and the total time played, for the companion journal (D18: the share of the
-- time played spent with a companion). Nothing is shown in the window (2026-10-18: the time played at this level is
-- gone, the addon is about enjoying the story, not about the clock; 2026-11-05: the level and money band too).
-- RequestTimePlayed asks the server, TIME_PLAYED_MSG(total, thisLevel) answers (seconds); the addon asks once when
-- the character enters the world, and counts on from the answer with GetTime. Until an answer comes, the total is
-- unknown (nil): nothing is guessed. The chat frames print that answer ("Temps de jeu total..."): for the addon's own
-- request only, they stop listening to TIME_PLAYED_MSG until the answer has come (their event registration only: no
-- Blizzard function is replaced). A /played typed by the player prints as usual.
-- Unverified on Forever: RequestTimePlayed, TIME_PLAYED_MSG and its arguments, ChatFrame1..NUM_CHAT_WINDOWS.
local H = ForeverSpeech

local Played = {}
H.Played = Played

local EVENT = "TIME_PLAYED_MSG"
local ANSWER_TIMEOUT = 10 -- seconds: without an answer, the chat frames get the event back

local total, answeredAt -- the last answer's total time played, and GetTime() when it came
local gainedLevel -- the level PLAYER_LEVEL_UP gave (UnitLevel follows a little later)
local pending, muted = false, {}

local function chatFrames()
  local list = {}
  for i = 1, tonumber(NUM_CHAT_WINDOWS) or 0 do
    local f = _G["ChatFrame" .. i]
    if type(f) == "table" and f.IsEventRegistered and f.UnregisterEvent then
      list[#list + 1] = f
    end
  end
  return list
end

local function mute()
  for _, f in ipairs(chatFrames()) do
    local ok, registered = pcall(f.IsEventRegistered, f, EVENT)
    if ok and registered then
      f:UnregisterEvent(EVENT)
      muted[#muted + 1] = f
    end
  end
end

local function unmute()
  for _, f in ipairs(muted) do
    pcall(f.RegisterEvent, f, EVENT)
  end
  muted = {}
end

local function finish()
  if pending then
    pending = false
    unmute()
  end
end

-- Asks the server for the time played, silently. false when the client cannot.
function Played.Request()
  if type(RequestTimePlayed) ~= "function" then
    return false
  end
  if pending then
    return true
  end
  pending = true
  mute()
  local ok, err = pcall(RequestTimePlayed)
  H.Trace("played: request ok=%s %s muted=%s", ok, err, #muted)
  if not ok then
    finish()
    return false
  end
  C_Timer.After(ANSWER_TIMEOUT, finish)
  return true
end

-- Seconds played in all, counting on from the last answer, or nil while none came.
function Played.Total()
  if not total then
    return nil
  end
  return total + math.max(0, GetTime() - answeredAt)
end

-- The character's level: the one PLAYER_LEVEL_UP gave if UnitLevel does not know it yet. nil if unknown.
function Played.Level()
  local level = UnitLevel and tonumber(UnitLevel("player"))
  if gainedLevel and (not level or gainedLevel > level) then
    return gainedLevel
  end
  return level
end

H.TryRegisterEvent(EVENT, function(_, all)
  H.Trace("played: answer total=%s pending=%s", all, pending)
  if tonumber(all) then
    total, answeredAt = tonumber(all), GetTime()
  end
  if pending then
    -- next frame: the chat frames must not get this very answer
    C_Timer.After(0, finish)
  end
end)

H.TryRegisterEvent("PLAYER_LEVEL_UP", function(_, level)
  gainedLevel = tonumber(level)
end)

local requested = false -- once per session (a /reload is a new one)
H.TryRegisterEvent("PLAYER_ENTERING_WORLD", function()
  if not requested then
    requested = Played.Request()
  end
end)
