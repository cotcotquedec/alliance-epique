local wow = require("tests.lua.helpers.wow")
local fx = require("tests.lua.fixtures.index_v9")

local SALDEAN = "Creature-0-4621-0-80-233-0000407152"

describe("NPC dialogues read in their voice", function()
  local units, gossip, Player, Dialogues, muted

  local function open(text)
    gossip = text
    wow.fire("GOSSIP_SHOW")
    wow.advance(0.1)
  end

  before_each(function()
    wow.reset()
    units = { npc = SALDEAN }
    muted = {}
    _G.UnitGUID = function(unit) return units[unit] end
    _G.UnitName = function(unit) return unit == "player" and "Jhou" or "Fermier Saldean" end
    _G.UnitClass = function() return "Guerrier", "WARRIOR" end
    _G.UnitRace = function() return "Elfe de la nuit" end
    _G.C_GossipInfo = { GetText = function() return gossip end }
    _G.MuteSoundFile = function(id) muted[id] = true end
    _G.UnmuteSoundFile = function(id) muted[id] = nil end
    wow.index = fx.build()
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    ForeverSpeechDB.gap = 0
    Player, Dialogues = ForeverSpeech.Player, ForeverSpeech.Dialogues
  end)

  it("matches the exact words once the player's name and class are removed", function()
    local page, score = Dialogues.Match(fx.NPC, "Bonjour, Jhou. Que puis-je faire pour vous, Guerrier ?")
    assert.equals("4710", page.page)
    assert.equals(1, score)
  end)

  it("removes a race of several words as a whole", function()
    assert.equals("4712", Dialogues.Match(fx.NPC, "Salut, Elfe de la nuit ! La nuit tombe.").page)
  end)

  it("matches a text that changed a little (score >= 0.7), not a different one", function()
    local page, score = Dialogues.Match(fx.NPC, "Les loups rôdent près de la grange, mon amie. Restez sur vos gardes !")
    assert.equals("4711", page.page)
    assert.is_true(score >= 0.7 and score < 1)
    assert.is_nil(Dialogues.Match(fx.NPC, "Je n'ai rien à vous dire."))
    assert.is_nil(Dialogues.Match(999, "Bonjour."))
  end)

  it("a page cut at 40 words (index size) is the same as the first 40 shown words", function()
    local shown, base = {}, {}
    for i = 1, 45 do
      shown[i] = "mot" .. i
      base[i] = i <= 40 and shown[i] or nil
    end
    ForeverSpeechIndex.dialogues[234] = { { page = "1", words = "autre chose" },
      { page = "2", words = table.concat(base, " ") } }
    local page, score = Dialogues.Match(234, table.concat(shown, ", ") .. ".")
    assert.same({ "2", 1 }, { page.page, score })
  end)

  it("plays the page in the NPC's voice 0.1 s after the window opens", function()
    gossip = "Bonjour, Jhou. Que puis-je faire pour vous, Guerrier ?"
    wow.fire("GOSSIP_SHOW")
    assert.equals(0, #wow.sounds)
    wow.advance(0.1)
    assert.equals(fx.FILE_HELLO, wow.sounds[1].path)
    local cur = Player.Current()
    assert.equals("gossip", cur.line)
    assert.equals("Fermier Saldean", ForeverSpeech.Index.Line("gossip", cur.lineID).name)
    local PlayerFrame = ForeverSpeech.PlayerFrame
    assert.same({ "gossip", cur.lineID }, { PlayerFrame.Line() })
    assert.equals("model", (PlayerFrame.Visual())) -- the NPC's model, not Elise's portrait
    assert.matches("GossipGossipIcon$", PlayerFrame.ListPanel().rows[1].icon:GetTexture())
  end)

  it("plays the female variant for a female character", function()
    _G.UnitSex = function(unit) return unit == "player" and 3 or 2 end
    open("Bonjour, Jhou. Que puis-je faire pour vous, Guerrière ?")
    assert.equals(fx.FILE_HELLO_F, wow.sounds[1].path)
  end)

  it("the next page replaces it; closing the window stops it", function()
    open("Bonjour, Jhou. Que puis-je faire pour vous, Guerrier ?")
    open("Les loups rôdent près de la ferme, mon ami. Restez sur vos gardes.")
    assert.same({ 1 }, wow.stopped)
    assert.equals(fx.FILE_WOLVES, wow.sounds[2].path)
    wow.fire("GOSSIP_CLOSED")
    assert.same({ 1, 2 }, wow.stopped)
  end)

  it("a window closed before the text settled reads nothing", function()
    gossip = "Bonjour, Jhou. Que puis-je faire pour vous, Guerrier ?"
    wow.fire("GOSSIP_SHOW")
    wow.fire("GOSSIP_CLOSED")
    wow.advance(0.2)
    assert.equals(0, #wow.sounds)
  end)

  it("nothing without a matching page (no speech synthesis), nor with the setting off", function()
    local spoken
    _G.C_VoiceChat = {
      GetTtsVoices = function() return { { voiceID = 1, name = "Thomas [fr-FR]" } } end,
      SpeakText = function(_, text) spoken = text end,
    }
    open("Je n'ai rien à vous dire.")
    assert.equals(0, #wow.sounds)
    assert.is_nil(spoken)
    wow.slash("gossip off")
    assert.is_false(ForeverSpeechDB.readGossip)
    open("Bonjour, Jhou. Que puis-je faire pour vous, Guerrier ?")
    assert.equals(0, #wow.sounds)
    assert.is_true(next(ForeverSpeechCaptures.gossip) ~= nil) -- the capture goes on
  end)

  it("mutes the game's greeting of an NPC whose dialogue has audio", function()
    units.mouseover = SALDEAN
    wow.fire("UPDATE_MOUSEOVER_UNIT")
    assert.is_true(muted[543353])
    units.mouseover = nil
    wow.tick(0.2)
    assert.is_nil(muted[543353])
    ForeverSpeechDB.readGossip = false
    units.mouseover = SALDEAN
    wow.fire("UPDATE_MOUSEOVER_UNIT")
    assert.is_nil(muted[543353])
  end)
end)
