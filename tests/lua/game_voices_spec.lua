local wow = require("tests.lua.helpers.wow")

-- Adjoint Willem (823) gives quest 18, Maréchal McBride (197) is its ender.
local WILLEM = "Creature-0-4621-0-80-823-0000407152"
local MCBRIDE = "Creature-0-4621-0-80-197-0000407152"

describe("the game's NPC voices", function()
  local mutedFiles, units, log, done, complete

  local function load(withApi)
    wow.reset()
    mutedFiles, units, log, done, complete = {}, {}, {}, {}, {}
    if withApi then
      _G.MuteSoundFile = function(id) mutedFiles[id] = true end
      _G.UnmuteSoundFile = function(id) mutedFiles[id] = nil end
    end
    _G.UnitGUID = function(unit) return units[unit] end
    _G.C_QuestLog = {
      GetLogIndexForQuestID = function(questID) return log[questID] end,
      IsQuestFlaggedCompleted = function(questID) return done[questID] == true end,
      IsComplete = function(questID) return complete[questID] == true end,
    }
    wow.loadAddon()
    ForeverSpeechIndex.quests[18] = { giver = 823, ender = 197 }
    wow.fire("ADDON_LOADED", "ForeverSpeech")
  end

  after_each(function()
    _G.C_QuestLog, _G.C_GossipInfo = nil, nil
  end)

  local function hover(guid)
    units.mouseover = guid
    wow.fire("UPDATE_MOUSEOVER_UNIT")
  end

  local function isMuted()
    return mutedFiles[543353] == true and mutedFiles[543355] == true
  end

  it("stay on when no NPC with a quest is at hand", function()
    load(true)
    assert.is_true(ForeverSpeechDB.muteGameVoices)
    assert.same({}, mutedFiles)
    hover(MCBRIDE) -- ender of a quest not in the log
    assert.is_false(isMuted())
  end)

  it("are muted while the mouse is over an NPC with a quest to give, back once it leaves", function()
    load(true)
    hover(WILLEM)
    assert.is_true(isMuted())
    units.mouseover = nil
    wow.tick(0.2)
    assert.is_false(isMuted())
  end)

  it("a quest done or taken leaves the giver's voice; ready to turn in mutes the ender", function()
    load(true)
    done[18] = true
    hover(WILLEM)
    assert.is_false(isMuted())
    done[18], log[18] = nil, 3
    hover(WILLEM)
    assert.is_false(isMuted()) -- in the log: nothing to give
    hover(MCBRIDE)
    assert.is_false(isMuted()) -- not ready to turn in yet
    complete[18] = true
    wow.fire("QUEST_LOG_UPDATE")
    wow.tick(0.2)
    assert.is_true(isMuted())
  end)

  it("the open window decides, and the farewell stays muted 2 s after a quest window closes", function()
    load(true)
    units.npc = WILLEM
    hover(WILLEM)
    wow.fire("QUEST_DETAIL", 0)
    assert.is_true(isMuted())
    units.mouseover = nil
    wow.fire("QUEST_FINISHED")
    wow.tick(0.2, 9)
    assert.is_true(isMuted()) -- the farewell
    wow.tick(0.2, 2)
    assert.is_false(isMuted())
  end)

  it("learns an NPC whose window shows no quest to take, until the quest log changes", function()
    load(true)
    _G.C_GossipInfo = {
      GetAvailableQuests = function() return {} end,
      GetActiveQuests = function() return {} end,
    }
    units.npc = WILLEM
    hover(WILLEM) -- the index says yes (no level nor class there)
    assert.is_true(isMuted())
    wow.fire("GOSSIP_SHOW")
    assert.is_false(isMuted()) -- the window says no
    wow.fire("GOSSIP_CLOSED")
    wow.tick(0.2, 12)
    assert.is_false(isMuted()) -- no farewell hold, and learned while still hovered
    wow.fire("QUEST_ACCEPTED", 99)
    wow.tick(0.2)
    assert.is_true(isMuted())
  end)

  it("come back when the option is turned off or the audio is off", function()
    load(true)
    hover(WILLEM)
    assert.is_true(isMuted())
    wow.slash("npcvoices on")
    assert.same({}, mutedFiles)
    wow.slash("npcvoices off")
    assert.is_true(isMuted())
    ForeverSpeech.SetEnabled(false)
    assert.same({}, mutedFiles)
    ForeverSpeech.SetEnabled(true)
    assert.is_true(isMuted())
  end)

  it("test (S10): plays the greeting six times, as it is, muted, unmuted, then applies the setting", function()
    load(true)
    local kits = {}
    _G.PlaySound = function(kit) kits[#kits + 1] = kit return true, 99 end
    wow.slash("npcvoices test")
    wow.advance(20)
    assert.equals(3, #wow.sounds)
    assert.equals(552196, wow.sounds[1].path)
    assert.same({ 5974, 5974, 5974 }, kits)
    assert.matches("S10 step 6/6", wow.chatText())
    assert.matches("S10 step 1: file voices on now ok=true willPlay=true", table.concat(ForeverSpeechDB.trace, "\n"))
    assert.same({}, mutedFiles) -- no quest NPC at hand: voices on again
  end)

  it("stay as they are on a client without MuteSoundFile", function()
    load(false)
    assert.is_false(ForeverSpeech.GameVoices.Available())
    assert.equals(0, ForeverSpeech.GameVoices.Update())
    wow.slash("npcvoices off")
    assert.matches("cannot be muted", wow.chatText())
  end)
end)
