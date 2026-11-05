local wow = require("tests.lua.helpers.wow")

local ELWYNN, KALIMDOR = 1429, 1414
local INTRO = "Interface\\AddOns\\ForeverSpeech\\audio\\1000000\\12_zone.ogg"

-- The world map shown on `mapID`, the addon loaded with Elise's introduction of Elwynn.
local function load(mapID, explored)
  wow.reset()
  _G.WorldMapFrame = wow.newRegion("Frame")
  _G.WorldMapFrame.GetMapID = function() return wow.shownMap end
  _G.WorldMapFrame:Show()
  wow.shownMap = mapID
  wow.loadAddon()
  _G.ForeverSpeechIndex = {
    version = 9, quests = {}, npcs = { [1000000] = { name = "Elise" } }, levels = {},
    zones = { [ELWYNN] = { area = 12, name = "Forêt d'Elwynn", text = "Sous les grands chênes.",
                           intro = { npc = 1000000, file = INTRO, dur = 30.5, src = "elise" } } },
  }
  _G.C_MapExplorationInfo = { GetExploredMapTextures = function() return explored and { {} } or {} end }
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  ForeverSpeechDB.gap = 0
  ForeverSpeech.MapButton.Update()
  return ForeverSpeech.MapPanel.Frame()
end

describe("zone story panel", function()
  it("shows Elise's text and the zone's picture beside a discovered zone, and plays it", function()
    local panel = load(ELWYNN, true)
    assert.is_true(panel:IsShown())
    assert.equals("Forêt d'Elwynn", panel.title:GetText())
    assert.equals("Sous les grands chênes.", panel.text:GetText())
    assert.matches("media\\zones\\1429$", panel.picture:GetTexture())
    panel.play:Click()
    assert.equals(INTRO, wow.sounds[#wow.sounds].path)
    assert.matches("glyph_stop$", panel.play.glyph:GetTexture())
  end)

  it("keeps the text and the voice of an undiscovered zone for later", function()
    local panel = load(ELWYNN, false)
    assert.is_true(panel:IsShown())
    assert.equals(ForeverSpeech.L.MAP_PANEL_UNDISCOVERED, panel.text:GetText())
    panel.play:Click()
    assert.equals(0, #wow.sounds)
  end)

  it("hides on a map without introduction, and with the setting off", function()
    local panel = load(KALIMDOR, true)
    assert.is_false(panel:IsShown())
    wow.shownMap = ELWYNN
    ForeverSpeech.MapButton.Update()
    assert.is_true(panel:IsShown())
    ForeverSpeech.MapPanel.SetShown(false)
    assert.is_false(panel:IsShown())
    assert.is_false(ForeverSpeechDB.mapPanel)
    ForeverSpeech.MapPanel.SetShown(true)
    assert.is_true(panel:IsShown())
  end)

  it("hides its picture when the client refuses the file", function()
    local panel = load(ELWYNN, true)
    wow.refusedTextures["Interface\\AddOns\\ForeverSpeech\\media\\zones\\1429"] = true
    ForeverSpeech.MapPanel.Update()
    assert.is_false(panel.picture:IsShown())
  end)
end)
