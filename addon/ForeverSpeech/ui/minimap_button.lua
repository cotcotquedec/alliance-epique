-- ForeverSpeech: entry points to the main window from the minimap.
-- 1. The minimap "addon compartment" menu (Retail 10.1+ AddonCompartmentFrame:RegisterAddon, no
--    global needed), used when the client has it (unverified on Forever).
-- 2. Our own minimap button. Clean-room, no library (no LibDBIcon: dependencies need approval).
--    Left click toggles the window, right click opens the options, drag moves it around the
--    minimap; the angle is saved in ForeverSpeechDB.minimapAngle. Border/background textures are
--    the classic minimap button ones (unverified on Forever).
local H = ForeverSpeech
local L = H.L

local MinimapButton = {}
H.MinimapButton = MinimapButton

local SIZE = 31
local FALLBACK_RADIUS = 80 -- when the minimap has no size yet (layout not done)
local button

local function position()
  local angle = math.rad(ForeverSpeechDB.minimapAngle or 215)
  local width = Minimap:GetWidth() or 0
  local radius = width > 50 and (width / 2 + 5) or FALLBACK_RADIUS
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  if not (mx and cx) then
    return
  end
  ForeverSpeechDB.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
  position()
end

local function create()
  button = CreateFrame("Button", nil, Minimap)
  button:SetSize(SIZE, SIZE)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetSize(20, 20)
  background:SetPoint("TOPLEFT", 7, -5)
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexture(H.MEDIA .. "icon")
  -- gold when the audio is on, grey when it is off
  local function tint(enabled)
    if enabled then
      icon:SetVertexColor(1, 0.82, 0)
    else
      icon:SetVertexColor(0.5, 0.5, 0.5)
    end
  end
  tint(H.IsEnabled())
  H.OnEnabledChange(tint)
  button.icon = icon
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      H.PlayerFrame.Toggle("options")
    else
      H.PlayerFrame.Toggle()
    end
  end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", onDragUpdate)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", function(self)
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(H.TITLE)
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  MinimapButton.button = button
  H.Trace("minimap: button created")
end

-- Addon compartment entry (the minimap's addon list), registered once if the client has it.
function MinimapButton.RegisterCompartment()
  local compartment = _G.AddonCompartmentFrame
  local available = type(compartment) == "table" and type(compartment.RegisterAddon) == "function"
  H.Trace("minimap: AddonCompartmentFrame available=%s", available)
  if not available or MinimapButton.compartment then
    return available
  end
  local ok, err = pcall(compartment.RegisterAddon, compartment, {
    text = H.TITLE,
    icon = H.MEDIA .. "icon",
    notCheckable = true,
    func = function(_, menuInputData)
      if type(menuInputData) == "table" and menuInputData.buttonName == "RightButton" then
        H.PlayerFrame.Toggle("options")
      else
        H.PlayerFrame.Toggle()
      end
    end,
  })
  MinimapButton.compartment = ok
  H.Trace("minimap: compartment registered=%s %s", ok, err)
  return ok
end

function MinimapButton.Update()
  if not Minimap then
    return
  end
  if ForeverSpeechDB.minimapHide then
    if button then
      button:Hide()
    end
    return
  end
  if not button then
    create()
  end
  position()
  button:Show()
  H.Trace("minimap: shown width=%s point=%s", Minimap:GetWidth(), button:GetPoint(1))
end

H.OnInit(MinimapButton.RegisterCompartment)
-- Placed once the UI layout is done: at ADDON_LOADED the minimap may have no size yet.
H.RegisterEvent("PLAYER_ENTERING_WORLD", function()
  local ok, err = pcall(MinimapButton.Update)
  if not ok then
    H.Trace("minimap: error %s", err)
  end
end)
