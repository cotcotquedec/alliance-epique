local wow = require("tests.lua.helpers.wow")

-- Secret values (Forever, like Retail 12): in instances and combat some values error when indexed, compared or joined.
-- Here a secret is a userdata whose every metamethod raises, and issecretvalue knows it.
local function makeSecret()
  local secret = newproxy(true)
  local mt = getmetatable(secret)
  local function boom()
    error("attempt to use a secret value")
  end
  mt.__index, mt.__eq, mt.__lt, mt.__le, mt.__concat, mt.__len, mt.__call = boom, boom, boom, boom, boom, boom, boom
  return secret
end

describe("secret values", function()
  local secrets, secret

  before_each(function()
    wow.reset()
    secrets = {}
    secret = makeSecret()
    secrets[secret] = true
    _G.issecretvalue = function(v) return secrets[v] == true end
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
  end)

  it("read as nil through H.NotSecret and H.Safe, the other values kept", function()
    local H = ForeverSpeech
    assert.is_nil(H.NotSecret(secret))
    assert.equals("x", H.NotSecret("x"))
    local a, b, c = H.Safe(function() return 1, secret, "c" end)
    assert.same({ 1, nil, "c" }, { a, b, c })
    assert.is_nil(H.Safe(function() error("no") end))
    assert.is_nil(H.Safe(nil))
    assert.is_nil(H.Capture.ParseGUID(secret))
  end)

  it("without issecretvalue nothing is secret", function()
    _G.issecretvalue = nil
    assert.equals(secret, ForeverSpeech.NotSecret(secret))
  end)

  it("a quest opened in a dungeon: no error; a secret quest ID captures nothing", function()
    _G.GetQuestID = function() return secret end
    _G.GetTitleText = function() return secret end
    _G.GetQuestText = function() return "Tuez dix rats." end
    _G.UnitGUID = function() return secret end
    _G.UnitName = function() return secret end
    wow.fire("QUEST_DETAIL")
    wow.fire("QUEST_COMPLETE")
    assert.is_nil(next(ForeverSpeechCaptures.quests or {}))
  end)

  it("a quest with a secret giver is captured without it", function()
    _G.GetQuestID = function() return 783 end
    _G.GetTitleText = function() return secret end
    _G.GetQuestText = function() return "Tuez dix rats." end
    _G.UnitGUID = function() return secret end
    _G.UnitName = function(unit) return unit == "player" and "Jhou" or secret end
    wow.fire("QUEST_DETAIL")
    local rec = ForeverSpeechCaptures.quests[783][1]
    assert.is_nil(rec.npcID)
    assert.is_nil(rec.giverName)
    assert.is_nil(rec.title)
    assert.equals("Jhou", rec.playerName)
  end)

  it("a gossip window and the mouse over a secret NPC: no error, nothing muted or read", function()
    local muted = {}
    _G.MuteSoundFile = function(id) muted[id] = true end
    _G.UnmuteSoundFile = function(id) muted[id] = nil end
    _G.UnitGUID = function() return secret end
    _G.UnitName = function() return secret end
    _G.C_GossipInfo = { GetText = function() return secret end }
    wow.fire("GOSSIP_SHOW")
    wow.advance(0.2)
    wow.fire("UPDATE_MOUSEOVER_UNIT")
    wow.fire("GOSSIP_CLOSED")
    assert.equals(0, #wow.sounds)
    assert.is_nil(next(muted))
    assert.is_nil(next(ForeverSpeechCaptures.gossip or {}))
  end)
end)
