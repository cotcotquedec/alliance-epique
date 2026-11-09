local wow = require("tests.lua.helpers.wow")

-- The combined bag: its anchor as the client keeps it, the game laying it out at the bottom right.
local bag, anchored, combat
local slots
local beforeLoad -- sets the game's functions a test needs, after wow.reset()

local function setup(db)
  wow.reset()
  combat = false
  _G.InCombatLockdown = function() return combat end
  if beforeLoad then
    beforeLoad()
  end
  bag = wow.newRegion("Frame")
  bag.EnumerateValidItems = function() return ipairs({}) end
  bag.SetPoint = function(self, point, rel, relPoint, x, y)
    self._point = { point, rel, relPoint, x, y }
  end
  bag.ClearAllPoints = function(self) self._point = nil end
  bag.GetPoint = function(self)
    if self._point then
      return unpack(self._point)
    end
  end
  bag.StartMoving = function(self) self._moving = true end
  bag.StopMovingOrSizing = function(self) self._moving = false end
  bag.IsProtected = function() return false end
  if db and db.slots then
    slots(bag, db.slots == "bottom")
    db.slots = nil
  end
  _G.ContainerFrameCombinedBags = bag
  anchored = 0
  _G.UpdateContainerFrameAnchors = function()
    anchored = anchored + 1
    bag:ClearAllPoints()
    bag:SetPoint("BOTTOMRIGHT", _G.UIParent, "BOTTOMRIGHT", -60, 90)
  end
  _G.ForeverSpeechDB = db
  wow.loadAddon()
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  wow.fire("PLAYER_LOGIN")
  wow.fire("PLAYER_ENTERING_WORLD")
  UpdateContainerFrameAnchors()
end

local function drag(point, x, y)
  bag:GetScript("OnDragStart")(bag)
  assert.is_true(bag._moving)
  bag:SetPoint(point, _G.UIParent, point, x, y) -- where the client leaves it
  bag:GetScript("OnDragStop")(bag)
end

-- A combined bag with the game's grid: 4 columns from (12, -60), a step of 42; the backpack (16 slots) and two bags of
-- 6, enumerated as the game may (last bag first). Its height: 100 plus its rows.
-- bottom: the game anchors its slots to the frame's bottom, the frame's bottom stays where it is (it grows upward).
function slots(f, bottom)
  f.items = {}
  for _, def in ipairs({ { 2, 6 }, { 1, 6 }, { 0, 16 } }) do
    for slot = 1, def[2] do
      local b = wow.newRegion("Button")
      b.GetBagID = function() return def[1] end
      b.GetID = function() return slot end
      b.GetWidth, b.GetHeight = function() return 37 end, function() return 37 end
      b.SetPoint = function(self, point, rel, relPoint, x, y)
        self._at, self._anchor = { x, y }, { point, rel, relPoint, x, y }
      end
      b.GetPoint = function(self) return unpack(self._anchor or {}) end
      b.GetLeft = function(self) return self._at and 100 + self._at[1] end
      b.GetTop = function(self)
        if not self._at then return nil end
        if self._anchor[3] == "BOTTOMLEFT" then return 100 + self._at[2] end
        return f:GetTop() + self._at[2]
      end
      f.items[#f.items + 1] = b
    end
  end
  f.EnumerateValidItems = function(self) return ipairs(self.items) end
  f.GetLeft = function() return 100 end
  f.GetTop = function(self) return bottom and 100 + (self._height or 0) or 500 end
  f.SetHeight = function(self, h) self._height = h end
  f.GetHeight = function(self) return self._height end
  f.GetColumns = function() return 4 end
  f.UpdateItemLayout = function(self)
    local height = 100 + math.ceil(#self.items / 4) * 42
    for i, b in ipairs(self.items) do
      local x, y = 12 + ((i - 1) % 4) * 42, -60 - math.floor((i - 1) / 4) * 42
      if bottom then
        b:SetPoint("TOPLEFT", self, "BOTTOMLEFT", x, height + y)
      else
        b:SetPoint("TOPLEFT", self, "TOPLEFT", x, y)
      end
    end
    self:SetHeight(height)
  end
end

-- Where each slot is: { [bag] = { [slot] = { x, y } } }.
local function rowsOf(f)
  local at = {}
  for _, b in ipairs(f.items) do
    local id, slot = b:GetBagID(), b:GetID()
    at[id] = at[id] or {}
    at[id][slot] = b._at
  end
  return at
end

describe("bag frame", function()
  it("is left at the game's place until it is dragged", function()
    setup()
    assert.same({ "BOTTOMRIGHT", _G.UIParent, "BOTTOMRIGHT", -60, 90 }, bag._point)
    wow.slash("bag")
    assert.matches("à la place du jeu", wow.chatText())
  end)

  it("keeps the place it is dragged to, after the game lays out its bags", function()
    setup()
    drag("TOPLEFT", 120, -80)
    assert.same({ point = "TOPLEFT", relativePoint = "TOPLEFT", x = 120, y = -80 }, ForeverSpeechDB.bagPos)
    UpdateContainerFrameAnchors()
    assert.same({ "TOPLEFT", _G.UIParent, "TOPLEFT", 120, -80 }, bag._point)
    bag:GetScript("OnShow")(bag)
    assert.same({ "TOPLEFT", _G.UIParent, "TOPLEFT", 120, -80 }, bag._point)
  end)

  it("puts the saved place back at login", function()
    setup({ bagPos = { point = "CENTER", relativePoint = "CENTER", x = 10, y = 20 } })
    assert.same({ "CENTER", _G.UIParent, "CENTER", 10, 20 }, bag._point)
  end)

  it("goes back to the game's place on reset", function()
    setup()
    drag("TOPLEFT", 120, -80)
    wow.slash("bag reset")
    assert.is_nil(ForeverSpeechDB.bagPos)
    assert.same({ "BOTTOMRIGHT", _G.UIParent, "BOTTOMRIGHT", -60, 90 }, bag._point)
    assert.matches("remis à la place du jeu", wow.chatText())
  end)

  it("never moves a protected frame in combat", function()
    setup()
    bag.IsProtected = function() return true end
    combat = true
    bag:GetScript("OnDragStart")(bag)
    assert.is_not_true(bag._moving)
    ForeverSpeechDB.bagPos = { point = "CENTER", x = 0, y = 0 }
    UpdateContainerFrameAnchors()
    assert.same({ "BOTTOMRIGHT", _G.UIParent, "BOTTOMRIGHT", -60, 90 }, bag._point)
  end)

  it("lays out one bag per row, the backpack on top, a gap between two bags", function()
    setup({ slots = true })
    bag:Show()
    bag:UpdateItemLayout()
    local at = rowsOf(bag)
    assert.same({ 12, -65 }, at[0][1]) -- the backpack from the grid's corner, below its header (16), lifted by 11
    assert.same({ 138, -191 }, at[0][16]) -- 4 rows of 4
    assert.same({ 12, -259 }, at[1][1]) -- a new row, after a gap of 10 and a header
    assert.same({ 54, -301 }, at[1][6])
    assert.same({ 12, -369 }, at[2][1])
    -- 8 rows, three headers and two gaps instead of the game's 7 rows: one row (42) and 20 + 48 more, less the lift,
    -- plus the room at the bottom
    assert.equal(100 + 7 * 42 + 42 + 20 + 48 - 11 + 6, bag._height)
    assert.same({ "Sac à dos · 16 cases", "Sac 1 · 6 cases", "Sac 2 · 6 cases" }, ForeverSpeech.BagFrame.HeaderTexts())
    bag:UpdateItems() -- again, the slots where the addon put them: the same layout
    assert.same({ 12, -369 }, rowsOf(bag)[2][1])
    assert.equal(100 + 7 * 42 + 42 + 20 + 48 - 11 + 6, bag._height)
  end)

  it("keeps the room of its headers and gaps when the game sizes the frame again", function()
    setup({ slots = true })
    bag:Show()
    bag:UpdateItemLayout()
    bag:SetHeight(100 + 7 * 42) -- the game, by another way than its layout
    assert.equal(100 + 7 * 42 + 42 + 20 + 48 - 11 + 6, bag._height)
    bag:SetHeight(100 + 8 * 42) -- a bag more: the game's new height, the same growth on top
    assert.equal(100 + 8 * 42 + 42 + 20 + 48 - 11 + 6, bag._height)
  end)

  it("keeps the grid's top when the game anchors its slots to the frame's bottom", function()
    setup({ slots = "bottom" })
    bag:Show()
    bag:UpdateItemLayout()
    assert.same({ 12, -65 }, rowsOf(bag)[0][1])
    bag:UpdateItemLayout() -- the frame grown: the game puts its slots lower
    assert.same({ 12, -65 }, rowsOf(bag)[0][1]) -- not lower: no margin under the search box
    assert.same({ 12, -369 }, rowsOf(bag)[2][1])
    assert.equal(100 + 7 * 42 + 42 + 20 + 48 - 11 + 6, bag._height)
  end)

  it("gives the game's layout back when the setting is turned off", function()
    setup({ slots = true })
    bag:Show()
    bag:UpdateItemLayout()
    ForeverSpeech.BagFrame.SetRows(false)
    assert.same({ 54, -60 }, rowsOf(bag)[2][2]) -- the game's grid, in its order
    assert.equal(100 + 7 * 42, bag._height)
    assert.same({}, ForeverSpeech.BagFrame.HeaderTexts())
    ForeverSpeech.BagFrame.SetRows(true)
    assert.same({ 12, -369 }, rowsOf(bag)[2][1])
  end)
end)

-- The reagent bag: Forever's toggle opens and closes the backpack only; the reagent bag (5) has its own frame.
describe("reagent bag", function()
  local open, frame, border, bg

  local function game()
    open = {}
    frame = wow.newRegion("Frame")
    border = { wow.newRegion("Texture"), wow.newRegion("Texture") }
    frame.NineSlice = wow.newRegion("Frame")
    frame.NineSlice.GetRegions = function() return border[1], border[2] end
    bg = wow.newRegion("Texture")
    bg:SetVertexColor(0.4, 0.4, 0.4, 1)
    frame.Bg = bg
    _G.C_Container = { GetContainerNumSlots = function(id) return id == 5 and 12 or 16 end }
    _G.IsBagOpen = function(id) return open[id] or false end
    _G.ToggleAllBags = function() -- the backpack only, as Forever's key does; a frame later for the addon
      open[0] = not open[0] or nil
      if open[0] then
        bag:Show()
        bag:GetScript("OnShow")(bag)
      else
        bag:Hide()
        bag:GetScript("OnHide")(bag)
      end
      wow.advance(0)
    end
    _G.ContainerFrame_GenerateFrame = function(f, _, id)
      f._bag = id
      f:Show()
    end
    _G.OpenBag = function(id)
      open[id] = true
      ContainerFrame_GenerateFrame(frame, 12, id)
    end
    _G.CloseBag = function(id)
      open[id] = nil
      frame:Hide()
    end
    _G.ContainerFrameUtil_GetShownFrameForID = function(id)
      return open[id] and frame._bag == id and frame or nil
    end
  end

  before_each(function()
    beforeLoad = game
  end)
  after_each(function()
    beforeLoad = nil
  end)

  it("opens with all bags, tinted green, and closes with them", function()
    setup()
    _G.ToggleAllBags()
    assert.is_true(open[5])
    assert.is_true(ForeverSpeech.BagFrame.Tinted(frame))
    local r, g = border[1]:GetVertexColor()
    assert.is_true(g > r)
    r, g = bg:GetVertexColor()
    assert.is_true(g > r)
    _G.ToggleAllBags()
    assert.is_nil(open[0])
    assert.is_nil(open[5])
  end)

  it("is opened by the bag button's call when OpenBag opens nothing", function()
    setup()
    _G.OpenBag = function() end
    _G.ToggleBag = function(id)
      open[id] = true
      ContainerFrame_GenerateFrame(frame, 12, id)
    end
    _G.ToggleAllBags()
    assert.is_true(open[5])
    assert.is_true(ForeverSpeech.BagFrame.Tinted(frame))
    assert.matches("did OpenBag%+ToggleBag", ForeverSpeech.BagFrame.lastFollow)
  end)

  it("is folded into the backpack as its last bag, its own frame hidden, and given back when closed", function()
    setup({ slots = true })
    local close, art = wow.newRegion("Button"), wow.newRegion("Texture")
    close:Show()
    for _, obj in ipairs({ art, frame }) do
      obj.SetAlpha = function(self, a) self._alpha = a end
      obj.GetAlpha = function(self) return rawget(self, "_alpha") or 1 end
    end
    local reagent = {}
    for slot = 1, 6 do
      local b = wow.newRegion("Button")
      b.GetBagID = function() return 5 end
      b.GetID = function() return slot end
      b.GetWidth, b.GetHeight = function() return 37 end, function() return 37 end
      b.SetPoint = function(self, point, rel, relPoint, x, y)
        self._at, self._anchor = { x, y }, { point, rel, relPoint, x, y }
      end
      b.GetPoint = function(self) return unpack(self._anchor or {}) end
      b.GetLeft = function(self) return self._at and 100 + self._at[1] end
      b.GetTop = function(self) return self._at and 500 + self._at[2] end
      reagent[slot] = b
    end
    frame.EnumerateValidItems = function() return ipairs(reagent) end
    frame.GetChildren = function() return close, unpack(reagent) end
    frame.GetRegions = function() return art end
    bag:UpdateItemLayout()
    _G.ToggleAllBags()
    assert.is_true(ForeverSpeech.BagFrame.Folded())
    assert.same({ 12, -479 }, reagent[1]._at) -- under the last bag: its line, its header
    assert.equal(bag, reagent[1]._anchor[2])
    assert.same({ 54, -521 }, reagent[6]._at)
    assert.is_false(close:IsShown())
    assert.equal(0, art._alpha)
    local texts = ForeverSpeech.BagFrame.HeaderTexts()
    assert.matches("6 cases", texts[#texts])
    _G.ToggleAllBags()
    assert.is_false(ForeverSpeech.BagFrame.Folded())
    assert.is_true(close:IsShown())
    assert.equal(1, art._alpha)
  end)

  it("takes its tint off a frame the game reuses for another bag", function()
    setup()
    _G.ToggleAllBags()
    ContainerFrame_GenerateFrame(frame, 20, 2)
    assert.is_false(ForeverSpeech.BagFrame.Tinted(frame))
    assert.same({ 0.4, 0.4, 0.4, 1 }, { bg:GetVertexColor() })
    assert.same({ 1, 1, 1, 1 }, { border[1]:GetVertexColor() })
  end)

  it("is left to the player when the setting is off, its tint taken off", function()
    setup()
    _G.ToggleAllBags()
    ForeverSpeech.BagFrame.SetReagent(false)
    assert.is_false(ForeverSpeech.BagFrame.Tinted(frame))
    _G.ToggleAllBags()
    assert.is_true(open[5]) -- the backpack closed, the reagent bag left open
    open[5] = nil
    _G.ToggleAllBags()
    assert.is_nil(open[5])
  end)
end)
