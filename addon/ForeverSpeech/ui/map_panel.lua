-- ForeverSpeech: the zone story panel beside the world map (2026-10-21, D16): while the map shows a zone that has
-- Elise's introduction (index v5, zones[mapID]), a parchment page against the map's right edge with the zone's name,
-- a picture painted for the addon (media/zones/<mapID>.tga, 512 x 256, tools/zone_pictures.ts), her text and a round
-- Play / Stop button. No spoiler, as the map button: a zone not yet discovered (MapButton.Discovered) keeps its text
-- and its voice for later, its picture greyed. Shown with the map while the setting mapPanel is on (default); the
-- round button with the lines glyph in the map's corner (ui/map_button.lua) shows or hides it.
-- Built from the game's flat panel template when the client has it, else a dark tooltip frame. Under the gamepad
-- interface the panel hangs on UIParent rather than on the map: an addon frame inside the open map taints the
-- gamepad's bindings there (idea from Spoken, MIT). Unverified on Forever: T44.
local H = ForeverSpeech
local L = H.L

local MapPanel = {}
H.MapPanel = MapPanel

local WIDTH, MARGIN = 340, 14
local PICTURE_H = math.floor((WIDTH - 2 * MARGIN) / 2) -- the pictures are 2:1
local INK, INK_SOFT = { 0.25, 0.16, 0.08 }, { 0.42, 0.30, 0.18 }
local PICTURES = H.MEDIA .. "zones\\"

local panel

local function gamepad()
  return GetCVar and GetCVar("InputDeviceInterfaceStyle") == "1"
end

local function shownMap()
  local map = _G.WorldMapFrame
  if not map or type(map.GetMapID) ~= "function" then
    return nil
  end
  local ok, mapID = pcall(map.GetMapID, map)
  return ok and tonumber(mapID) or nil
end

local function ink(fs, color)
  fs:SetTextColor(color[1], color[2], color[3])
  fs:SetShadowColor(0, 0, 0, 0)
end

-- The page: parchment, title, "told by Elise", divider, picture, text, and the round Play / Stop button.
local function build(map)
  local parent = gamepad() and UIParent or map
  local f, templated
  local ok, made = pcall(CreateFrame, "Frame", nil, parent, "DefaultPanelFlatTemplate")
  if ok and made then
    f, templated = made, true
  else
    f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  end
  f:SetWidth(WIDTH)
  f:SetFrameStrata(map:GetFrameStrata() or "HIGH")
  f:SetToplevel(true)
  f:EnableMouse(true)
  if templated and f.SetTitle then
    pcall(f.SetTitle, f, L.MAP_PANEL_TITLE)
  elseif f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
  end
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", templated and 0 or -2, templated and 0 or -2)
  close:SetScript("OnClick", function()
    MapPanel.SetShown(false)
  end)

  local page = CreateFrame("Frame", nil, f)
  page:SetPoint("TOPLEFT", f, "TOPLEFT", templated and 7 or 6, templated and -25 or -26)
  page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", templated and -5 or -6, 6)
  local parchment = page:CreateTexture(nil, "BACKGROUND")
  parchment:SetAllPoints()
  parchment:SetTexture(H.Style.PARCHMENT)
  f.page = page

  f.play = H.Style.RoundButton(page, "play", 30, function()
    if not f.discovered then
      return L.MAP_PLAY_ZONE, nil, L.MAP_UNDISCOVERED
    end
    return H.Player.IsLinePlaying("zone", f.mapID) and L.TOOLTIP_STOP or L.MAP_PLAY_ZONE
  end, true) -- the page keeps its look in every theme
  f.play:SetPoint("TOPRIGHT", page, "TOPRIGHT", -MARGIN + 2, -MARGIN + 2)
  f.play:SetScript("OnClick", function()
    if not (f.mapID and f.discovered) then
      return
    end
    if H.Player.IsLinePlaying("zone", f.mapID) then
      H.Player.Stop()
    else
      H.Player.PlayLineNow("zone", f.mapID)
    end
  end)

  f.title = page:CreateFontString(nil, "OVERLAY", _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", page, "TOPLEFT", MARGIN, -MARGIN)
  f.title:SetPoint("RIGHT", f.play, "LEFT", -6, 0)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)
  ink(f.title, INK)

  f.byline = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.byline:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.byline:SetText(L.MAP_PANEL_BY)
  ink(f.byline, INK_SOFT)

  local divider = page:CreateTexture(nil, "ARTWORK")
  divider:SetTexture(H.Style.DIVIDER)
  divider:SetPoint("TOPLEFT", f.byline, "BOTTOMLEFT", -4, -4)
  divider:SetPoint("RIGHT", page, "RIGHT", -MARGIN + 4, 0)
  divider:SetHeight(12)

  local frameTex = page:CreateTexture(nil, "ARTWORK")
  frameTex:SetColorTexture(INK[1], INK[2], INK[3], 0.8)
  frameTex:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 4, -6)
  frameTex:SetSize(WIDTH - 2 * MARGIN - 12, PICTURE_H - 6)
  f.picture = page:CreateTexture(nil, "OVERLAY")
  f.picture:SetPoint("TOPLEFT", frameTex, "TOPLEFT", 1, -1)
  f.picture:SetPoint("BOTTOMRIGHT", frameTex, "BOTTOMRIGHT", -1, 1)
  f.pictureFrame = frameTex

  f.text = page:CreateFontString(nil, "OVERLAY", _G.QuestFont and "QuestFont" or "GameFontHighlight")
  f.text:SetPoint("TOPLEFT", frameTex, "BOTTOMLEFT", 0, -10)
  f.text:SetPoint("RIGHT", page, "RIGHT", -MARGIN, 0)
  f.text:SetJustifyH("LEFT")
  f.text:SetJustifyV("TOP")
  f.text:SetSpacing(2)
  ink(f.text, INK)

  -- the map's frame (its border art), else the map itself
  f.anchor = rawget(map, "BorderFrame") or map
  f:Hide()
  return f
end

local function place(f, map)
  f:ClearAllPoints()
  local maximized = type(map.IsMaximized) == "function" and map:IsMaximized()
  if maximized then -- the full-screen map leaves no room on its right: inside it, against its right edge
    f:SetPoint("TOPRIGHT", f.anchor, "TOPRIGHT", -4, -60)
    f:SetPoint("BOTTOMRIGHT", f.anchor, "BOTTOMRIGHT", -4, 40)
  else
    f:SetPoint("TOPLEFT", f.anchor, "TOPRIGHT", 2, 0)
    f:SetPoint("BOTTOMLEFT", f.anchor, "BOTTOMRIGHT", 2, 0)
  end
end

-- Shown while the setting is on, the audio on, the map open and showing a zone with an introduction.
function MapPanel.Update()
  local map = _G.WorldMapFrame
  if not (panel and map) then
    return
  end
  local mapID = shownMap()
  local zone = mapID and H.Index.Zone(mapID)
  if not zone or not map:IsShown() or not H.IsEnabled() or ForeverSpeechDB.mapPanel == false then
    panel:Hide()
    return
  end
  place(panel, map)
  panel.mapID = mapID
  panel.discovered = H.Player.IsLinePlaying("zone", mapID) or H.MapButton.Discovered(mapID)
  panel.title:SetText(zone.name or "")
  local shown = panel.picture:SetTexture(PICTURES .. mapID)
  panel.picture:SetShown(shown ~= false)
  panel.pictureFrame:SetShown(shown ~= false)
  panel.picture:SetDesaturated(not panel.discovered)
  if panel.discovered then
    panel.text:SetText(zone.text or "")
    ink(panel.text, INK)
  else
    panel.text:SetText(L.MAP_PANEL_UNDISCOVERED)
    ink(panel.text, INK_SOFT)
  end
  panel.play:SetGlyph(H.Player.IsLinePlaying("zone", mapID) and "stop" or "play")
  panel.play:SetActive(panel.discovered)
  panel:Show()
end

function MapPanel.SetShown(shown)
  ForeverSpeechDB.mapPanel = shown and true or false
  MapPanel.Update()
  if H.MapButton then
    H.MapButton.Update()
  end
end

function MapPanel.IsShown()
  return panel ~= nil and panel:IsShown()
end

function MapPanel.Frame()
  return panel
end

H.Player.OnChange(function()
  MapPanel.Update()
end)
H.OnEnabledChange(function()
  MapPanel.Update()
end)

H.WhenAvailable(function()
  local map = _G.WorldMapFrame
  return type(map) == "table" and type(map.HookScript) == "function"
end, function()
  local map = _G.WorldMapFrame
  panel = build(map)
  map:HookScript("OnShow", MapPanel.Update)
  map:HookScript("OnHide", function()
    panel:Hide()
  end)
  if type(map.OnMapChanged) == "function" then
    hooksecurefunc(map, "OnMapChanged", MapPanel.Update)
  end
  H.OnInit(MapPanel.Update)
end)
