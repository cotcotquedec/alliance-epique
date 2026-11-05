local wow = require("tests.lua.helpers.wow")

local FILE = "Interface\\AddOns\\ForeverSpeech\\audio\\1000000\\12_level.ogg"

local function setup()
  wow.reset()
  wow.loadAddon()
  _G.ForeverSpeechIndex = {
    version = 8, quests = {}, npcs = { [1000000] = { name = "Elise" } }, zones = {},
    levels = {
      [12] = { text = "Je m'appelle Elise.", intro = { npc = 1000000, voice = "npc1000000@G6INpmIs", file = FILE,
                                                      dur = 4.2, src = "elise" } },
      [13] = { text = "Méfiez-vous des chemins trop calmes." },
    },
  }
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  ForeverSpeechDB.gap = 0
end

describe("level-up lines", function()
  local Player
  before_each(function()
    setup()
    Player = ForeverSpeech.Player
  end)

  it("plays Elise's line 2 s after the level is gained", function()
    wow.fire("PLAYER_LEVEL_UP", 12)
    assert.equals(0, #wow.sounds)
    wow.advance(2)
    assert.equals(FILE, wow.sounds[1].path)
    assert.is_true(Player.IsLinePlaying("level", 12))
    local entries = Player.List()
    assert.equals("level", entries[1].line)
    assert.equals(12, entries[1].lineID)
  end)

  it("waits its turn behind a quest", function()
    Player.PlayQuest(5) -- test sound: busy
    wow.fire("PLAYER_LEVEL_UP", 12)
    wow.advance(2)
    assert.same({ "playing", "queued" }, { Player.List()[1].state, Player.List()[2].state })
  end)

  it("nothing by itself without audio, nor with the setting off", function()
    wow.fire("PLAYER_LEVEL_UP", 13)
    wow.advance(2)
    assert.equals(0, #wow.sounds)
    ForeverSpeechDB.levelLines = false
    wow.fire("PLAYER_LEVEL_UP", 12)
    wow.advance(2)
    assert.equals(0, #wow.sounds)
  end)

  it("shows the level in the window and the list, with its icon and her text", function()
    wow.fire("PLAYER_LEVEL_UP", 12)
    wow.advance(2)
    local PlayerFrame = ForeverSpeech.PlayerFrame
    assert.same({ "level", 12 }, { PlayerFrame.Line() })
    assert.equals("Je m'appelle Elise.", PlayerFrame.QuestText())
    local kind, texture = PlayerFrame.Visual()
    assert.equals("portrait", kind) -- her portrait in the window, the line's icon in the list
    assert.matches("media\\elise$", texture)
    local row = PlayerFrame.ListPanel().rows[1]
    assert.matches("Spell_Holy_HolyBolt$", row.icon:GetTexture())
    assert.matches("Niveau 12", row.text:GetText(), 1, true)
  end)

  it("shows the line's icon in the window when the client refuses her portrait", function()
    wow.refusedTextures["Interface\\AddOns\\ForeverSpeech\\media\\elise"] = true
    wow.fire("PLAYER_LEVEL_UP", 12)
    wow.advance(2)
    local kind, texture = ForeverSpeech.PlayerFrame.Visual()
    assert.equals("icon", kind)
    assert.matches("Spell_Holy_HolyBolt$", texture)
  end)

  it("/fs level <n> reads a line on demand, with the speech synthesis while no audio exists", function()
    local spoken
    _G.C_VoiceChat = {
      GetTtsVoices = function() return { { voiceID = 1, name = "Thomas [fr-FR]" } } end,
      SpeakText = function(_, text) spoken = text end,
    }
    wow.slash("level 13")
    assert.equals("Méfiez-vous des chemins trop calmes.", spoken)
  end)
end)
