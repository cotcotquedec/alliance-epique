local wow = require("tests.lua.helpers.wow")

local TEXT = "Un groupe de voleurs traîne depuis peu autour de Northshire."

local function setupQuestDetail()
  _G.GetQuestID = function() return 18 end
  _G.GetQuestText = function() return TEXT end
  _G.GetTitleText = function() return "La confrérie des voleurs" end
  _G.GetObjectiveText = function() return "Apporter 12 Masques rouges." end
  _G.UnitGUID = function(unit)
    if unit == "npc" then return "Creature-0-4621-0-80-823-0000407152" end
  end
  _G.UnitName = function(unit)
    if unit == "npc" then return "Adjoint Willem" end
    if unit == "player" then return "Cotcot" end
  end
  _G.UnitClass = function() return "Paladin", "PALADIN", 2 end
  _G.UnitRace = function() return "Humaine", "Human", 1 end
  _G.UnitSex = function(unit) return unit == "npc" and 2 or 3 end
  _G.UnitCreatureType = function() return "Humanoïde", 7 end
  _G.GetZoneText = function() return "Forêt d'Elwynn" end
end

describe("Capture", function()
  local Capture
  before_each(function()
    wow.reset()
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    setupQuestDetail()
    Capture = ForeverSpeech.Capture
  end)

  it("parses creature GUIDs (format verified in S4)", function()
    assert.same({ "Creature", 823 }, { Capture.ParseGUID("Creature-0-4621-0-80-823-0000407152") })
    assert.same({ "GameObject", 562131 }, { Capture.ParseGUID("GameObject-0-4621-0-80-562131-0000ABCD") })
    assert.same({}, { Capture.ParseGUID(nil) })
  end)

  it("hashes deterministically to 8 hex digits", function()
    assert.equals(Capture.Hash("abc"), Capture.Hash("abc"))
    assert.not_equals(Capture.Hash("abc"), Capture.Hash("abd"))
    assert.matches("^%x%x%x%x%x%x%x%x$", Capture.Hash(TEXT))
  end)

  it("records the quest at QUEST_DETAIL", function()
    wow.fire("QUEST_DETAIL", 0)
    local rec = ForeverSpeechCaptures.quests[18][1]
    assert.equals(1, ForeverSpeechCaptures.version)
    assert.equals(TEXT, rec.text)
    assert.equals("La confrérie des voleurs", rec.title)
    assert.equals(823, rec.npcID)
    assert.equals("Creature", rec.giverType)
    assert.equals("Adjoint Willem", rec.giverName)
    assert.equals(2, rec.npcSex)
    assert.equals(3, rec.playerSex)
    assert.equals("Cotcot", rec.playerName)
    assert.equals("Paladin", rec.playerClass)
    assert.equals("Humaine", rec.playerRace)
    assert.equals(7, rec.npcCreatureTypeID)
    assert.is_nil(rec.startItemID)
    assert.equals("1.60.1.70205", rec.client)
    assert.equals(1, rec.seen)
  end)

  it("deduplicates the same text and counts sightings", function()
    wow.fire("QUEST_DETAIL", 0)
    wow.fire("QUEST_DETAIL", 0)
    assert.equals(1, #ForeverSpeechCaptures.quests[18])
    assert.equals(2, ForeverSpeechCaptures.quests[18][1].seen)
  end)

  it("completes an old capture of the same text with its rewards", function()
    ForeverSpeechCaptures.quests = { [18] = { {
      questID = 18, text = TEXT, hash = ForeverSpeech.Capture.Hash(TEXT), seen = 12, lastSeen = 1,
    } } }
    _G.GetRewardMoney = function() return 75 end
    wow.fire("QUEST_DETAIL", 0)
    local rec = ForeverSpeechCaptures.quests[18][1]
    assert.equals(1, #ForeverSpeechCaptures.quests[18])
    assert.equals(13, rec.seen)
    assert.equals(75, rec.rewards.money)
    assert.is_not_nil(rec.playerName) -- other fields added since are filled in too
  end)

  it("keeps a second record when the text differs", function()
    wow.fire("QUEST_DETAIL", 0)
    _G.GetQuestText = function() return TEXT .. " Variante." end
    wow.fire("QUEST_DETAIL", 0)
    assert.equals(2, #ForeverSpeechCaptures.quests[18])
  end)

  it("stores an object giver without npcID and an item start", function()
    _G.UnitGUID = function() return "GameObject-0-4621-0-80-562131-0000ABCD" end
    wow.fire("QUEST_DETAIL", 247824)
    local rec = ForeverSpeechCaptures.quests[18][1]
    assert.is_nil(rec.npcID)
    assert.equals(562131, rec.giverID)
    assert.equals(247824, rec.startItemID)
  end)

  it("ignores a detail without quest text", function()
    _G.GetQuestText = function() return "" end
    wow.fire("QUEST_DETAIL", 0)
    assert.is_nil(ForeverSpeechCaptures.quests)
  end)

  it("/fs captures reports the counts", function()
    wow.fire("QUEST_DETAIL", 0)
    wow.slash("captures")
    assert.matches("1 quest(s) captured, 1 text(s)", wow.chatText(), 1, true)
  end)

  it("/fs captures lists the latest quests with their ID", function()
    wow.fire("QUEST_DETAIL", 0)
    wow.slash("captures")
    assert.matches("18 - La confrérie des voleurs", wow.chatText(), 1, true)
  end)

  it("/fs play without argument plays the last opened quest", function()
    wow.fire("QUEST_DETAIL", 0)
    wow.slash("play")
    assert.matches("playing quest 18 (test)", wow.chatText(), 1, true)
  end)

  it("/fs play without argument and no capture explains what to do", function()
    wow.slash("play")
    assert.matches("no quest captured yet", wow.chatText(), 1, true)
  end)

  it("Latest returns the most recently seen text", function()
    Capture.Record({ questID = 5, text = "old" })
    local newer = { questID = 5, text = "new" }
    Capture.Record(newer)
    newer.lastSeen = newer.lastSeen + 10
    assert.equals("new", Capture.Latest(5).text)
    assert.is_nil(Capture.Latest(6))
  end)
  it("captures the NPC dialogue at GOSSIP_SHOW, deduplicated (spike S11)", function()
    _G.C_GossipInfo = {
      GetText = function() return "Hé ! Vous m'avez l'air d'être costaud." end,
      GetOptions = function() return { { name = "Je voudrais acheter quelque chose." } } end,
    }
    wow.fire("GOSSIP_SHOW")
    wow.fire("GOSSIP_SHOW")
    local list = ForeverSpeechCaptures.gossip["Creature:823"]
    assert.equals(1, #list)
    assert.equals("Hé ! Vous m'avez l'air d'être costaud.", list[1].text)
    assert.equals("C_GossipInfo.GetText", list[1].api)
    assert.equals(823, list[1].npcID)
    assert.equals("Adjoint Willem", list[1].name)
    assert.same({ "Je voudrais acheter quelque chose." }, list[1].options)
    assert.equals(2, list[1].seen)
  end)

  it("falls back to GetGossipText, and records nothing without a text", function()
    _G.C_GossipInfo = { GetText = function() return "" end }
    _G.GetGossipText = function() return "Salutations." end
    wow.fire("GOSSIP_SHOW")
    assert.equals("GetGossipText", ForeverSpeechCaptures.gossip["Creature:823"][1].api)
    _G.GetGossipText = function() return nil end
    _G.UnitGUID = function() return "Creature-0-4621-0-80-197-0000407152" end
    wow.fire("GOSSIP_SHOW")
    assert.is_nil(ForeverSpeechCaptures.gossip["Creature:197"])
    _G.GetGossipText = nil
  end)
end)
