-- ForeverSpeech: the backpack's frame made movable (2026-10-20). The combined bag (ContainerFrameCombinedBags, the
-- one Forever shows, H18) is dragged by its edges or its title (left button; the item buttons keep their own drag);
-- its place is kept by account (ForeverSpeechDB.bagPos) and put back after the game lays out its bags
-- (UpdateContainerFrameAnchors, run each time a bag opens) and each time it shows. Without a saved place, the game's.
-- The separate bags (ContainerFrameN, Classic style) are laid out together by the game: left to it.
-- The secure Disenchant tab (ui/side_tabs.lua) is placed by screen position: it follows the frame while it moves.
-- One row per bag (2026-10-20, setting bagRows): after the game lays out its slots in one grid, the addon puts them
-- back bag by bag, each bag from a new row, the backpack on top, a thin line between two bags, so a bag's size shows;
-- above each bag, its name, its slots and its free slots (C_Container.GetBagName, GetContainerNumFreeSlots, else the
-- addon's names; seen 2026-10-20: a backpack of 20 slots fills two rows of 10 and the line alone did not show it);
-- the frame grows by the rows, headers and gaps added, and keeps it: each time the game sizes the frame (SetHeight,
-- SetSize: seen 2026-10-20, the frame was not grown, the gaps were not counted), the addon's growth is added again.
-- The game's grid gives the place, the steps and the number of columns (GetColumns, else measured): the addon only
-- moves its slots. The grid's top is measured as the game laid it out at its own height: slots anchored to the
-- frame's bottom (seen 2026-10-20: once the frame grown, the game put them lower and the grid went down by as much,
-- a margin under the search box) are lifted by the addon's growth; anchored to nothing known, the top measured
-- before. Run after UpdateItemLayout, UpdateFrameSize and UpdateItems when the frame has them (Retail style), on show
-- and after UpdateContainerFrameAnchors.
-- Never while the frame is protected in combat. Unverified on Forever: all of it (T38).
local H = ForeverSpeech
local L = H.L

local BagFrame = {}
H.BagFrame = BagFrame

local GAP = 10 -- between two bags; the line in its middle
local HEADER = 16 -- a bag's name and size, above its slots
local LIFT = 11 -- the first header goes up into the game's margin under the search box (asked 2026-10-20)
local PAD = 6 -- more room between the last bag and the money bar (asked 2026-10-20); the frame: game's + growth - 5
local LINE = { 1, 0.82, 0, 0.35 }

local bag -- the combined bag, once made movable
local moving = false
local follower -- runs the side tabs' update while the frame moves
local lines = {} -- the separators between two bags
local headers = {} -- the bags' names and sizes
local gameHeight, ownHeight -- the frame's height as the game set it, and as the addon set it
local extra = 0 -- the height the addon's layout adds to the game's
local sizing = false -- the addon is setting the frame's height
local placed = setmetatable({}, { __mode = "k" }) -- slot button → where the addon put it, { x, y }
local grid -- the game's grid, measured before the addon moved its slots
local gridTop -- the grid's top below the frame's top, measured at the game's height
local folded -- the reagent bag's own frame, folded into the combined bag (below, 2026-11-09)
local band -- the reagent bag's green background in the combined bag
local TINT = { 0.35, 0.85, 0.5 } -- the reagent bag's color
local GOLD = { 1, 0.82, 0 } -- GameFontNormalSmall's

local function blocked(f)
  return InCombatLockdown and InCombatLockdown() and f.IsProtected and f:IsProtected()
end

local function rowsOn()
  return not ForeverSpeechDB or ForeverSpeechDB.bagRows ~= false
end

local function slotOf(button)
  local bagID
  if button.GetBagID then
    local ok, value = pcall(button.GetBagID, button)
    bagID = ok and value or nil
  end
  return bagID or -1, button.GetID and button:GetID() or 0
end

local function items(f)
  local list = {}
  if not f.EnumerateValidItems then
    return list
  end
  local ok, iter, st, ctl = pcall(f.EnumerateValidItems, f)
  if ok and type(iter) == "function" then
    for _, b in iter, st, ctl do
      list[#list + 1] = b
    end
  end
  return list
end

local function round(v)
  return math.floor(v * 10 + 0.5) / 10
end

-- The smallest positive step between the values of a set, or nil.
local function step(set)
  local values = {}
  for v in pairs(set) do
    values[#values + 1] = v
  end
  table.sort(values)
  local best
  for i = 2, #values do
    local d = math.abs(values[i] - values[i - 1])
    if d > 0.5 and (not best or d < best) then
      best = d
    end
  end
  return best, #values
end

-- How much of the frame's growth moves the slots down: 1 when they are anchored to its bottom, 0.5 to its middle,
-- 0 to its top; nil when no slot is anchored to the frame.
local function anchorShare(f, buttons)
  for _, b in ipairs(buttons) do
    local _, rel, relPoint = b:GetPoint(1)
    if rel == f and type(relPoint) == "string" then
      if relPoint:find("BOTTOM") then
        return 1
      elseif relPoint:find("TOP") then
        return 0
      end
      return 0.5
    end
  end
  return nil
end

-- The grid the slots are in, in the frame's coordinates: its top left corner, its steps, its columns.
local function measure(f, buttons)
  local fl, ft = f:GetLeft(), f:GetTop()
  if not (fl and ft) then
    return nil
  end
  local lefts, tops, x, y = {}, {}, nil, nil
  for _, b in ipairs(buttons) do
    local l, t = b:GetLeft(), b:GetTop()
    if not (l and t) then
      return nil
    end
    l, t = round(l - fl), round(t - ft)
    lefts[l], tops[t] = true, true
    x = x and math.min(x, l) or l
    y = y and math.max(y, t) or t
  end
  local grown = (f:GetHeight() or 0) - (gameHeight or f:GetHeight() or 0) -- the addon's growth, now
  if math.abs(grown) < 0.5 then
    gridTop = y
  else
    local share = anchorShare(f, buttons)
    y = share and round(y + grown * share) or gridTop or y
  end
  local w, h = buttons[1]:GetWidth() or 37, buttons[1]:GetHeight() or 37
  local stepX, cols = step(lefts)
  local stepY = step(tops)
  if f.GetColumns then
    local ok, n = pcall(f.GetColumns, f)
    if ok and type(n) == "number" and n > 0 then
      cols = n
    end
  end
  return { x = x, y = y, w = w, h = h, stepX = stepX or (w + 5), stepY = stepY or (h + 5), cols = cols }
end

local function line(f, i)
  local tex = lines[i]
  if not tex then
    tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(LINE[1], LINE[2], LINE[3], LINE[4])
    tex:SetHeight(1)
    lines[i] = tex
  end
  return tex
end

local function hideLines(from)
  for i = math.max(from, 1), #lines do
    lines[i]:Hide()
  end
  for i = from + 1, #headers do
    headers[i]:Hide()
  end
end

local function header(f, i)
  local fs = headers[i]
  if not fs then
    fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetJustifyH("LEFT")
    fs:SetHeight(HEADER)
    fs:SetWordWrap(false)
    headers[i] = fs
  end
  return fs
end

local function bagName(id)
  if C_Container and C_Container.GetBagName then
    local ok, name = pcall(C_Container.GetBagName, id)
    if ok and type(name) == "string" and name ~= "" then
      return name
    end
  end
  return id == 0 and L.BAG_BACKPACK or string.format(L.BAG_N, id)
end

local function freeSlots(id)
  if C_Container and C_Container.GetContainerNumFreeSlots then
    local ok, n = pcall(C_Container.GetContainerNumFreeSlots, id)
    if ok and type(n) == "number" then
      return n
    end
  end
  return nil
end

local function headerText(id, slots)
  local text = string.format(L.BAG_HEADER, bagName(id), slots)
  local free = freeSlots(id)
  if free then
    text = text .. "  |cffa0a0a0" .. string.format(L.BAG_FREE, free) .. "|r"
  end
  return text
end

-- The shown headers' texts, top to bottom (tests, /fs bag slots).
function BagFrame.HeaderTexts()
  local out = {}
  for _, fs in ipairs(headers) do
    if fs:IsShown() then
      out[#out + 1] = fs:GetText()
    end
  end
  return out
end

-- True when every slot is where the addon put it: the game's grid is the one measured before.
local function ours(f, buttons)
  local fl, ft = f:GetLeft(), f:GetTop()
  if not (grid and fl and ft) then
    return false
  end
  for _, b in ipairs(buttons) do
    local p, l, t = placed[b], b:GetLeft(), b:GetTop()
    if not (p and l and t) or math.abs(l - fl - p[1]) > 0.5 or math.abs(t - ft - p[2]) > 0.5 then
      return false
    end
  end
  return true
end

local function setHeight(f, h)
  sizing = true
  f:SetHeight(h)
  sizing = false
end

-- The game sized the frame: its height is the game's, the addon's growth goes on top of it.
local function onGameSize()
  if sizing or not (bag and grid and rowsOn()) or blocked(bag) then
    return
  end
  gameHeight = bag:GetHeight() or 0
  ownHeight = gameHeight + extra
  setHeight(bag, ownHeight)
end

-- The frame's height as the game set it last: the current one, unless it is the addon's own.
local function baseHeight(f)
  local h = f:GetHeight() or 0
  if not (ownHeight and math.abs(h - ownHeight) < 0.5) then
    gameHeight = h
  end
  return gameHeight
end

-- Puts the slots back one bag per row (nothing when the setting is off).
function BagFrame.Layout()
  local f = bag
  if not (f and rowsOn() and f:IsShown()) or blocked(f) then
    return
  end
  local own = items(f)
  if #own == 0 then
    return
  end
  local base = baseHeight(f)
  local m = ours(f, own) and grid or measure(f, own) -- the game's grid: from its own slots only
  if not m then
    return
  end
  grid = m
  local buttons = {}
  for _, b in ipairs(own) do
    buttons[#buttons + 1] = b
  end
  if folded then
    for _, b in ipairs(items(folded)) do
      buttons[#buttons + 1] = b
    end
  end
  local reagentID = BagFrame.ReagentID()
  local bandTop -- the reagent bag's header, its top
  table.sort(buttons, function(a, b)
    local ab, as = slotOf(a)
    local bb, bs = slotOf(b)
    if ab ~= bb then
      return ab < bb
    end
    return as < bs
  end)
  local counts = {}
  for _, b in ipairs(buttons) do
    local bagID = slotOf(b)
    counts[bagID] = (counts[bagID] or 0) + 1
  end
  local width = (m.cols - 1) * m.stepX + m.w
  local rowY, col, last, used = LIFT, 0, nil, 0 -- rowY: the current row's top
  for _, b in ipairs(buttons) do
    local bagID = slotOf(b)
    if bagID ~= last then
      if last ~= nil then
        local prev = rowY
        rowY = rowY - m.stepY - GAP
        local tex = line(f, used)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", f, "TOPLEFT", m.x, m.y + (prev - m.h + rowY) / 2)
        tex:SetWidth(width)
        tex:Show()
      end
      used = used + 1
      local fs = header(f, used)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", f, "TOPLEFT", m.x, m.y + rowY)
      fs:SetWidth(width)
      fs:SetText(headerText(bagID, counts[bagID]))
      local color = (folded and bagID == reagentID) and TINT or GOLD
      fs:SetTextColor(color[1], color[2], color[3])
      fs:Show()
      if folded and bagID == reagentID then
        bandTop = rowY
      end
      rowY = rowY - HEADER
      col = 0
    elseif col == m.cols then
      rowY = rowY - m.stepY
      col = 0
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", m.x + col * m.stepX, m.y + rowY)
    placed[b] = { m.x + col * m.stepX, m.y + rowY }
    col = col + 1
    last = bagID
  end
  hideLines(used)
  if bandTop then
    if not band then
      band = f:CreateTexture(nil, "BACKGROUND", nil, 7)
      band:SetColorTexture(TINT[1], TINT[2], TINT[3], 0.18)
    end
    band:ClearAllPoints()
    band:SetPoint("TOPLEFT", f, "TOPLEFT", m.x - 4, m.y + bandTop + 2)
    band:SetSize(width + 8, bandTop - rowY + m.h + 6)
    band:Show()
  elseif band then
    band:Hide()
  end
  local gameRows = math.ceil(#own / m.cols)
  extra = (-rowY) - (gameRows - 1) * m.stepY + PAD
  ownHeight = base + extra
  setHeight(f, ownHeight)
end

-- The setting turned off: the game's layout back.
local function restore()
  hideLines(0)
  if band then
    band:Hide()
  end
  ownHeight, grid, gridTop, extra = nil, nil, nil, 0
  if not bag or blocked(bag) then
    return
  end
  if gameHeight then
    bag:SetHeight(gameHeight)
  end
  for _, name in ipairs({ "UpdateItemLayout", "UpdateFrameSize" }) do
    if type(bag[name]) == "function" then
      pcall(bag[name], bag)
    end
  end
end

function BagFrame.SetRows(on)
  ForeverSpeechDB.bagRows = on and true or false
  if on then
    BagFrame.Layout()
  else
    restore()
  end
  BagFrame.FollowSoon() -- the reagent bag folded in or given back
end

local pending = false
local function layoutSoon()
  if pending then
    return
  end
  pending = true
  C_Timer.After(0, function()
    pending = false
    BagFrame.Layout()
  end)
end

-- Puts the frame at its saved place (nothing without one, or while it moves).
function BagFrame.Apply()
  local pos = ForeverSpeechDB and ForeverSpeechDB.bagPos
  if not (bag and pos and pos.point) or moving or blocked(bag) then
    return
  end
  bag:ClearAllPoints()
  bag:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
end

local function save(f)
  local point, _, relativePoint, x, y = f:GetPoint(1)
  if point then
    ForeverSpeechDB.bagPos = { point = point, relativePoint = relativePoint, x = x, y = y }
    H.Trace("bag: moved to %s %s %.0f %.0f", point, tostring(relativePoint), x or 0, y or 0)
  end
end

local function onDragStart(f)
  if blocked(f) then
    return
  end
  moving = true
  f:StartMoving()
  follower:Show()
end

local function onDragStop(f)
  if not moving then
    return
  end
  moving = false
  follower:Hide()
  f:StopMovingOrSizing()
  pcall(f.SetUserPlaced, f, false) -- the addon keeps the place, not the client's layout cache
  save(f)
  H.SideTabs.Update()
end

-- Back to the game's place: the saved one forgotten, the game lays out its bags again.
function BagFrame.Reset()
  ForeverSpeechDB.bagPos = nil
  if bag and type(UpdateContainerFrameAnchors) == "function" and not blocked(bag) then
    UpdateContainerFrameAnchors()
  end
end

local function install()
  bag = ContainerFrameCombinedBags
  bag:SetMovable(true)
  bag:SetClampedToScreen(true)
  bag:EnableMouse(true)
  bag:RegisterForDrag("LeftButton")
  bag:HookScript("OnDragStart", onDragStart)
  bag:HookScript("OnDragStop", onDragStop)
  bag:HookScript("OnHide", onDragStop) -- closed while moving
  bag:HookScript("OnShow", function() BagFrame.FollowSoon() end) -- the reagent bag with it (defined below)
  bag:HookScript("OnHide", function() BagFrame.FollowSoon() end)
  bag:HookScript("OnShow", BagFrame.Apply)
  bag:HookScript("OnShow", function()
    BagFrame.Layout()
    layoutSoon() -- the game may lay out its slots just after showing the frame
  end)
  for _, name in ipairs({ "UpdateItemLayout", "UpdateFrameSize", "UpdateItems" }) do
    if type(bag[name]) == "function" then
      hooksecurefunc(bag, name, BagFrame.Layout)
    end
  end
  hooksecurefunc(bag, "SetHeight", onGameSize)
  hooksecurefunc(bag, "SetSize", onGameSize)
  if type(UpdateContainerFrameAnchors) == "function" then
    hooksecurefunc("UpdateContainerFrameAnchors", BagFrame.Apply)
    hooksecurefunc("UpdateContainerFrameAnchors", layoutSoon)
  end
  follower = CreateFrame("Frame")
  follower:Hide()
  follower:SetScript("OnUpdate", function()
    H.SideTabs.Update()
  end)
  BagFrame.Apply()
  H.Trace("bag: movable, layout hooks: %s %s %s", type(bag.UpdateItemLayout), type(bag.UpdateFrameSize),
    type(bag.GetColumns))
end

H.WhenAvailable(function()
  return ContainerFrameCombinedBags ~= nil
end, install)

H.OnInit(BagFrame.Apply) -- the saved place is known once the SavedVariables are loaded

-- The reagent bag (2026-11-09, asked by the player; setting reagentBag): Forever's "open all bags" key leaves it
-- closed, the player had to click it too. The reagent bag follows the backpack's frame: opened when it shows, closed
-- when it hides, a frame later, whatever opened it (a hook on ToggleAllBags never ran in game: the player's key calls
-- something else). Its own frame (the game shows it apart from the combined bag) is
-- tinted green, border and background, so it stands out; the tint leaves a pooled frame reused for another bag.
-- Opened by the addon, the frame's fields are tainted: an item used from it in combat may be blocked (reagents are
-- not used). Unverified on Forever: the bag's ID (5, Enum.BagIndex.ReagentBag in Retail), its frame (T71, H44).
-- One window (2026-11-09, asked by the player): with one row per bag (bagRows), the reagent bag's frame is folded
-- into the combined bag. It stays open, so the game keeps updating its slots, but its art and its other buttons are
-- hidden, it takes no mouse, and its slots are laid out as the combined bag's last bag, under a green header on a
-- green background. Given back to the game when it closes, when a setting is off or when the game reuses it for
-- another bag.
local FILL_ALPHA = 0.2
local hidden = {} -- the folded frame's art: region or child → { alpha } or { shown = true }
local saved -- the folded frame's own state: { mouse, strata, level }
local hooked = setmetatable({}, { __mode = "k" }) -- frames whose updates lay the combined bag out again
local painted = setmetatable({}, { __mode = "k" }) -- frame → { fill, saved = { [region] = color }, on }

local function reagentOn()
  return not ForeverSpeechDB or ForeverSpeechDB.reagentBag ~= false
end

function BagFrame.ReagentID()
  local index = Enum and Enum.BagIndex
  return index and index.ReagentBag or 5
end

local function numSlots(id)
  local get = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  if not get then
    return 0
  end
  local ok, n = pcall(get, id)
  return ok and tonumber(n) or 0
end

-- The frame showing a bag apart from the combined bag, or nil.
local function frameOf(id)
  if type(ContainerFrameUtil_GetShownFrameForID) == "function" then
    local ok, f = pcall(ContainerFrameUtil_GetShownFrameForID, id)
    if ok and f then
      return f
    end
  end
  for i = 1, 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f:IsShown() and f:GetID() == id then
      return f
    end
  end
  return nil
end

-- The frame's border pieces and background, the ones a tint shows on.
local function tintables(f)
  local out = {}
  local ns = f.NineSlice
  if type(ns) == "table" and type(ns.GetRegions) == "function" then
    for _, r in ipairs({ ns:GetRegions() }) do
      if type(r) == "table" and type(r.SetVertexColor) == "function" then
        out[#out + 1] = r
      end
    end
  end
  local bg = f.Bg
  if type(bg) == "table" and type(bg.SetVertexColor) == "function" then
    out[#out + 1] = bg
  end
  return out
end

local function paint(f, on)
  local state = painted[f]
  if on then
    if not state then
      local fill = f:CreateTexture(nil, "BACKGROUND", nil, 7)
      fill:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
      fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
      fill:SetColorTexture(TINT[1], TINT[2], TINT[3], FILL_ALPHA)
      state = { fill = fill, saved = {} }
      painted[f] = state
    end
    for _, r in ipairs(tintables(f)) do
      if not state.saved[r] then
        state.saved[r] = { r:GetVertexColor() }
      end
      r:SetVertexColor(TINT[1], TINT[2], TINT[3])
    end
    state.fill:Show()
    state.on = true
  elseif state and state.on then
    for r, c in pairs(state.saved) do
      r:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
    state.saved = {}
    state.fill:Hide()
    state.on = false
  end
end

-- True when the frame wears the reagent bag's tint (tests, /fs bag slots).
function BagFrame.Tinted(f)
  local state = painted[f]
  return state and state.on or false
end

local function unfold()
  local rf = folded
  if not rf then
    return
  end
  folded = nil
  for obj, was in pairs(hidden) do
    if was.shown then
      obj:Show()
    else
      obj:SetAlpha(was.alpha or 1)
    end
  end
  hidden = {}
  if saved then
    rf:EnableMouse(saved.mouse ~= false)
    if saved.strata then
      rf:SetFrameStrata(saved.strata)
    end
    if saved.level then
      rf:SetFrameLevel(saved.level)
    end
    saved = nil
  end
  H.Trace("bag: reagent bag given back to its own frame")
end

-- Hides the frame's art and other buttons; its slots are laid out by BagFrame.Layout.
local function fold(rf)
  if blocked(rf) or blocked(bag) then
    return
  end
  if folded ~= rf then
    unfold()
    folded = rf
    saved = { mouse = rf:IsMouseEnabled(), strata = rf:GetFrameStrata(), level = rf:GetFrameLevel() }
    H.Trace("bag: reagent bag folded into the backpack")
  end
  local slot = {}
  for _, b in ipairs(items(rf)) do
    slot[b] = true
  end
  for _, child in ipairs({ rf:GetChildren() }) do
    if not slot[child] and child:IsShown() then
      hidden[child] = { shown = true }
      child:Hide()
    end
  end
  for _, region in ipairs({ rf:GetRegions() }) do
    if not hidden[region] then
      hidden[region] = { alpha = region:GetAlpha() }
    end
    region:SetAlpha(0)
  end
  rf:EnableMouse(false)
  rf:SetFrameStrata(bag:GetFrameStrata())
  rf:SetFrameLevel((bag:GetFrameLevel() or 0) + 10)
  if not hooked[rf] then
    hooked[rf] = true
    for _, name in ipairs({ "UpdateItemLayout", "UpdateFrameSize", "UpdateItems" }) do
      if type(rf[name]) == "function" then
        hooksecurefunc(rf, name, function(self)
          if folded == self then
            layoutSoon()
          end
        end)
      end
    end
  end
  BagFrame.Layout()
end

-- The reagent bag's frame, shown: tinted, and folded into the combined bag when it is laid out one bag per row.
local function paintShown()
  local f = frameOf(BagFrame.ReagentID())
  if f then
    paint(f, reagentOn())
    if reagentOn() and rowsOn() and bag and bag:IsShown() then
      fold(f)
      return
    end
  end
  if folded then
    unfold()
    BagFrame.Layout()
  end
end

-- True when the reagent bag's slots are in the combined bag (tests, /fs bag slots).
function BagFrame.Folded()
  return folded ~= nil
end

local function backpackOpen()
  if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
    return true
  end
  return type(IsBagOpen) == "function" and IsBagOpen(0) and true or false
end

-- After the backpack shows or hides: the reagent bag opened or closed with it. Open means its frame shown
-- (first test, 2026-11-09: bags open, no frame for bag 5). OpenBag first, else ToggleBag, the bag button's own call.
-- What it saw and did is kept for /fs bag slots (BagFrame.lastFollow).
local function followBackpack()
  local id = BagFrame.ReagentID()
  local slots = numSlots(id)
  if not reagentOn() or slots <= 0 then
    BagFrame.lastFollow = string.format("skipped (setting %s, %d slots)", tostring(reagentOn()), slots)
    return
  end
  local backpack, shown = backpackOpen(), frameOf(id)
  local did = "nothing"
  if backpack and not shown then
    if type(OpenBag) == "function" then
      OpenBag(id)
      did = "OpenBag"
    end
    if not frameOf(id) and type(ToggleBag) == "function" then
      ToggleBag(id)
      did = did .. "+ToggleBag"
    end
  elseif shown and not backpack then
    if type(CloseBag) == "function" then
      CloseBag(id)
      did = "CloseBag"
    end
    if shown:IsShown() then
      shown:Hide()
      did = did .. "+Hide"
    end
  end
  local after = frameOf(id)
  BagFrame.lastFollow = string.format("backpack %s, was shown %s, IsBagOpen %s, did %s, frame now %s",
    tostring(backpack), tostring(shown ~= nil), tostring(type(IsBagOpen) == "function" and IsBagOpen(id)), did,
    tostring(after and after.GetName and after:GetName()))
  H.Trace("bag: reagent bag %d: %s", id, BagFrame.lastFollow)
  paintShown()
end

function BagFrame.SetReagent(on)
  ForeverSpeechDB.reagentBag = on and true or false
  paintShown()
end

-- A frame later: the game ends opening or closing its bags first.
function BagFrame.FollowSoon()
  C_Timer.After(0, followBackpack)
end

H.WhenAvailable(function()
  return type(ContainerFrame_GenerateFrame) == "function"
end, function()
  hooksecurefunc("ContainerFrame_GenerateFrame", function(f, _, id)
    if type(f) == "table" and f ~= ContainerFrameCombinedBags then
      local reagent = id == BagFrame.ReagentID() and reagentOn()
      if f == folded and not reagent then
        unfold() -- reused for another bag
      end
      paint(f, reagent)
      if reagent then
        paintShown()
      end
    end
  end)
end)

-- What the game says of each bag (its slots, C_Container) and what the frame's slot buttons say (their bag), so a
-- layout can be checked against both; kept in ForeverSpeechDB.bagSlots for the next /reload.
local function dumpSlots()
  local out = {}
  for id = 0, 5 do
    local n = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(id) or nil
    out[#out + 1] = string.format("bag %d: %s slots", id, tostring(n))
  end
  local seen, order = {}, {}
  for _, b in ipairs(bag and items(bag) or {}) do
    local id, slot = slotOf(b)
    if not seen[id] then
      seen[id] = { n = 0, max = 0 }
      order[#order + 1] = id
    end
    seen[id].n = seen[id].n + 1
    seen[id].max = math.max(seen[id].max, slot)
  end
  for _, id in ipairs(order) do
    out[#out + 1] = string.format("buttons of bag %s: %d (last slot %d)", tostring(id), seen[id].n, seen[id].max)
  end
  local rid = BagFrame.ReagentID()
  local rframe = frameOf(rid)
  out[#out + 1] = string.format("reagent bag %d: %d slots, Enum %s, frame %s, tinted %s, total frames %s", rid,
    numSlots(rid), tostring(Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag),
    tostring(rframe and rframe.GetName and rframe:GetName()), tostring(rframe and BagFrame.Tinted(rframe)),
    tostring(NUM_TOTAL_BAG_FRAMES))
  out[#out + 1] = "reagent bag, backpack last shown or hidden: " .. (BagFrame.lastFollow or "never seen")
    .. ", folded " .. tostring(folded ~= nil)
  out[#out + 1] = string.format("columns: %s, rows on: %s", grid and tostring(grid.cols) or "?", tostring(rowsOn()))
  out[#out + 1] = string.format("height: %s (game %s, added %s)", tostring(bag and bag:GetHeight()),
    tostring(gameHeight), tostring(extra))
  if grid then
    out[#out + 1] = string.format("grid: x %s y %s step %s/%s slot %s/%s", tostring(grid.x), tostring(grid.y),
      tostring(grid.stepX), tostring(grid.stepY), tostring(grid.w), tostring(grid.h))
  end
  if bag then
    local lowest -- the lowest slot's bottom, above the frame's bottom
    for _, b in ipairs(items(bag)) do
      local bottom = b:GetBottom()
      if bottom and (not lowest or bottom < lowest) then
        lowest = bottom
      end
    end
    out[#out + 1] = string.format("lowest slot above the frame's bottom: %s",
      tostring(lowest and bag:GetBottom() and (lowest - bag:GetBottom())))
    for i = 1, bag:GetNumPoints() or 0 do
      local point, rel, relPoint, x, y = bag:GetPoint(i)
      out[#out + 1] = string.format("point %d: %s %s %s %s %s", i, tostring(point),
        tostring(rel and rel.GetName and rel:GetName()), tostring(relPoint), tostring(x), tostring(y))
    end
    out[#out + 1] = string.format("scale %s, Layout %s, MarkDirty %s, CalculateHeight %s, MoneyFrame %s",
      tostring(bag:GetScale()), type(bag.Layout), type(bag.MarkDirty), type(bag.CalculateHeight),
      tostring(bag.MoneyFrame ~= nil))
    if bag.CalculateHeight then
      local ok, h = pcall(bag.CalculateHeight, bag)
      out[#out + 1] = "CalculateHeight(): " .. tostring(ok and h)
    end
  end
  ForeverSpeechDB.bagSlots = out
  for _, text in ipairs(out) do
    H.Print("%s", text)
  end
end

H.RegisterCommand("bag", function(rest)
  if rest == "reset" then
    BagFrame.Reset()
    H.Print("%s", L.BAG_RESET_DONE)
  elseif rest == "slots" then
    dumpSlots()
  else
    H.Print("%s", ForeverSpeechDB.bagPos and L.BAG_MOVED or L.BAG_DEFAULT)
  end
end, "bag [reset|slots] - drag the backpack by its edge; reset: the game's place; slots: each bag's size")
