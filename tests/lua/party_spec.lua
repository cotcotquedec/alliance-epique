local wow = require("tests.lua.helpers.wow")

-- The group's progress under the window's objectives (2026-11-05): the game's own lines
-- (C_TooltipInfo.GetQuestPartyProgress), a member then their objectives.
local lines, members

local function color(r, g, b)
  return { GetRGB = function() return r, g, b end }
end

local function setup()
  wow.reset()
  members = 1
  lines = {
    { leftText = "Thrall", type = 18, leftColor = color(0.96, 0.55, 0.73) },
    { leftText = "Kobolds tués : 3/8", type = 8, leftColor = color(1, 1, 1) },
    { leftText = "Bougies : 5/5", type = 8, leftColor = color(0.5, 0.5, 0.5) },
  }
  wow.loadAddon()
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  wow.fire("PLAYER_LOGIN")
  _G.GetNumSubgroupMembers = function() return members end
  _G.C_TooltipInfo = {
    GetQuestPartyProgress = function(questID, omitTitle, ignorePlayer)
      assert.equals(1, questID)
      assert.is_true(omitTitle and ignorePlayer)
      return { lines = lines }
    end,
  }
  _G.Enum = { TooltipDataLineType = { QuestObjective = 8, QuestPlayer = 18 } }
end

after_each(function()
  _G.GetNumSubgroupMembers, _G.C_TooltipInfo, _G.Enum = nil, nil, nil
end)

describe("the group's progress", function()
  it("shows each member on the quest, then their objectives, the done ones checked", function()
    setup()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(1)
    assert.same({
      { text = "Thrall", done = false },
      { text = "Kobolds tués : 3/8", done = false },
      { text = "Bougies : 5/5", done = true },
    }, PlayerFrame.PartyRows())
    local data = ForeverSpeech.QuestData.PartyProgress(1)
    assert.is_true(data[1].member)
    assert.is_false(data[2].member)
  end)

  it("follows a member's progress, and shows nothing alone", function()
    setup()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(1)
    lines[2] = { leftText = "Kobolds tués : 8/8", type = 8, leftColor = color(1, 1, 1), completed = true }
    wow.fire("UNIT_QUEST_LOG_CHANGED", "party1")
    assert.same({ text = "Kobolds tués : 8/8", done = true }, PlayerFrame.PartyRows()[2])
    members = 0 -- the group left: the block goes, at the next poll
    wow.tick(1.1)
    assert.same({}, PlayerFrame.PartyRows())
  end)

  it("keeps every line flush left when the client has no line types", function()
    setup()
    _G.Enum = nil
    local data = ForeverSpeech.QuestData.PartyProgress(1)
    assert.is_nil(data[1].member)
    assert.is_true(data[3].done) -- grey: done, as the game draws it
  end)
end)
