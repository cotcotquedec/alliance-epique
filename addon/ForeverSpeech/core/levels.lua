-- ForeverSpeech: Elise's level-up lines (2026-10-11). Each level gained (2 to 60) has its line, and the 59 lines tell
-- one story; 2 s after the level is gained (the game's own sound and glow first), the line goes in the play list
-- (Player.PlayLine). Automatic only once her audio exists (index v6, levels[level].intro); before that, /fs level
-- reads her text with the client's speech synthesis.
-- Unverified on Forever: PLAYER_LEVEL_UP and its first argument, the new level (docs/ingame/queue.md).
local H = ForeverSpeech

local Levels = {}
H.Levels = Levels

local DELAY = 2

-- Puts the line of a level gained in the play list. Returns "off", "no audio" or the Player.PlayLine status.
function Levels.Gained(level)
  level = tonumber(level)
  if not ForeverSpeechDB.levelLines or not H.IsEnabled() or not level then
    return "off"
  end
  local entry = H.Index.Level(level)
  if not (entry and entry.intro) then
    H.Trace("levels: %s has no audio yet", level)
    return "no audio"
  end
  local status, detail = H.Player.PlayLine("level", level, H.Player.AUTO)
  H.Trace("levels: %s: %s %s", level, status, detail)
  return status, detail
end

H.TryRegisterEvent("PLAYER_LEVEL_UP", function(_, level)
  C_Timer.After(DELAY, function()
    Levels.Gained(level)
  end)
end)

H.RegisterCommand("level", function(arg)
  arg = (arg or ""):lower()
  if arg == "on" or arg == "off" then
    ForeverSpeechDB.levelLines = arg == "on"
    H.Print("level-up lines: %s", arg)
    return
  end
  local level = tonumber(arg) or (UnitLevel and UnitLevel("player"))
  local status, detail = H.Player.PlayLine("level", level)
  H.Print("level %s: %s %s", tostring(level), tostring(status), tostring(detail))
end, "level [n|on|off] - Elise's line for a level (default: the current one)")
