-- ForeverSpeech: silence in battlegrounds and arenas (2026-10-21). There, nothing the addon starts by itself plays:
-- Elise's zone, level and companion lines, the turn-in reading of the reward panel, the native Accept's reading, the
-- books and the NPC dialogues (every Player.Play* call with Player.AUTO). A line the player asks for (a play button,
-- "Accepter et lire", /fs play) still plays. Entering one drops what the addon had queued by itself. Setting
-- readInBattleground (off by default) lifts it.
-- IsInInstance() -> inInstance, "pvp" | "arena" | "party" | "raid" | "none" (Classic, Retail; unverified on Forever).
local H = ForeverSpeech

local Silence = {}
H.Silence = Silence

local PVP = { pvp = true, arena = true }

-- True in a battleground or an arena.
function Silence.InBattleground()
  local inInstance, kind = H.Safe(IsInInstance)
  return (inInstance and PVP[kind]) and true or false
end

-- True when the addon must not start anything by itself.
function Silence.Active()
  if type(ForeverSpeechDB) ~= "table" or ForeverSpeechDB.readInBattleground then
    return false
  end
  return Silence.InBattleground()
end

H.TryRegisterEvent("PLAYER_ENTERING_WORLD", function()
  if Silence.Active() then
    local dropped = H.Player.DropAuto()
    H.Trace("silence: battleground, %s automatic line(s) dropped", dropped)
  end
end)
