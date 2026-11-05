-- ForeverSpeech: the interface fades while the character moves (2026-11-05, asked by the player: enjoy the world
-- while walking). Moving (IsPlayerMoving, or a flight path: UnitOnTaxi), the whole interface (UIParent) fades from
-- where it is to 20 % in 3 seconds (never the minimap); stopped, it comes back to 100 % in half a second from
-- where it was. The element under the mouse (UIParent's child holding the mouse focus) and the tooltip stay at full
-- alpha (SetIgnoreParentAlpha), their own setting given back.
-- Never while the interface is needed: in combat (back at once), the world map or a game window open, a dialog, the
-- game menu, the loot window, the chat being typed in, something on the cursor, Edit Mode, the addon's options.
-- Setting fadeOnMove (Options > Confort, on), /fs fade on|off. Any error puts the interface back and stops the fade.
-- Unverified on Forever: T68 (H42).
local H = ForeverSpeech

local Fade = {}
H.Fade = Fade

-- the faded alpha (20 %, 10 % at first: asked after a try in game); seconds to reach it; seconds to come back
local MIN_ALPHA, FADE_OUT, FADE_IN = 0.2, 3, 0.5
local BUSY_EVERY = 0.1 -- seconds between two looks at what is open
local PANELS = { "left", "center", "right", "doublewide", "fullscreen" } -- GetUIPanel's slots
local OPEN = { "WorldMapFrame", "StaticPopup1", "GameMenuFrame", "LootFrame", "EditModeManagerFrame" }

local alpha = 1
local inRate -- the fade-in's speed, fixed when it starts (from where it was to 100 % in FADE_IN)
local lifted = {} -- [frame] = { ignore, alpha }: its own IgnoreParentAlpha and alpha before the fade lifted it
local busy, busyElapsed = false, BUSY_EVERY
local broken = false

local function shown(name)
  local f = _G[name]
  return type(f) == "table" and f.IsShown and f:IsShown() or false
end

-- True while the interface must stay: in combat, or something to read or to use is open.
local function needed()
  if H.Safe(_G.InCombatLockdown) or H.Safe(_G.UnitAffectingCombat, "player") then
    return true
  end
  for _, name in ipairs(OPEN) do
    if shown(name) then
      return true
    end
  end
  for _, slot in ipairs(PANELS) do
    if H.Safe(_G.GetUIPanel, slot) then
      return true
    end
  end
  return H.Safe(_G.ChatEdit_GetActiveWindow) ~= nil or H.Safe(_G.GetCursorInfo) ~= nil
    or (H.Options ~= nil and H.Options.IsShown())
end

-- UIParent's child holding a frame (the element), else nil.
local function element(frame)
  local ui = _G.UIParent
  for _ = 1, 40 do
    if type(frame) ~= "table" or not frame.GetParent then
      return nil
    end
    local parent = frame:GetParent()
    if parent == ui then
      return frame
    end
    frame = parent
  end
  return nil
end

local function underMouse()
  local foci = H.Safe(_G.GetMouseFoci)
  local focus = type(foci) == "table" and foci[1] or H.Safe(_G.GetMouseFocus)
  if focus == nil or focus == _G.WorldFrame then
    return nil
  end
  return element(focus)
end

-- Out of the interface's fade: the element at its own alpha (own: an alpha of the fade's own for it, else its own).
local function lift(frame, own)
  if not frame.SetIgnoreParentAlpha then
    return
  end
  local saved = lifted[frame]
  if not saved then
    local okIgnore, ignore = pcall(frame.IsIgnoringParentAlpha, frame)
    local okAlpha, was = pcall(frame.GetAlpha, frame)
    saved = { ignore = okIgnore and ignore == true, alpha = okAlpha and tonumber(was) or 1 }
    lifted[frame] = saved
    pcall(frame.SetIgnoreParentAlpha, frame, true)
  end
  local want = own or saved.alpha
  if saved.set ~= want then
    saved.set = want
    pcall(frame.SetAlpha, frame, want)
  end
end

local function drop(frame)
  local saved = lifted[frame]
  if saved then
    lifted[frame] = nil
    if saved.set ~= saved.alpha then
      pcall(frame.SetAlpha, frame, saved.alpha)
    end
    pcall(frame.SetIgnoreParentAlpha, frame, saved.ignore)
  end
end

local function setAlpha(value)
  alpha = value
  _G.UIParent:SetAlpha(value)
end

-- Everything back at once: alpha, the lifted frames.
local function restore()
  inRate = nil
  for frame in pairs(lifted) do
    drop(frame)
  end
  if alpha ~= 1 then
    setAlpha(1)
  end
end

local function step(elapsed)
  busyElapsed = busyElapsed + elapsed
  if busyElapsed >= BUSY_EVERY then
    busyElapsed = 0
    busy = needed()
  end
  if busy and (H.Safe(_G.InCombatLockdown) or H.Safe(_G.UnitAffectingCombat, "player")) then
    restore() -- combat: the interface at once
    return
  end
  -- moving: walking, running, swimming, mounted, or on a flight path (2026-11-05, asked: the gryphon too)
  local moving = H.Safe(_G.IsPlayerMoving) == true or H.Safe(_G.UnitOnTaxi, "player") == true
  if ForeverSpeechDB.fadeOnMove ~= false and not busy and moving then
    inRate = nil
    if alpha > MIN_ALPHA then
      setAlpha(math.max(MIN_ALPHA, alpha - (1 - MIN_ALPHA) / FADE_OUT * elapsed))
    end
  elseif alpha < 1 then
    inRate = inRate or (1 - alpha) / FADE_IN
    setAlpha(math.min(1, alpha + inRate * elapsed))
  else
    inRate = nil
  end
  -- over the faded interface: the element under the mouse, the tooltip and the minimap's element at their own alpha.
  -- The minimap never fades, to guide the player (40 % was tried: setting its alpha made it jump, 2026-11-05).
  local hovered = alpha < 1 and underMouse() or nil
  local tooltip = alpha < 1 and _G.GameTooltip or nil
  local map = alpha < 1 and element(_G.Minimap) or nil
  for frame in pairs(lifted) do
    if frame ~= hovered and frame ~= tooltip and frame ~= map then
      drop(frame)
    end
  end
  if map then
    lift(map)
  end
  if hovered then
    lift(hovered)
  end
  if tooltip then
    lift(tooltip)
  end
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, elapsed)
  if broken then
    return
  end
  local ok, err = pcall(step, elapsed)
  if not ok then
    broken = true
    pcall(restore)
    H.Trace("fade: stopped after an error: %s", tostring(err))
  end
end)

H.TryRegisterEvent("PLAYER_REGEN_DISABLED", function()
  busy = true
  restore()
end)

-- The interface's alpha now (for tests and debugging).
function Fade.Alpha()
  return alpha
end

function Fade.SetEnabled(on)
  ForeverSpeechDB.fadeOnMove = on and true or false
  if not on then
    restore()
  end
end

H.RegisterCommand("fade", function(arg)
  arg = (arg or ""):lower()
  if arg == "on" or arg == "off" then
    Fade.SetEnabled(arg == "on")
  end
  H.Print("interface faded while moving: %s", ForeverSpeechDB.fadeOnMove ~= false and "on" or "off")
end, "fade on|off - fade the interface while the character moves")
