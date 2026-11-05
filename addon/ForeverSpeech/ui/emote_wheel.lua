-- ForeverSpeech: the emote wheel (2026-10-21, asked by the player: "like the ping wheel"). Hold its key (Bindings.xml
-- FOREVERSPEECH_EMOTEWHEEL, runOnUp; Options > Confort or Options > Raccourcis > AddOns), the wheel opens at the cursor
-- (at the screen's center in mouselook), aim at an emote with the mouse or the right stick, release: DoEmote, to the
-- target if there is one, to everyone otherwise (as the side tabs did). Released in the center or after
-- a short press (< SHORT s): nothing. Left click while open: now; right click: cancel. Setting emoteWheel.
-- Our own frame in the ping wheel's style: the client's RadialWheel atlases by name where it has them for 8 wedges
-- (Radial_Wheel_Select_Wedge_Count_8; the pointer Radial_Wheel_Select_Pointer and the cross Radial_Wheel_Icon_Close),
-- names read in the Forever interface code, nothing copied; the ping wheel itself is forbidden to addons. Forever has
-- no 8-wedge art (T60): the dark disc, the aimed wedge's gold cone and the center button are the addon's own, drawn by
-- tools/wheel_art.ts (media/ui/wheel_*.tga), the wedge lines are thin grey textures.
-- Gamepad: the right stick read with C_GamePad.GetDeviceMappedState, not captured (EnableGamePadStick is protected on
-- Forever). Mouse and stick both aim, whichever moved last (T60, 2026-10-21: no highlight and nothing on release, most
-- likely because the game's gamepad mode was on and the first version then listened to the stick alone).
-- Nothing secure, nothing Blizzard hooked: works in combat.
-- Unverified on Forever (H32-H35): which atlases exist (T60: the pointer yes, the 8-wedge frame and highlight not),
-- the stick's index.
local H = ForeverSpeech
local L = H.L

local Wheel = {}
H.EmoteWheel = Wheel

local SIZE = 340       -- the wheel, px
local RADIUS = 116     -- the icons' circle
local ICON = 44
local CENTER_SIZE = 52 -- the center button
local LINE_FROM = 28   -- the wedge lines, from the center button to near the rim
local LABEL_SIZE = 14  -- the names, the face of the game's wheel (Game18Font) a little smaller (T60)
local LABEL_GAP = 5    -- between an icon and its name
local DEAD = 22        -- center dead zone, px (the game's)
local SHORT = 0.15     -- a shorter press does nothing (the ping wheel's)
local STICK = 0.5      -- stick length that aims (the game's threshold)
local GLOW_OFFSET = 20 -- the wedge highlight's distance from the center, along its wedge (the game's)
local UI = H.MEDIA .. "ui\\"
local ART = { disc = UI .. "wheel_disc", wedge = UI .. "wheel_wedge", center = UI .. "wheel_center" }

-- Icons painted for the wheel (2026-10-21): flat "World of Warcraft emoji" in the ping wheel's style, on a transparent
-- ground (media/wheel/<key>.tga, tools/wheel_icons.ts). First at the top, then counterclockwise, like the game's wheel.
local ICONS = H.MEDIA .. "wheel\\"
Wheel.EMOTES = {
  { token = "HELLO", label = "EMOTE_HELLO", icon = ICONS .. "hello" },
  { token = "THANK", label = "EMOTE_THANKS", icon = ICONS .. "thanks" },
  { token = "CONGRATULATE", label = "EMOTE_CONGRATS", icon = ICONS .. "congrats" },
  { token = "APPLAUD", label = "EMOTE_APPLAUD", icon = ICONS .. "applaud" },
  { token = "LAUGH", label = "EMOTE_LAUGH", icon = ICONS .. "laugh" },
  { token = "DANCE", label = "EMOTE_DANCE", icon = ICONS .. "dance" },
  { token = "BOW", label = "EMOTE_BOW", icon = ICONS .. "bow" },
  { token = "SIT", label = "EMOTE_SIT", icon = ICONS .. "sit" },
}

local frame, wheel, pressedAt, selected, openCursor, mouseMoved
local art = {} -- the wheel's textures and what the client gave (a missing frame field is not nil in every client)

-- Wedge (1..n) under an offset from the center (screen orientation, y up), nil in the dead zone. Wedge 1 is centered
-- at the top, then counterclockwise.
function Wheel.WedgeAt(dx, dy, n, dead)
  if dx * dx + dy * dy < (dead or DEAD) ^ 2 then
    return nil
  end
  local step = 2 * math.pi / n
  local fromTop = math.atan2(dy, dx) - math.pi / 2
  return math.floor((fromTop + step / 2) / step) % n + 1
end

-- Angle of a wedge's center, radians, counterclockwise from the x axis.
local function wedgeAngle(i, n)
  return math.pi / 2 + (i - 1) * 2 * math.pi / n
end

local function enabled()
  return not ForeverSpeechDB or ForeverSpeechDB.emoteWheel ~= false
end

-- The right stick (x, y), or nil: the mapped state's second stick (unverified, H34).
local function stick()
  local get, active = C_GamePad and C_GamePad.GetDeviceMappedState, C_GamePad and C_GamePad.GetActiveDeviceID
  if type(get) ~= "function" or type(active) ~= "function" then
    return nil
  end
  local state = H.Safe(get, H.Safe(active))
  local s = type(state) == "table" and type(state.sticks) == "table" and state.sticks[2]
  if type(s) == "table" and tonumber(s.x) and tonumber(s.y) then
    return s.x, s.y
  end
end

-- Building ---------------------------------------------------------------------------------------------------------

local function build()
  local Style = H.Style
  local n = #Wheel.EMOTES
  frame = CreateFrame("Frame", nil, UIParent)
  frame:SetAllPoints(UIParent)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:Hide()
  wheel = CreateFrame("Frame", nil, frame)
  wheel:SetSize(SIZE, SIZE)
  local bg = wheel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("CENTER")
  bg:SetSize(SIZE, SIZE)
  bg:SetTexture(ART.disc)
  for i = 1, n do -- a thin grey line on each wedge boundary
    local a = wedgeAngle(i, n) + math.pi / n
    local d = (LINE_FROM + SIZE / 2 - 8) / 2
    local line = wheel:CreateTexture(nil, "BORDER")
    line:SetColorTexture(0.55, 0.55, 0.55, 0.35)
    line:SetSize(SIZE / 2 - 8 - LINE_FROM, 1)
    line:SetPoint("CENTER", wheel, "CENTER", math.cos(a) * d, math.sin(a) * d)
    if line.SetRotation then
      line:SetRotation(a)
    end
  end
  -- The aimed wedge, lit as the game does it (Blizzard_RadialWheel, read for its behavior): the client's wedge
  -- highlight for n at its atlas size, turned by the wedge's angle, GLOW_OFFSET out along it; else the addon's gold
  -- cone, the wheel's size, centered, turned by the wedge's angle.
  local glow = wheel:CreateTexture(nil, "ARTWORK")
  art.atlasGlow = Style.SetAtlas(glow, "Radial_Wheel_Select_Wedge_Count_" .. n, true)
  if not art.atlasGlow then
    glow:SetTexture(ART.wedge)
    glow:SetSize(SIZE, SIZE)
  end
  glow:Hide()
  art.glow = glow
  -- The pointer, as the game's: centered on the wheel at its atlas size, turned by the aimed direction's angle.
  local pointer = wheel:CreateTexture(nil, "OVERLAY")
  pointer:SetPoint("CENTER")
  if Style.SetAtlas(pointer, "Radial_Wheel_Select_Pointer", true) then
    art.pointer = pointer
  end
  pointer:Hide()
  local centerButton = wheel:CreateTexture(nil, "ARTWORK", nil, 1)
  centerButton:SetPoint("CENTER")
  centerButton:SetSize(CENTER_SIZE, CENTER_SIZE)
  centerButton:SetTexture(ART.center)
  local cross = wheel:CreateTexture(nil, "OVERLAY")
  cross:SetPoint("CENTER")
  cross:SetSize(26, 26)
  if not Style.SetAtlas(cross, "Radial_Wheel_Icon_Close") then
    cross:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
  end
  art.icons = {}
  for i, e in ipairs(Wheel.EMOTES) do
    local a = wedgeAngle(i, n)
    local icon = wheel:CreateTexture(nil, "OVERLAY")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("CENTER", wheel, "CENTER", math.cos(a) * RADIUS, math.sin(a) * RADIUS)
    icon:SetTexture(e.icon)
    -- The name just beyond its icon, along the wedge (T60: placed by quadrant, the diagonal names sat beside their
    -- icon): its center pushed out by half its width sideways and half its height up or down, weighted by cos² and
    -- sin² (with the plain sums, the diagonal names stood too far from their icon).
    local label = wheel:CreateFontString(nil, "OVERLAY", _G.Game18Font and "Game18Font" or "GameFontHighlightLarge")
    local face, _, flags = label:GetFont()
    if face then
      label:SetFont(face, LABEL_SIZE, flags)
    end
    label:SetText(L[e.label])
    local w, h = label:GetStringWidth() or 0, label:GetStringHeight() or LABEL_SIZE
    local d = RADIUS + ICON / 2 + LABEL_GAP + math.cos(a) ^ 2 * w / 2 + math.sin(a) ^ 2 * h / 2
    label:SetPoint("CENTER", wheel, "CENTER", math.cos(a) * d, math.sin(a) * d)
    art.icons[i] = { icon = icon, label = label }
  end
  frame:SetScript("OnUpdate", function()
    Wheel.Update()
  end)
  frame:SetScript("OnMouseDown", function(_, button)
    if button == "RightButton" then
      Wheel.Close()
    else
      Wheel.Release(true)
    end
  end)
  H.Trace("emote wheel: built, atlases bg=%s wedges=%s glow=%s pointer=%s", Style.HasAtlas("Radial_Wheel_BG"),
    art.atlasWedges, art.atlasGlow, art.pointer ~= nil)
end

-- Showing the selection --------------------------------------------------------------------------------------------

-- The pointer follows the aimed direction (angle, radians from the x axis, counterclockwise; nil: hidden).
local function point(angle)
  local p = art.pointer
  if not p then
    return
  end
  p:SetShown(angle ~= nil)
  if angle and p.SetRotation then
    p:SetRotation(angle)
  end
end

local function show(i)
  if i == selected then
    return
  end
  selected = i
  local n = #Wheel.EMOTES
  for k, item in ipairs(art.icons) do
    local on = k == i
    item.icon:SetSize(on and ICON + 6 or ICON, on and ICON + 6 or ICON)
    item.label:SetTextColor(1, 1, 1)
  end
  H.Trace("emote wheel: wedge %s", tostring(i))
  local glow = art.glow
  glow:SetShown(i ~= nil)
  if not i then
    return
  end
  local angle = wedgeAngle(i, n)
  glow:ClearAllPoints()
  local out = art.atlasGlow and GLOW_OFFSET or 0
  glow:SetPoint("CENTER", wheel, "CENTER", math.cos(angle) * out, math.sin(angle) * out)
  if glow.SetRotation then
    glow:SetRotation(angle)
  end
end

-- Aims at (dx, dy) from the center: the wedge there and the pointer's direction (dead zone: none). Returns the wedge.
local function aim(dx, dy, dead)
  local i = Wheel.WedgeAt(dx, dy, #Wheel.EMOTES, dead)
  point(i and math.atan2(dy, dx) or nil)
  show(i)
  return i
end

function Wheel.Update()
  if not (frame and frame:IsShown()) then
    return
  end
  local x, y = stick()
  if x and x * x + y * y >= STICK * STICK then -- the stick pushed aims
    aim(x, y, 0)
    return
  end
  local cx, cy = GetCursorPosition()
  if not cx then
    return
  end
  if not mouseMoved and openCursor then
    mouseMoved = math.abs(cx - openCursor[1]) + math.abs(cy - openCursor[2]) > 2
  end
  -- the mouse moved: it aims (nothing in the center); otherwise the stick's last direction stays
  if mouseMoved then
    local scale = wheel:GetEffectiveScale() or 1
    local wx, wy = wheel:GetCenter()
    if wx then
      aim(cx / scale - wx, cy / scale - wy)
    end
  end
end

-- Opening, releasing -----------------------------------------------------------------------------------------------

function Wheel.Open()
  if not enabled() then
    return false
  end
  if not frame then
    build()
  end
  selected = false -- forces the first show
  wheel:ClearAllPoints()
  local mouselook = IsMouselooking and IsMouselooking()
  local cx, cy = GetCursorPosition()
  openCursor, mouseMoved = cx and { cx, cy } or nil, false
  if mouselook then
    wheel:SetPoint("CENTER", UIParent, "CENTER")
  else
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    local w, h = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    x = math.max(SIZE / 2, math.min(w - SIZE / 2, (x or 0) / scale))
    y = math.max(SIZE / 2, math.min(h - SIZE / 2, (y or 0) / scale))
    wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
  end
  point(nil)
  show(nil)
  frame:EnableMouse(true)
  frame:Show()
  pressedAt = GetTime()
  H.Trace("emote wheel: open mouselook=%s gamepad=%s", mouselook,
    tostring(C_GamePad and C_GamePad.IsEnabled and H.Safe(C_GamePad.IsEnabled)))
  return true
end

function Wheel.Close()
  if frame then
    frame:EnableMouse(false)
    frame:Hide()
  end
  pressedAt = nil
end

function Wheel.IsShown()
  return frame ~= nil and frame:IsShown()
end

-- The key released (or a left click, now = true): the emote aimed, unless the press was too short or in the center.
function Wheel.Release(now)
  if not Wheel.IsShown() then
    return nil
  end
  Wheel.Update()
  local held = GetTime() - (pressedAt or GetTime())
  local e = selected and Wheel.EMOTES[selected]
  Wheel.Close()
  if not e or (held < SHORT and not now) then
    H.Trace("emote wheel: nothing (held %.2fs, wedge %s)", held, tostring(selected))
    return nil
  end
  if DoEmote then
    local ok, err = pcall(DoEmote, e.token)
    H.Trace("emote wheel: %s target=%s ok=%s %s", e.token, UnitExists and UnitExists("target") or false, ok, err)
  end
  return e.token
end

-- The key binding: down opens, up releases.
function Wheel.OnKey(down)
  if down then
    Wheel.Open()
  else
    Wheel.Release(false)
  end
end

-- The full-screen catcher, the wheel and its textures (tests).
function Wheel.Parts()
  return frame, wheel, art
end
