local wow = require("tests.lua.helpers.wow")

-- Quests 1..5 and their levels (index v7), the watch list as the Retail C_QuestLog keeps it: AddQuestWatch appends.
local LEVELS = { [101] = 5, [102] = 2, [103] = 9, [104] = 2, [105] = nil }

describe("quests sorted by level", function()
  local watches, calls, combat, Sort

  local function watch(list)
    watches = {}
    for i, id in ipairs(list) do
      watches[i] = id
    end
  end

  before_each(function()
    wow.reset()
    watches, calls, combat = {}, {}, false
    _G.InCombatLockdown = function() return combat end
    _G.C_QuestLog = {
      GetNumQuestWatches = function() return #watches end,
      GetQuestIDForQuestWatchIndex = function(i) return watches[i] end,
      GetQuestWatchType = function() return 1 end,
      RemoveQuestWatch = function(id)
        for i = #watches, 1, -1 do
          if watches[i] == id then
            table.remove(watches, i)
          end
        end
        calls[#calls + 1] = "remove " .. id
      end,
      AddQuestWatch = function(id, watchType)
        watches[#watches + 1] = id
        calls[#calls + 1] = "add " .. id .. " " .. tostring(watchType)
      end,
    }
    wow.loadAddon()
    local quests = {}
    for id, level in pairs(LEVELS) do
      quests[id] = { level = level }
    end
    _G.ForeverSpeechIndex = { version = 9, quests = quests, npcs = {} }
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    Sort = ForeverSpeech.QuestSort
  end)

  it("is on by default and orders the tracker's watch list by level, unknown last, ties in the game's order", function()
    assert.is_true(ForeverSpeechDB.sortByLevel)
    watch({ 105, 101, 102, 103, 104 })
    wow.fire("QUEST_WATCH_LIST_CHANGED")
    wow.advance(0.3)
    assert.same({ 102, 104, 101, 103, 105 }, watches)
    assert.equals("add 102 1", calls[2]) -- the watch type is kept
  end)

  it("moves only the quests out of place", function()
    watch({ 102, 104, 103, 101 })
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.3)
    assert.same({ 102, 104, 101, 103 }, watches)
    assert.same({ "remove 101", "add 101 1", "remove 103", "add 103 1" }, calls)
    calls = {}
    wow.fire("QUEST_LOG_UPDATE") -- sorted: nothing more
    wow.advance(0.3)
    assert.same({}, calls)
  end)

  it("waits for the end of combat", function()
    combat = true
    watch({ 103, 102 })
    wow.fire("QUEST_ACCEPTED", 103)
    wow.advance(0.3)
    assert.same({ 103, 102 }, watches)
    combat = false
    wow.fire("PLAYER_REGEN_ENABLED")
    wow.advance(0.3)
    assert.same({ 102, 103 }, watches)
  end)

  it("stops trying when the game keeps its own order", function()
    _G.C_QuestLog.AddQuestWatch = function(id)
      table.insert(watches, 1, id) -- a client that puts a new watch first
      calls[#calls + 1] = "add " .. id
    end
    watch({ 103, 102 })
    wow.fire("QUEST_WATCH_LIST_CHANGED")
    wow.advance(0.3)
    local tries = #calls
    wow.fire("QUEST_WATCH_LIST_CHANGED")
    wow.advance(0.3)
    assert.equals(tries, #calls)
  end)

  it("does nothing when off, nor without the watch API", function()
    ForeverSpeech.HandleSlash("sort off")
    watch({ 103, 102 })
    wow.fire("QUEST_WATCH_LIST_CHANGED")
    wow.advance(0.3)
    assert.same({ 103, 102 }, watches)
    ForeverSpeech.HandleSlash("sort on")
    _G.C_QuestLog.AddQuestWatch = nil
    wow.fire("QUEST_WATCH_LIST_CHANGED")
    wow.advance(0.3)
    assert.same({ 103, 102 }, watches)
  end)

  it("sorts again after a quest is accepted, turned in or removed, and after an objective update", function()
    for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "UNIT_QUEST_LOG_CHANGED" }) do
      watch({ 103, 102 })
      wow.fire(event, 103)
      wow.advance(0.3)
      assert.same({ 102, 103 }, watches, event)
    end
  end)

  it("the button on the tracker header sorts by hand, even with the setting off, and tries again", function()
    assert.is_nil(Sort.button) -- no tracker in this client
    _G.ObjectiveTrackerFrame = wow.newRegion("Frame")
    rawset(_G.ObjectiveTrackerFrame, "Header", wow.newRegion("Frame"))
    rawset(_G.ObjectiveTrackerFrame.Header, "MinimizeButton", wow.newRegion("Button"))
    wow.fire("PLAYER_LOGIN")
    wow.advance(1)
    local b = Sort.button
    assert.is_not_nil(b)
    assert.equals(_G.ObjectiveTrackerFrame.Header, b._parent)
    ForeverSpeech.HandleSlash("sort off")
    watch({ 103, 101, 102 })
    b:Click()
    assert.same({ 102, 101, 103 }, watches)
    assert.matches("triées par niveau", wow.chat[#wow.chat], 1, true)
    combat = true
    watch({ 103, 102 })
    b:Click()
    assert.same({ 103, 102 }, watches)
    assert.matches("fin du combat", wow.chat[#wow.chat], 1, true)
    combat = false
    wow.fire("PLAYER_REGEN_ENABLED")
    wow.advance(0.3)
    assert.same({ 102, 103 }, watches)
  end)

  it("sorts highest first with sortOrder desc, unknown still last; right click turns it around", function()
    ForeverSpeechDB.sortOrder = "desc"
    watch({ 105, 101, 102, 103, 104 })
    wow.fire("QUEST_WATCH_LIST_CHANGED")
    wow.advance(0.3)
    assert.same({ 103, 101, 102, 104, 105 }, watches)
    _G.ObjectiveTrackerFrame = wow.newRegion("Frame")
    wow.fire("PLAYER_LOGIN")
    Sort.button:Click("RightButton")
    assert.equals("asc", ForeverSpeechDB.sortOrder)
    assert.same({ 102, 104, 101, 103, 105 }, watches)
    ForeverSpeech.HandleSlash("sort desc")
    assert.same({ 103, 101, 102, 104, 105 }, watches)
  end)

  -- The quest log: headers (no questID), quest title rows and their objective rows, laid out by layoutIndex.
  local function row(questID, layoutIndex)
    local r = wow.newRegion("Frame")
    r.questID, r.layoutIndex = questID, layoutIndex
    r:Show()
    return r
  end

  it("orders the quest log by level inside each header, a quest keeping its objective rows", function()
    local rows = {
      row(nil, 1),                                   -- header "Forêt d'Elwynn"
      row(103, 2), row(103, 3), row(101, 4), row(102, 5), row(102, 6),
      row(nil, 7),                                   -- header "Classe"
      row(104, 8), row(105, 9), row(101, 10),
    }
    local laidOut = 0
    local contents = wow.newRegion("Frame")
    contents.GetChildren = function() return unpack(rows) end
    contents.Layout = function() laidOut = laidOut + 1 end
    _G.QuestScrollFrame = { Contents = contents }
    assert.equals("sorted", Sort.SortLog())
    local order = {}
    for _, r in ipairs(rows) do
      order[r.layoutIndex] = tostring(rawget(r, "questID"))
    end
    assert.same({ "nil", "102", "102", "101", "103", "103", "nil", "104", "101", "105" }, order)
    assert.equals(1, laidOut)
    assert.equals("unchanged", Sort.SortLog())
    assert.equals(1, laidOut)
  end)

  it("leaves a quest log without a layout frame alone", function()
    _G.QuestScrollFrame = { Contents = { GetChildren = function() end } }
    assert.equals("no layout frame", Sort.SortLog())
  end)

  it("/fs sort probe stores what the client has", function()
    watch({ 101 })
    ForeverSpeech.HandleSlash("sort probe")
    local text = table.concat(ForeverSpeechDB.sortProbe, "\n")
    assert.matches("C_QuestLog.AddQuestWatch: function", text, 1, true)
    assert.matches("watch 1: quest 101 level 5", text, 1, true)
  end)
end)
