local wow = require("tests.lua.helpers.wow")

local FILE = "Interface\\AddOns\\ForeverSpeech\\audio\\1000000\\12_level.ogg"

describe("silence in battlegrounds and arenas", function()
  local instance, Player

  before_each(function()
    wow.reset()
    instance = { false, "none" }
    _G.IsInInstance = function() return instance[1], instance[2] end
    wow.loadAddon()
    _G.ForeverSpeechIndex = {
      version = 9, quests = {}, npcs = { [1000000] = { name = "Elise" } }, zones = {},
      levels = { [12] = { text = "Je m'appelle Elise.",
                          intro = { npc = 1000000, file = FILE, dur = 4, src = "elise" } } },
    }
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    ForeverSpeechDB.gap = 0
    Player = ForeverSpeech.Player
  end)

  it("nothing the addon starts by itself plays in a battleground", function()
    instance = { true, "pvp" }
    assert.is_true(ForeverSpeech.Silence.Active())
    wow.fire("PLAYER_LEVEL_UP", 12)
    wow.advance(2)
    assert.equals(0, #wow.sounds)
    assert.same({ "failed", "battleground" }, { Player.PlayQuest(5, nil, Player.AUTO) })
    assert.same({ "failed", "battleground" }, { Player.PlayLineNow("level", 12, Player.AUTO) })
  end)

  it("nor in an arena; a dungeon is not concerned", function()
    instance = { true, "arena" }
    assert.same({ "failed", "battleground" }, { Player.PlayLine("level", 12, Player.AUTO) })
    instance = { true, "party" }
    assert.equals("playing", (Player.PlayLine("level", 12, Player.AUTO)))
  end)

  it("what the player asks for still plays", function()
    instance = { true, "pvp" }
    wow.slash("level 12")
    assert.equals(FILE, wow.sounds[1].path)
    assert.equals("queued", (Player.PlayQuest(5)))
  end)

  it("entering one drops what the addon queued by itself, and stops it if it plays", function()
    Player.PlayLine("level", 12, Player.AUTO) -- plays
    Player.PlayQuest(5) -- asked: queued
    Player.PlayQuest(6, nil, Player.AUTO) -- auto: queued
    instance = { true, "pvp" }
    wow.fire("PLAYER_ENTERING_WORLD")
    assert.is_true(Player.IsPlaying(5)) -- the level line stopped, the asked quest goes on
    assert.equals(0, #Player.Queue())
  end)

  it("the setting lifts it", function()
    instance = { true, "pvp" }
    ForeverSpeechDB.readInBattleground = true
    assert.is_false(ForeverSpeech.Silence.Active())
    wow.fire("PLAYER_LEVEL_UP", 12)
    wow.advance(2)
    assert.equals(FILE, wow.sounds[1].path)
  end)
end)
