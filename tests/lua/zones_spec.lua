local wow = require("tests.lua.helpers.wow")

local ELWYNN, WESTFALL, GOLDSHIRE_MAP = 1429, 1436, 9001
local INTRO = "Interface\\AddOns\\ForeverSpeech\\audio\\1000000\\12_zone.ogg"

local function setup()
  wow.reset()
  wow.loadAddon()
  _G.ForeverSpeechIndex = {
    version = 8, quests = {}, npcs = { [1000000] = { name = "Elise" } },
    zones = {
      [ELWYNN] = { area = 12, name = "Forêt d'Elwynn", nameEn = "Elwynn Forest", text = "Sous les grands chênes.",
                   intro = { npc = 1000000, voice = "npc1000000@G6INpmIs", file = INTRO, dur = 30.5, src = "elise" } },
      [WESTFALL] = { area = 40, name = "Marche de l'Ouest", nameEn = "Westfall", text = "Les blés ont séché." },
    },
  }
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  ForeverSpeechDB.gap = 0
  _G.UnitName = function() return "Jhou" end
  _G.GetRealmName = function() return "Forever" end
  wow.map = ELWYNN
  wow.taxi = false
  wow.parents = {}
  _G.C_Map = {
    GetBestMapForUnit = function() return wow.map end,
    GetMapInfo = function(mapID)
      return wow.parents[mapID] and { mapType = 5, parentMapID = wow.parents[mapID] } or { mapType = 3 }
    end,
  }
  _G.UnitOnTaxi = function() return wow.taxi end
end

local function arrive()
  wow.fire("ZONE_CHANGED_NEW_AREA")
  wow.advance(ForeverSpeech.Zones.STAY + 1)
end

describe("zone introductions", function()
  local Player, Zones
  before_each(function()
    setup()
    Player, Zones = ForeverSpeech.Player, ForeverSpeech.Zones
  end)

  it("plays Elise's introduction the first time the character enters a zone, never again", function()
    arrive()
    assert.equals(INTRO, wow.sounds[#wow.sounds].path)
    assert.is_true(Player.IsLinePlaying("zone", ELWYNN))
    assert.is_true(Zones.Seen(ELWYNN))
    assert.is_true(ForeverSpeechDB.zonesSeen["Jhou-Forever"][ELWYNN] ~= nil)
    local count = #wow.sounds
    Player.Stop()
    arrive()
    assert.equals(count, #wow.sounds)
  end)

  it("waits for the landing on a flight path, then plays in the zone landed in", function()
    wow.taxi = true
    arrive()
    assert.equals(0, #wow.sounds)
    assert.is_false(Zones.Seen(ELWYNN))
    wow.advance(10) -- still flying: nothing
    assert.equals(0, #wow.sounds)
    wow.taxi = false
    wow.advance(3) -- the taxi poll sees the ground: the stay in the zone starts
    assert.equals(0, #wow.sounds)
    wow.advance(Zones.STAY)
    assert.equals(INTRO, wow.sounds[1].path)
  end)

  it("waits two minutes in the zone; a new zone before that starts the wait again", function()
    assert.equals(120, Zones.STAY)
    wow.fire("PLAYER_ENTERING_WORLD") -- a first login: the game's cinematic plays first
    wow.advance(100)
    assert.equals(0, #wow.sounds)
    wow.fire("ZONE_CHANGED_NEW_AREA") -- left for another zone (here the same map: the wait starts again)
    wow.advance(100)
    assert.equals(0, #wow.sounds)
    wow.advance(21)
    assert.equals(INTRO, wow.sounds[1].path)
  end)

  it("a cinematic or a movie still playing delays her introduction to its end", function()
    local cinematic = true
    _G.InCinematic = function() return cinematic end
    _G.MovieFrame = wow.newRegion("Frame")
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.advance(Zones.STAY + 1)
    assert.equals(0, #wow.sounds)
    cinematic = false
    _G.MovieFrame:Show() -- then a movie
    wow.advance(30)
    assert.equals(0, #wow.sounds)
    _G.MovieFrame:Hide()
    wow.advance(5)
    assert.equals(INTRO, wow.sounds[1].path)
    _G.InCinematic, _G.MovieFrame = nil, nil
  end)

  it("climbs from a child map (a district, a cave) to its zone", function()
    wow.map, wow.parents[GOLDSHIRE_MAP] = GOLDSHIRE_MAP, ELWYNN
    assert.equals(ELWYNN, Zones.CurrentMap())
    arrive()
    assert.is_true(Zones.Seen(ELWYNN))
  end)

  it("finds the zone by its name when the client gives no map", function()
    _G.C_Map = nil
    _G.GetRealZoneText = function() return "Forêt d’Elwynn" end
    local mapID, _, how = Zones.Current()
    assert.equals(ELWYNN, mapID)
    assert.equals("name", how)
  end)

  it("plays nothing by itself for a zone without audio yet, and does not count it as seen", function()
    wow.map = WESTFALL
    arrive()
    assert.equals(0, #wow.sounds)
    assert.is_false(Zones.Seen(WESTFALL))
  end)

  it("reads the text with the speech synthesis on demand (/fs zone) while no audio exists", function()
    local spoken
    _G.C_VoiceChat = {
      GetTtsVoices = function() return { { voiceID = 1, name = "Thomas [fr-FR]" } } end,
      SpeakText = function(_, text) spoken = text end,
    }
    wow.map = WESTFALL
    wow.slash("zone")
    assert.equals("Les blés ont séché.", spoken)
    assert.is_true(Player.IsLinePlaying("zone", WESTFALL))
  end)

  it("queues behind a quest, with the zone in the play list", function()
    Player.PlayQuest(5) -- test sound fallback: busy
    arrive()
    local entries = Player.List()
    assert.equals("zone", entries[2].line)
    assert.equals(ELWYNN, entries[2].lineID)
    assert.equals("queued", entries[2].state)
    assert.is_true(Zones.Seen(ELWYNN))
  end)

  it("stays silent when the setting is off, or the audio off", function()
    ForeverSpeechDB.zoneIntros = false
    arrive()
    assert.equals(0, #wow.sounds)
    ForeverSpeechDB.zoneIntros = true
    ForeverSpeech.SetEnabled(false)
    arrive()
    assert.equals(0, #wow.sounds)
    assert.is_false(Zones.Seen(ELWYNN))
  end)

  it("/fs zone reset forgets the zones seen by this character", function()
    arrive()
    Player.Stop()
    wow.slash("zone reset")
    assert.is_false(Zones.Seen(ELWYNN))
  end)

  it("shows the zone in the window and the list, with the map icon", function()
    arrive()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    assert.same({ "zone", ELWYNN }, { PlayerFrame.Line() })
    assert.is_nil(PlayerFrame.QuestID())
    local row = PlayerFrame.ListPanel().rows[1]
    assert.equals("zone", row.line)
    assert.equals(ELWYNN, row.lineID)
    assert.matches("INV_Misc_Map_01$", row.icon:GetTexture())
    assert.matches("Forêt d'Elwynn", row.text:GetText(), 1, true)
    local f = PlayerFrame.ListPanel():GetParent()
    assert.equals("Sous les grands chênes.", PlayerFrame.QuestText())
    local count = #wow.sounds
    f.playButton:Click() -- plays it again from the start
    assert.equals(count + 1, #wow.sounds)
    assert.equals(INTRO, wow.sounds[#wow.sounds].path)
  end)
end)

describe("world map button", function()
  local function load(mapID)
    wow.reset()
    _G.WorldMapFrame = wow.newRegion("Frame")
    _G.WorldMapFrame.GetMapID = function() return wow.shownMap end
    wow.shownMap = mapID
    wow.loadAddon()
    _G.ForeverSpeechIndex = {
      version = 8, quests = {}, npcs = {}, levels = {},
      zones = { [ELWYNN] = { area = 12, name = "Forêt d'Elwynn", text = "Sous les grands chênes.",
                             intro = { npc = 1000000, file = INTRO, dur = 30.5, src = "elise" } } },
    }
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    ForeverSpeechDB.gap = 0
    return ForeverSpeech.MapButton
  end

  it("installs at load time without error when the map shows a zone of the index (before SavedVariables)", function()
    wow.reset()
    _G.WorldMapFrame = wow.newRegion("Frame")
    _G.WorldMapFrame.GetMapID = function() return ELWYNN end
    wow.index = { -- loaded before the addon's code, as in the client
      version = 8, quests = {}, npcs = {}, levels = {},
      zones = { [ELWYNN] = { area = 12, name = "Forêt d'Elwynn", text = "Sous les grands chênes.",
                             intro = { npc = 1000000, file = INTRO, dur = 30.5, src = "elise" } } },
    }
    wow.loadAddon() -- raised "attempt to index global 'ForeverSpeechDB'" (2026-10-14)
    _G.C_MapExplorationInfo = { GetExploredMapTextures = function() return { {} } end }
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    local b = ForeverSpeech.MapButton.Button()
    assert.is_true(b:IsShown())
    assert.is_true(b.discovered)
  end)

  it("shows on a zone with an introduction and plays it again, a second click stops it", function()
    local MapButton = load(ELWYNN)
    _G.C_MapExplorationInfo = { GetExploredMapTextures = function() return { {} } end } -- a part explored
    MapButton.Update()
    local b = MapButton.Button()
    assert.is_true(b:IsShown())
    assert.matches("glyph_play$", b.glyph:GetTexture())
    b:GetScript("OnClick")(b)
    assert.equals(INTRO, wow.sounds[#wow.sounds].path)
    assert.matches("glyph_stop$", b.glyph:GetTexture())
    b:GetScript("OnClick")(b)
    assert.is_false(ForeverSpeech.Player.IsBusy())
    assert.matches("glyph_play$", b.glyph:GetTexture())
  end)

  it("hides on a map without introduction (a continent, a city district) and follows the map shown", function()
    local MapButton = load(1415)
    MapButton.Update()
    assert.is_false(MapButton.Button():IsShown())
    wow.shownMap = ELWYNN
    _G.WorldMapFrame._scripts.OnUpdate(_G.WorldMapFrame, 1) -- the poll while the map is open
    assert.is_true(MapButton.Button():IsShown())
  end)

  it("no spoiler: an undiscovered zone is greyed and does not play, a heard or explored one does", function()
    local MapButton = load(ELWYNN)
    _G.C_MapExplorationInfo = { GetExploredMapTextures = function() return {} end } -- nothing explored yet
    MapButton.Update()
    local b = MapButton.Button()
    assert.is_true(b:IsShown())
    assert.is_false(b.discovered)
    b:GetScript("OnClick")(b)
    assert.equals(0, #wow.sounds)
    _G.UnitName = function() return "Jhou" end
    _G.GetRealmName = function() return "Forever" end
    ForeverSpeech.Zones.MarkSeen(ELWYNN) -- its introduction heard on arrival
    MapButton.Update()
    assert.is_true(b.discovered)
    b:GetScript("OnClick")(b)
    assert.equals(INTRO, wow.sounds[#wow.sounds].path)
  end)
end)
