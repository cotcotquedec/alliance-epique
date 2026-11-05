-- ForeverSpeech: ducking (2026-10-21). While a line of the addon plays (any kind), the music, the ambience and the
-- effects fade down to a share of the player's own volume (music 30 %, ambience 40 %, effects 60 %), never the channel
-- the addon plays on (ForeverSpeechDB.channel, "Dialog" by default); they fade back up DUCK_HOLD s after the play list
-- goes quiet (a gap between two quests keeps them down). Setting duck (on by default), /fs duck on|off.
-- Safe restore: the player's values are kept in ForeverSpeechDB.duckState before anything changes, with the value the
-- addon set last. A volume that no longer matches it (the player moved the slider) is no longer managed: left as the
-- player put it. Restored at once on PLAYER_LOGOUT (it fires on /reload and logout before the CVars are saved); at
-- PLAYER_LOGIN, a volume a crash left lowered is put back. Idea from Spoken (MIT).
-- CVars Sound_MusicVolume, Sound_AmbienceVolume, Sound_SFXVolume ("0".."1"): unverified on Forever.
local H = ForeverSpeech

local Ducking = {}
H.Ducking = Ducking

local CHANNELS = {
  { channel = "Music", cvar = "Sound_MusicVolume", share = 0.3 },
  { channel = "Ambience", cvar = "Sound_AmbienceVolume", share = 0.4 },
  { channel = "SFX", cvar = "Sound_SFXVolume", share = 0.6 },
}
local FADE, STEP = 0.8, 0.05
local STEPS = math.floor(FADE / STEP + 0.5)
local DUCK_HOLD = 1.2
local TOLERANCE = 0.005

local fadeToken = 0  -- cancels a fade when a newer one starts
local raiseToken = 0 -- cancels a scheduled raise when a line starts
local lowered = false

local function getCVar(name)
  local get = (C_CVar and C_CVar.GetCVar) or GetCVar
  return H.Safe(get, name)
end

local function setCVar(name, value)
  local set = (C_CVar and C_CVar.SetCVar) or SetCVar
  if type(set) ~= "function" then
    return false
  end
  return (pcall(set, name, value))
end

-- cvar -> { orig = number, origText = the player's string, set = the value set last, share }
local function state()
  ForeverSpeechDB.duckState = ForeverSpeechDB.duckState or {}
  return ForeverSpeechDB.duckState
end

-- The player moved the slider since the addon set it (or the value cannot be read).
local function moved(cvar, entry)
  local value = tonumber(getCVar(cvar))
  return value == nil or math.abs(value - entry.set) > TOLERANCE
end

local function write(cvar, entry, value)
  local text = string.format("%.3f", value)
  if setCVar(cvar, text) then
    entry.set = tonumber(text)
  end
end

local function restore(cvar, entry)
  if setCVar(cvar, entry.origText) then
    entry.set = entry.orig
  end
end

-- Fades every managed volume to target(entry) in STEPS steps of STEP s; done() after the last one.
local function fade(target, done)
  fadeToken = fadeToken + 1
  local mine, step = fadeToken, 0
  local from = {}
  for cvar, entry in pairs(state()) do
    from[cvar] = entry.set
  end
  local function tick()
    if mine ~= fadeToken then
      return
    end
    step = step + 1
    local st = state()
    for cvar, entry in pairs(st) do
      if moved(cvar, entry) then
        st[cvar] = nil
        H.Trace("ducking: %s moved by the player, left as it is", cvar)
      elseif step >= STEPS and target(entry) == entry.orig then
        restore(cvar, entry)
      else
        local start = from[cvar] or entry.set
        write(cvar, entry, start + (target(entry) - start) * step / STEPS)
      end
    end
    if step < STEPS then
      C_Timer.After(STEP, tick)
    elseif done then
      done()
    end
  end
  tick()
end

local function lowTarget(entry)
  return entry.orig * entry.share
end

local function origTarget(entry)
  return entry.orig
end

function Ducking.IsLowered()
  return lowered
end

-- Fades the other channels down (a line starts).
function Ducking.Lower()
  raiseToken = raiseToken + 1
  if not ForeverSpeechDB.duck or lowered then
    return false
  end
  local st = state()
  local playing = ForeverSpeechDB.channel or "Dialog"
  for _, c in ipairs(CHANNELS) do
    if c.channel ~= playing and not st[c.cvar] then
      local text = getCVar(c.cvar)
      local value = tonumber(text)
      if value then
        st[c.cvar] = { orig = value, origText = tostring(text), set = value, share = c.share }
      end
    end
  end
  lowered = true
  H.Trace("ducking: down")
  fade(lowTarget)
  return true
end

-- Fades them back to the player's values, then forgets them.
function Ducking.Raise()
  raiseToken = raiseToken + 1
  if not lowered and not next(state()) then
    return false
  end
  lowered = false
  H.Trace("ducking: up")
  fade(origTarget, function()
    ForeverSpeechDB.duckState = {}
  end)
  return true
end

-- Puts the player's values back at once (logout, /reload; at login, after a crash), except a moved slider.
function Ducking.RestoreNow(why)
  fadeToken, raiseToken = fadeToken + 1, raiseToken + 1
  lowered = false
  local restored = 0
  for cvar, entry in pairs(state()) do
    if not moved(cvar, entry) then
      restore(cvar, entry)
      restored = restored + 1
    end
  end
  ForeverSpeechDB.duckState = {}
  if restored > 0 then
    H.Trace("ducking: %s volume(s) restored (%s)", restored, why)
  end
  return restored
end

-- The play list went quiet: up again DUCK_HOLD s later if nothing plays then.
local function raiseSoon()
  raiseToken = raiseToken + 1
  local mine = raiseToken
  C_Timer.After(DUCK_HOLD, function()
    if mine == raiseToken and not H.Player.IsBusy() then
      Ducking.Raise()
    end
  end)
end

function Ducking.SetEnabled(value)
  ForeverSpeechDB.duck = value and true or false
  if not value then
    Ducking.Raise()
  elseif H.Player.Current() then
    Ducking.Lower()
  end
end

H.Player.OnChange(function(event)
  if event == "start" then
    Ducking.Lower()
  elseif event == "stop" or event == "idle" then
    raiseSoon()
  end
end)

for event, why in pairs({ PLAYER_LOGOUT = "logout", PLAYER_LOGIN = "login" }) do
  H.TryRegisterEvent(event, function()
    if type(ForeverSpeechDB) == "table" then
      Ducking.RestoreNow(why)
    end
  end)
end

H.RegisterCommand("duck", function(arg)
  arg = (arg or ""):lower()
  if arg == "on" or arg == "off" then
    Ducking.SetEnabled(arg == "on")
  end
  H.Print("ducking (music, ambience and effects lowered while a line plays): %s",
    ForeverSpeechDB.duck and "on" or "off")
end, "duck on|off - lower the music, ambience and effects while a line plays")
