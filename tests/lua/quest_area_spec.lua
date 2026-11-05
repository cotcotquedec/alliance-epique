local wow = require("tests.lua.helpers.wow")

-- Two quests on map 1429, each area a rectangle; the QuestPOIFrame's hit test answers only for the drawn quest, as
-- the client does (H16). `world.x`, `world.y` is the player's position.
local AREAS = {
  [112] = { 0.45, 0.60, 0.55, 0.70 },
  [60] = { 0.35, 0.80, 0.45, 0.90 },
}

local function setup()
  wow.reset()
  local world = { x = 0.2, y = 0.2 }
  local createFrame = _G.CreateFrame
  _G.CreateFrame = function(objectType, ...)
    local f = createFrame(objectType, ...)
    if objectType == "QuestPOIFrame" then
      world.layer = f
      f.DrawNone = function(self) self.drawn = {} end
      f.DrawBlob = function(self, questID, draw) self.drawn[questID] = draw end
      f.UpdateMouseOverTooltip = function(self, x, y)
        for questID in pairs(self.drawn or {}) do
          local a = AREAS[questID]
          if x >= a[1] and x <= a[3] and y >= a[2] and y <= a[4] then
            return questID, 1
          end
        end
      end
    end
    return f
  end
  _G.C_Map = {
    GetBestMapForUnit = function() return 1429 end,
    GetPlayerMapPosition = function()
      return { GetXY = function() return world.x, world.y end }
    end,
  }
  _G.C_QuestLog = {
    GetQuestsOnMap = function() return { { questID = 112 }, { questID = 60 } } end,
    GetTitleForQuestID = function(id) return id == 112 and "Récolte de varech" or "Les bougies de kobolds" end,
  }
  wow.loadAddon()
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  return world
end

describe("quest areas", function()
  it("finds the quest whose area the player stands in, by the client's hit test", function()
    local world = setup()
    local changes = 0
    ForeverSpeech.QuestArea.OnChange(function() changes = changes + 1 end)
    wow.tick(1.1)
    assert.is_false(ForeverSpeech.QuestArea.Inside(112))
    assert.equals(0, changes)

    world.x, world.y = 0.5, 0.65
    wow.tick(1.1)
    assert.is_true(ForeverSpeech.QuestArea.Inside(112))
    assert.is_false(ForeverSpeech.QuestArea.Inside(60))
    assert.equals(1, changes)

    world.x, world.y = 0.4, 0.85
    wow.tick(1.1)
    assert.is_false(ForeverSpeech.QuestArea.Inside(112))
    assert.is_true(ForeverSpeech.QuestArea.Inside(60))
    assert.equals(2, changes)
  end)

  it("highlights nothing with the setting off", function()
    local world = setup()
    world.x, world.y = 0.5, 0.65
    wow.tick(1.1)
    assert.is_true(ForeverSpeech.QuestArea.Inside(112))
    ForeverSpeechDB.questAreaHighlight = false
    ForeverSpeech.QuestArea.Refresh()
    assert.is_false(ForeverSpeech.QuestArea.Inside(112))
  end)

  it("marks the tracker block of a quest in its area", function()
    local world = setup()
    local block = wow.newRegion("Frame")
    block.id = 112
    ForeverSpeech.TrackerButtons.Decorate(block)
    assert.is_nil(rawget(block, "ForeverSpeechArea"))
    world.x, world.y = 0.5, 0.65
    wow.tick(1.1)
    assert.is_true(block.ForeverSpeechArea.bar:IsShown())
    world.x, world.y = 0.2, 0.2
    wow.tick(1.1)
    assert.is_false(block.ForeverSpeechArea.bar:IsShown())
  end)

  it("says the areas with /fs area", function()
    local world = setup()
    world.x, world.y = 0.5, 0.65
    wow.slash("area")
    assert.matches("Récolte de varech", wow.chatText())
  end)
end)
