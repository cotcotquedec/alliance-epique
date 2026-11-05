local wow = require("tests.lua.helpers.wow")

-- FlareUI's quest tracker as its code builds it (2026-11-05, FlareUI 2.7.0): FlareUI_ObjectiveTracker > its header
-- and a scroll frame > the scroll child > pooled line buttons holding questID (or zone) and their offset ftY;
-- FlareUI.ObjectiveTracker:Render redraws them.
local lines, watches, calls, clicked

local function line(fields, shown)
  local l = wow.newRegion("Button")
  for k, v in pairs(fields) do
    rawset(l, k, v)
  end
  if shown == false then
    l:Hide()
  else
    l:Show()
  end
  return l
end

local function flareUI(initialized, look)
  local content = wow.newRegion("Frame")
  content.GetChildren = function() return unpack(lines) end
  local scroll = wow.newRegion("ScrollFrame")
  scroll.GetScrollChild = function() return content end
  local holder = wow.newRegion("Frame")
  holder.GetChildren = function() return wow.newRegion("Frame"), scroll end -- its header first
  holder.GetHeight = function() return 300 end
  _G.FlareUI_ObjectiveTracker = holder
  _G.FlareUI = {
    ObjectiveTracker = {
      initialized = initialized ~= false, Render = function() end, Side = function() return true end,
    },
    WINDOW_STYLE = look ~= false and { border = { 0.80, 0.60, 0.34 } } or nil,
  }
end

local function render()
  _G.FlareUI.ObjectiveTracker:Render()
end

local function setup(opts)
  opts = opts or {}
  wow.reset()
  _G.FlareUI, _G.FlareUI_ObjectiveTracker = nil, nil
  watches, calls, clicked = { 104, 101 }, {}, {}
  -- in the pool's order, not the screen's: a hidden line, quest 102's title, the zone heading, quest 101's lines
  lines = {
    line({ questID = 103, ftY = -60 }, false),
    line({ questID = 102, ftY = -42 }),
    line({ zone = "Forêt d'Elwynn", ftY = 0 }),
    line({ questID = 101, ftY = -14 }),
    line({ questID = 101, ftY = -28 }),
  }
  _G.IsShiftKeyDown = function() return false end
  _G.IsControlKeyDown = function() return false end
  _G.C_QuestLog = {
    GetNumQuestWatches = function() return #watches end,
    GetQuestIDForQuestWatchIndex = function(i) return watches[i] end,
    RemoveQuestWatch = function(id) calls[#calls + 1] = "remove " .. id end,
    AddQuestWatch = function(id) calls[#calls + 1] = "add " .. id end,
  }
  if opts.portrait then -- the game's frames, with the parts the addon hides under FlareUI's look
    _G.PortraitFrameMixin = {}
    local createFrame = _G.CreateFrame
    _G.CreateFrame = function(kind, name, parent, template)
      local f = createFrame(kind, name, parent, template)
      if template == "PortraitFrameTemplate" or template == "InsetFrameTemplate" then
        for _, key in ipairs({ "NineSlice", "Bg" }) do
          f[key] = wow.newRegion("Frame")
          f[key]:Show()
        end
      end
      if template == "PortraitFrameTemplate" then
        f.CloseButton = wow.newRegion("Button")
        f.PortraitContainer = wow.newRegion("Frame")
      end
      return f
    end
  end
  if not opts.late then
    flareUI(opts.initialized, opts.look)
  end
  wow.loadAddon()
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  wow.fire("PLAYER_LOGIN")
  ForeverSpeech.PlayerFrame.ShowClicked = function(questID, from)
    clicked[#clicked + 1] = questID .. " " .. from
  end
end

local function toggleQuest(l)
  local b = rawget(l, "ForeverSpeechToggle")
  return b and rawget(b, "questID")
end

after_each(function()
  _G.FlareUI, _G.FlareUI_ObjectiveTracker = nil, nil
  _G.IsShiftKeyDown, _G.IsControlKeyDown = nil, nil
  _G.PortraitFrameMixin = nil
end)

describe("FlareUI's quest tracker", function()
  it("gets a play button on each quest's title after each redraw, none on the other lines", function()
    setup()
    render()
    assert.equals(101, toggleQuest(lines[4]))
    assert.equals(102, toggleQuest(lines[2]))
    assert.is_nil(rawget(lines[5], "ForeverSpeechToggle")) -- an objective
    assert.is_nil(rawget(lines[3], "ForeverSpeechToggle")) -- the zone heading
    assert.is_nil(rawget(lines[1], "ForeverSpeechToggle")) -- not shown
    -- the pool reused: quest 101's objective line is now its title, its old title an objective
    rawset(lines[4], "ftY", -28)
    rawset(lines[5], "ftY", -14)
    render()
    assert.equals(101, toggleQuest(lines[5]))
    assert.is_nil(toggleQuest(lines[4])) -- hidden
  end)

  it("follows its first quest shown, not the watch list's first", function()
    setup()
    local QuestData = ForeverSpeech.QuestData
    assert.same({ 104, "tracker" }, { QuestData.Tracked() }) -- before its first redraw: the watch list
    render()
    assert.equals(101, ForeverSpeech.TrackerButtons.FirstShown())
    assert.same({ 101, "tracker" }, { QuestData.Tracked() })
    assert.truthy(table.concat(ForeverSpeechDB.trace, "\n"):find("tracker: FlareUI 2 quest(s), first=101", 1, true))
  end)

  it("washes in gold the quests whose area the player stands in", function()
    setup()
    local Tracker = ForeverSpeech.TrackerButtons
    ForeverSpeech.QuestArea.Inside = function(questID) return questID == 102 end
    render()
    assert.same({ 102 }, Tracker.FlareHighlighted())
    ForeverSpeech.QuestArea.Inside = function() return false end
    render()
    assert.same({}, Tracker.FlareHighlighted())
  end)

  it("shows a quest clicked in it in the window, not with Shift or Ctrl", function()
    setup()
    render()
    lines[5]:GetScript("OnClick")(lines[5], "LeftButton") -- an objective line: its quest
    assert.same({ "101 tracker" }, clicked)
    lines[2]:GetScript("OnClick")(lines[2], "RightButton") -- FlareUI's menu
    _G.IsShiftKeyDown = function() return true end -- FlareUI links or focuses the quest
    lines[2]:GetScript("OnClick")(lines[2], "LeftButton")
    assert.same({ "101 tracker" }, clicked)
  end)

  it("leaves the watch list alone: FlareUI sorts its tracker itself", function()
    setup()
    local tracker = ForeverSpeech.QuestSort.SortNow()
    assert.equals("FlareUI", tracker)
    assert.same({}, calls)
    assert.matches("Par niveau", wow.chatText())
  end)

  it("dresses the addon's windows in its look, and leaves the game's frames without it", function()
    setup({ portrait = true })
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(1)
    local f = PlayerFrame.ListPanel():GetParent()
    assert.truthy(rawget(f, "ForeverSpeechFlare"))
    assert.is_false(f.NineSlice:IsShown()) -- the game's border and title bar
    assert.is_false(f.Bg:IsShown())
    local list = PlayerFrame.ListPanel()
    assert.truthy(rawget(list, "ForeverSpeechFlare")) -- the play list's box
    assert.is_false(list.NineSlice:IsShown())
    ForeverSpeech.Companions.Open()
    assert.truthy(rawget(ForeverSpeech.Companions.Window(), "ForeverSpeechFlare"))
    local trace = table.concat(ForeverSpeechDB.trace, "\n")
    assert.truthy(trace:find("style: FlareUI look on the main window", 1, true))
    assert.truthy(trace:find("style: FlareUI look on the companions window", 1, true))

    setup({ portrait = true, look = false }) -- a FlareUI without its window style: the game's frames
    PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(1)
    f = PlayerFrame.ListPanel():GetParent()
    assert.is_nil(rawget(f, "ForeverSpeechFlare"))
    assert.is_true(f.NineSlice:IsShown())
    assert.is_true(PlayerFrame.ListPanel().NineSlice:IsShown())
  end)

  it("docks the window to its tracker, on the side facing the middle of the screen, unless told not to", function()
    setup()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(1)
    render()
    assert.equals("right", PlayerFrame.Docked()) -- the tracker on the right: the window on its left
    assert.truthy(table.concat(ForeverSpeechDB.trace, "\n"):find("frame: docked right", 1, true))
    ForeverSpeechDB.dockFlare = false -- the setting off: where the player left it
    PlayerFrame.Redock()
    assert.is_nil(PlayerFrame.Docked())
    ForeverSpeechDB.dockFlare = true
    _G.FlareUI.ObjectiveTracker.Side = function() return false end
    render()
    assert.equals("left", PlayerFrame.Docked())
    assert.is_false(PlayerFrame.HomeButton():IsShown()) -- at home

    local f = PlayerFrame.ListPanel():GetParent() -- dragged away: free, and the home button shows
    f:GetScript("OnDragStart")(f)
    f:GetScript("OnDragStop")(f)
    assert.is_nil(PlayerFrame.Docked())
    assert.is_false(ForeverSpeechDB.dockFlare)
    assert.is_true(PlayerFrame.HomeButton():IsShown())
    render() -- FlareUI's redraws leave it where it was dragged
    assert.is_nil(PlayerFrame.Docked())
    PlayerFrame.GoHome()
    assert.equals("left", PlayerFrame.Docked())
    assert.is_false(PlayerFrame.HomeButton():IsShown())
  end)

  it("puts the decor in its look: its font faces, its struck-bronze icons; the game's look without it", function()
    setup()
    local painted = 0
    local applied = {}
    _G.FlareUI.BronzeIcon = {
      Apply = function(_, path) applied[#applied + 1] = path end,
      Paint = function() painted = painted + 1 end,
    }
    _G.FlareUI.GetFontPath = function(face) return "Fonts\\" .. face end
    _G.FlareUI.ApplyShadow = function() end
    _G.FlareUI.db = { profile = { objectivetracker = {
      headerFont = { face = "Header", flags = "OUTLINE" },
      titleFont = { face = "Title" },
      objectiveFont = { face = "Body", flags = "NONE" },
    } } }
    local Style = ForeverSpeech.Style
    local function fontString(kind)
      return {
        fsFontKind = kind,
        GetObjectType = function() return "FontString" end,
        GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
        SetFont = function(self, path, size, flags) self.set = { path, size, flags } end,
      }
    end
    local body, header, title = fontString(nil), fontString("header"), fontString("title")
    local child = { GetRegions = function() return title end, GetChildren = function() end }
    local root = { GetRegions = function() return body, header end, GetChildren = function() return child end }
    assert.equals(3, Style.FlareFonts(root))
    assert.same({ "Fonts\\Body", 12, "" }, body.set) -- the size kept, FlareUI's face and outline
    assert.same({ "Fonts\\Header", 12, "OUTLINE" }, header.set)
    assert.same({ "Fonts\\Title", 12, "" }, title.set)

    local b = Style.RoundButton(UIParent, "play", 20)
    assert.is_true(rawget(b, "bronze"))
    assert.is_false(b.ring:IsShown()) -- the glyph alone
    assert.is_true(painted > 0)
    assert.equals(ForeverSpeech.Style.Glyph("play") .. "_white", applied[#applied]) -- the white glyph, in bronze
    local onMap = Style.RoundButton(UIParent, "play", 20, nil, true) -- the world map's: its own look
    assert.is_false(rawget(onMap, "bronze"))

    _G.FlareUI = nil -- without FlareUI: the game's look
    body.set = nil
    assert.equals(0, Style.FlareFonts(root))
    assert.is_nil(body.set)
    assert.is_false(rawget(Style.RoundButton(UIParent, "play", 20), "bronze"))
  end)

  it("does nothing while FlareUI's tracker is off, and hooks it when FlareUI loads after the addon", function()
    setup({ initialized = false })
    render()
    assert.is_nil(ForeverSpeech.TrackerButtons.FirstShown())
    ForeverSpeech.PlayerFrame.ShowQuest(1)
    assert.is_nil(ForeverSpeech.PlayerFrame.Docked()) -- not docked to a tracker that does not run
    local PlayerFrame = ForeverSpeech.PlayerFrame -- without it, the home button brings the window to its default place
    local f = PlayerFrame.ListPanel():GetParent()
    assert.is_false(PlayerFrame.HomeButton():IsShown())
    f:GetScript("OnDragStart")(f)
    f:GetScript("OnDragStop")(f)
    assert.is_true(PlayerFrame.HomeButton():IsShown())
    PlayerFrame.GoHome()
    assert.is_nil(ForeverSpeechDB.playerMoved)
    assert.is_false(PlayerFrame.HomeButton():IsShown())
    assert.same({ 104, "tracker" }, { ForeverSpeech.QuestData.Tracked() })

    setup({ late = true })
    flareUI()
    wow.fire("ADDON_LOADED", "FlareUI")
    render()
    assert.equals(102, toggleQuest(lines[2]))
  end)
end)
