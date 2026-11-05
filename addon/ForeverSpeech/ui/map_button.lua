-- ForeverSpeech: play/stop button in the top right corner of the world map's map area (2026-10-12): while the map
-- shows a zone that has Elise's introduction (index v5, zones[mapID]), it plays that introduction again, from the
-- start (PlayLineNow); a second click stops it. Hidden on any other map, and while the audio is off. No spoiler: only
-- for a zone discovered (its introduction already heard, Zones.Seen, or a part of it explored on the map,
-- C_MapExplorationInfo.GetExploredMapTextures, unverified on Forever); else greyed, with a hint. No grey square on
-- hover: the icon brightens instead.
-- 2026-10-21: a round button of the addon's set (ui/style.lua), and a second one beside it, the lines glyph, that
-- shows or hides the zone story panel (ui/map_panel.lua). Under the gamepad interface both hang on UIParent, above
-- the map: an addon button inside the open map taints the gamepad's bindings (idea from Spoken, MIT).
-- S4: the quest log is part of the map on Forever (WorldMapFrame > QuestMapFrame), so WorldMapFrame exists.
-- Unverified on Forever: WorldMapFrame:GetMapID() and its OnMapChanged method (Retail's MapCanvasMixin); the button
-- also follows the map shown with a light poll while the map is open, so either is enough.
local H = ForeverSpeech
local L = H.L

local MapButton = {}
H.MapButton = MapButton

local SIZE = 28
local POLL = 0.5 -- seconds between two looks at the map shown, while the map is open

local button, storyButton
local onUIParent = false -- the gamepad interface: the buttons hang on UIParent, shown only with the map

-- Discovered: its introduction already heard by this character, or a part of it explored (the map's fog lifted).
function MapButton.Discovered(mapID)
  if H.Zones and H.Zones.Seen(mapID) then
    return true
  end
  local api = C_MapExplorationInfo
  if api and api.GetExploredMapTextures then
    local ok, textures = pcall(api.GetExploredMapTextures, mapID)
    return ok and type(textures) == "table" and #textures > 0
  end
  return false
end

local function shownMap()
  local map = _G.WorldMapFrame
  if not map or type(map.GetMapID) ~= "function" then
    return nil
  end
  local ok, mapID = pcall(map.GetMapID, map)
  return ok and tonumber(mapID) or nil
end

function MapButton.Update()
  if not button then
    return
  end
  if H.MapPanel then
    H.MapPanel.Update()
  end
  local mapID = shownMap()
  local zone = mapID and H.Index.Zone(mapID)
  button.mapID = zone and mapID or nil
  local map = _G.WorldMapFrame
  if not zone or not H.IsEnabled() or (ForeverSpeechDB and ForeverSpeechDB.mapButton == false)
    or (onUIParent and map and not map:IsShown()) then
    button:Hide()
    storyButton:Hide()
    return
  end
  local playing = H.Player.IsLinePlaying("zone", mapID)
  button.discovered = playing or MapButton.Discovered(mapID)
  button:SetGlyph(playing and "stop" or "play")
  button.glyph:SetDesaturated(not button.discovered)
  button:Show()
  storyButton:SetShown(H.MapPanel ~= nil)
  storyButton.glyph:SetVertexColor(1, 1, 1, ForeverSpeechDB.mapPanel == false and 0.55 or 1)
end

local function onClick(self)
  if not self.mapID or not self.discovered then
    return
  end
  if H.Player.IsLinePlaying("zone", self.mapID) then
    H.Player.Stop()
  else
    H.Player.PlayLineNow("zone", self.mapID)
  end
  MapButton.Update()
end

local function install(map)
  -- Inside the map itself, its top right corner (2026-10-12: anchored to the window, the button was hidden behind its
  -- border): the map area is WorldMapFrame.ScrollContainer (Retail), else the window. Above the map's layers and pins.
  local area = rawget(map, "ScrollContainer") or map
  local gamepad = GetCVar and GetCVar("InputDeviceInterfaceStyle") == "1"
  local parent = gamepad and UIParent or map
  onUIParent = gamepad
  button = H.Style.RoundButton(parent, "play", SIZE, function(self)
    local hint = not self.discovered and L.MAP_UNDISCOVERED
      or H.Player.IsLinePlaying("zone", self.mapID) and L.TOOLTIP_STOP or L.MAP_PLAY_ZONE
    return (H.Index.Zone(self.mapID) or {}).name or "", nil, hint
  end, true) -- the game's map: its own look in every theme
  button.tooltipAnchor = "ANCHOR_LEFT"
  button:SetPoint("TOPRIGHT", area, "TOPRIGHT", -10, -10)
  button:SetFrameStrata("FULLSCREEN_DIALOG")
  button:SetToplevel(true)
  button:SetScript("OnClick", onClick)
  button:Hide()
  storyButton = H.Style.RoundButton(parent, "list", SIZE, function()
    return ForeverSpeechDB.mapPanel == false and L.MAP_PANEL_SHOW or L.MAP_PANEL_HIDE
  end, true)
  storyButton.tooltipAnchor = "ANCHOR_LEFT"
  storyButton:SetPoint("RIGHT", button, "LEFT", -6, 0)
  storyButton:SetFrameStrata("FULLSCREEN_DIALOG")
  storyButton:SetToplevel(true)
  storyButton:SetScript("OnClick", function()
    H.MapPanel.SetShown(ForeverSpeechDB.mapPanel == false)
  end)
  storyButton:Hide()
  if gamepad then -- on UIParent: hide with the map
    map:HookScript("OnHide", MapButton.Update)
  end
  if type(map.OnMapChanged) == "function" then
    hooksecurefunc(map, "OnMapChanged", MapButton.Update)
  end
  local since = 0
  map:HookScript("OnShow", MapButton.Update)
  map:HookScript("OnUpdate", function(_, dt)
    since = since + dt
    if since >= POLL then
      since = 0
      MapButton.Update()
    end
  end)
  H.Trace("map: button installed, GetMapID=%s OnMapChanged=%s area=%s", type(map.GetMapID), type(map.OnMapChanged),
    area == map and "window" or "ScrollContainer")
  -- the map may exist before ADDON_LOADED (then installed at load time): its zones seen are not loaded yet
  H.OnInit(MapButton.Update)
end

function MapButton.Button()
  return button
end

H.Player.OnChange(function()
  MapButton.Update()
end)
H.OnEnabledChange(function()
  MapButton.Update()
end)

H.WhenAvailable(function()
  local map = _G.WorldMapFrame
  return type(map) == "table" and type(map.HookScript) == "function"
end, function()
  install(_G.WorldMapFrame)
end)
