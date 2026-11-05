-- ForeverSpeech: play/stop button on each quest of the objective tracker (CLAUDE.md 9.3).
-- S4: ObjectiveTrackerFrame > QuestObjectiveTracker > .ContentsFrame > recycled blocks, title in
-- block.HeaderButton. Blocks are recycled, so the button lives on the block and its quest ID is
-- re-read on every AddBlock. Unverified on Forever: block.id holding the quest ID (Retail); the
-- ID passed to GetBlock just before AddBlock is used as fallback.
local H = ForeverSpeech

local Tracker = {}
H.TrackerButtons = Tracker

local SIZE = 14
local TRACKERS = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }

local lastRequestedID
local blocks = setmetatable({}, { __mode = "k" }) -- every decorated block (recycled: its quest changes)

-- The quest area highlight (core/quest_area.lua): a gold wash over the whole block (title and objectives), a dark
-- gold line down its right edge. T34 (2026-10-18): a bar on the title alone was too faint on the tracker; the line
-- moved from the left to the right and the arrow went, on request.
local GOLD = { 1, 0.82, 0 }
local DARK_GOLD = { 0.8, 0.55, 0 }

local function highlight(block)
  local mark = rawget(block, "ForeverSpeechArea")
  local on = H.QuestArea.Inside(rawget(block, "ForeverSpeechQuest"))
  if not mark then
    if not on then
      return
    end
    local header = rawget(block, "HeaderButton") or block
    mark = {}
    mark.wash = block:CreateTexture(nil, "BACKGROUND")
    mark.wash:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
    mark.wash:SetPoint("TOPLEFT", header, "TOPLEFT", -4, 2)
    mark.wash:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", 0, -2)
    mark.bar = block:CreateTexture(nil, "ARTWORK")
    mark.bar:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    mark.bar:SetBlendMode("ADD")
    mark.bar:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    mark.bar:SetPoint("TOPLEFT", header, "TOPLEFT", -4, 2)
    mark.bar:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, -2)
    mark.edge = block:CreateTexture(nil, "OVERLAY")
    mark.edge:SetColorTexture(DARK_GOLD[1], DARK_GOLD[2], DARK_GOLD[3], 1)
    mark.edge:SetWidth(3)
    mark.edge:SetPoint("TOPLEFT", mark.wash, "TOPRIGHT", 0, 0)
    mark.edge:SetPoint("BOTTOMLEFT", mark.wash, "BOTTOMRIGHT", 0, 0)
    block.ForeverSpeechArea = mark
  end
  for _, part in pairs(mark) do
    part:SetShown(on)
  end
end

local function decorate(block)
  local blockID = rawget(block, "id")
  local questID = tonumber(blockID) or lastRequestedID
  H.Trace("tracker: AddBlock block.id=%s lastGetBlock=%s -> quest=%s header=%s", blockID, lastRequestedID, questID,
    rawget(block, "HeaderButton") ~= nil)
  lastRequestedID = nil
  local b = rawget(block, "ForeverSpeechToggle")
  if not b then
    b = H.PlayerFrame.MakeToggleButton(block, SIZE)
    b:SetPoint("TOPRIGHT", rawget(block, "HeaderButton") or block, "TOPRIGHT", 0, 0)
    b:SetFrameLevel((block:GetFrameLevel() or 0) + 5)
    block.ForeverSpeechToggle = b
  end
  if questID then
    b:SetQuest(questID)
  else
    b:Hide()
  end
  block.ForeverSpeechQuest = questID
  blocks[block] = true
  highlight(block)
end
Tracker.Decorate = decorate

H.QuestArea.OnChange(function()
  for block in pairs(blocks) do
    highlight(block)
  end
end)

local function installOn(tracker)
  hooksecurefunc(tracker, "GetBlock", function(_, id)
    lastRequestedID = tonumber(id)
  end)
  hooksecurefunc(tracker, "AddBlock", function(_, block)
    if block then
      decorate(block)
    end
  end)
  -- a click on a quest's title (2026-10-21): the window shows it (Retail's OnBlockHeaderClick; unverified on Forever,
  -- the quest log's details hook catches the click anyway when it opens the quest)
  if type(tracker.OnBlockHeaderClick) == "function" then
    hooksecurefunc(tracker, "OnBlockHeaderClick", function(_, block)
      local questID = block and (rawget(block, "ForeverSpeechQuest") or tonumber(rawget(block, "id")))
      if questID then
        H.PlayerFrame.ShowClicked(questID, "tracker")
      end
    end)
  end
end

for _, name in ipairs(TRACKERS) do
  H.WhenAvailable(function()
    local t = _G[name]
    return type(t) == "table" and type(t.AddBlock) == "function" and type(t.GetBlock) == "function"
  end, function()
    installOn(_G[name])
    H.Trace("tracker: installed on %s", name)
  end)
end

-- FlareUI (2026-11-05; MIT, its code read for the names of its frames, nothing copied): its quest tracker
-- replaces the game's (parked out of sight) with its own window, FlareUI_ObjectiveTracker, redrawn by
-- FlareUI.ObjectiveTracker:Render. After each redraw the addon decorates it as it does the game's: a play/stop
-- button on each quest's title, the gold wash of the quests whose area the player stands in, a click on a quest
-- shows it in the window. Its lines are pooled buttons in the scroll frame's child, each holding the quest's ID
-- (questID; a zone heading: zone; a recipe: recipeID) and its offset (ftY); a quest's lines follow each other, its
-- title first. FlareUI sorts its tracker itself (its own option, « Par niveau »): the addon leaves the watch list
-- alone while it runs (ui/quest_sort.lua). The followed quest (the window's logbook) is its first quest shown. Its
-- names are indexed in _G: a third-party addon, not the client's, never listed by the game check.
-- Unverified on Forever: all of it (T63).
local FLARE_PAD = 10 -- the wash reaches into the frame's side margins, as FlareUI's own hover band
local flare = { lines = setmetatable({}, { __mode = "k" }), marks = {}, first = nil, lit = {}, summary = nil }

local function flareTracker()
  local addon = _G["FlareUI"]
  local tracker = type(addon) == "table" and addon.ObjectiveTracker
  return type(tracker) == "table" and tracker or nil
end

-- True while FlareUI's tracker runs (its module on: it started).
function Tracker.FlareUI()
  local tracker = flareTracker()
  return tracker ~= nil and rawget(tracker, "initialized") == true
end

-- The shown lines of FlareUI's tracker, top to bottom, and the frame holding them.
local function flareLines()
  local holder = _G["FlareUI_ObjectiveTracker"]
  local content
  if type(holder) == "table" and type(holder.GetChildren) == "function" then
    for _, child in ipairs({ holder:GetChildren() }) do
      content = type(child.GetScrollChild) == "function" and child:GetScrollChild() or nil
      if content then
        break
      end
    end
  end
  local entries = {}
  if content and type(content.GetChildren) == "function" then
    for i, line in ipairs({ content:GetChildren() }) do
      if line:IsShown() then
        entries[#entries + 1] = { line = line, y = tonumber(rawget(line, "ftY")), i = i }
      end
    end
  end
  table.sort(entries, function(a, b)
    if a.y and b.y and a.y ~= b.y then
      return a.y > b.y -- offsets go down from 0
    end
    return a.i < b.i
  end)
  local lines = {}
  for i, entry in ipairs(entries) do
    lines[i] = entry.line
  end
  return lines, content
end

-- The quests shown, in order: { questID, first = its title line, last = its last line }.
local function flareGroups(lines)
  local groups, current = {}, nil
  for _, line in ipairs(lines) do
    local questID = tonumber(rawget(line, "questID"))
    if questID and current and current.questID == questID then
      current.last = line
    elseif questID then
      current = { questID = questID, first = line, last = line }
      groups[#groups + 1] = current
    else
      current = nil
    end
  end
  return groups
end

local function flareMark(content, i)
  local mark = flare.marks[i]
  if mark and mark.content == content then
    return mark
  end
  mark = { content = content }
  mark.wash = content:CreateTexture(nil, "BACKGROUND")
  mark.wash:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
  mark.bar = content:CreateTexture(nil, "BORDER")
  mark.bar:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  mark.bar:SetBlendMode("ADD")
  mark.bar:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
  mark.edge = content:CreateTexture(nil, "ARTWORK")
  mark.edge:SetColorTexture(DARK_GOLD[1], DARK_GOLD[2], DARK_GOLD[3], 1)
  mark.edge:SetWidth(3)
  flare.marks[i] = mark
  return mark
end

local function showMark(mark, on)
  for _, part in ipairs({ mark.wash, mark.bar, mark.edge }) do
    part:SetShown(on)
  end
end

-- A click on a quest's line (left, without Shift or Ctrl: FlareUI opens it in the quest log) shows it in the window.
local function hookClick(line)
  if flare.lines[line] then
    return
  end
  flare.lines[line] = true
  line:HookScript("OnClick", function(self, button)
    local questID = tonumber(rawget(self, "questID"))
    if questID and button == "LeftButton" and not (IsShiftKeyDown() or IsControlKeyDown()) then
      H.PlayerFrame.ShowClicked(questID, "tracker")
    end
  end)
end

local function flareDecorate()
  local lines, content = flareLines()
  local groups = flareGroups(lines)
  local titles = {}
  for _, g in ipairs(groups) do
    titles[g.first] = g.questID
  end
  for _, line in ipairs(lines) do
    hookClick(line)
    local b = rawget(line, "ForeverSpeechToggle")
    if titles[line] and not b then
      b = H.PlayerFrame.MakeToggleButton(line, SIZE)
      -- mostly in the frame's right margin, 3 pixels in from its edge (2026-11-05, after a look in game)
      b:SetPoint("TOPRIGHT", line, "TOPRIGHT", SIZE - 5, 0)
      b:SetFrameLevel((line:GetFrameLevel() or 0) + 5)
      line.ForeverSpeechToggle = b
    end
    if b then
      b:SetQuest(titles[line]) -- nil for a line that is no longer a title: hidden
    end
  end
  -- the pooled lines no longer shown keep their button hidden
  for line in pairs(flare.lines) do
    local b = rawget(line, "ForeverSpeechToggle")
    if b and not line:IsShown() then
      b:SetQuest(nil)
    end
  end
  local lit = {}
  if content then
    for _, g in ipairs(groups) do
      if H.QuestArea.Inside(g.questID) then
        local mark = flareMark(content, #lit + 1)
        mark.wash:ClearAllPoints()
        mark.wash:SetPoint("TOPLEFT", g.first, "TOPLEFT", -FLARE_PAD, 2)
        mark.wash:SetPoint("BOTTOMRIGHT", g.last, "BOTTOMRIGHT", FLARE_PAD, -2)
        mark.bar:ClearAllPoints()
        mark.bar:SetPoint("TOPLEFT", g.first, "TOPLEFT", -FLARE_PAD, 2)
        mark.bar:SetPoint("BOTTOMRIGHT", g.first, "BOTTOMRIGHT", FLARE_PAD, -2)
        mark.edge:ClearAllPoints()
        mark.edge:SetPoint("TOPLEFT", mark.wash, "TOPRIGHT", 0, 0)
        mark.edge:SetPoint("BOTTOMLEFT", mark.wash, "BOTTOMRIGHT", 0, 0)
        showMark(mark, true)
        lit[#lit + 1] = g.questID
      end
    end
  end
  for i = #lit + 1, #flare.marks do
    showMark(flare.marks[i], false)
  end
  flare.lit = lit
  local first = groups[1] and groups[1].questID or nil
  local summary = string.format("%d quest(s), first=%s, in area=%s", #groups, tostring(first),
    #lit > 0 and table.concat(lit, ",") or "none")
  if summary ~= flare.summary then -- once per change: FlareUI redraws often
    flare.summary = summary
    H.Trace("tracker: FlareUI %s", summary)
  end
  if first ~= flare.first then
    flare.first = first
    if H.PlayerFrame.TrackingChanged then
      H.PlayerFrame.TrackingChanged()
    end
  end
end

-- After FlareUI's redraw; an error here never reaches FlareUI's own code.
local function afterFlareRender()
  local ok, err = pcall(flareDecorate)
  if not ok then
    H.Trace("tracker: FlareUI decoration failed: %s", tostring(err))
  end
  if H.PlayerFrame and H.PlayerFrame.Redock then -- the window docked to it, as tall (2026-11-05)
    local docked, why = pcall(H.PlayerFrame.Redock)
    if not docked then
      H.Trace("frame: docking failed: %s", tostring(why))
    end
  end
end

-- FlareUI's tracker frame while it runs (the addon's window docks to it, ui/player_frame.lua), else nil.
function Tracker.FlareHolder()
  local holder = Tracker.FlareUI() and _G["FlareUI_ObjectiveTracker"]
  return type(holder) == "table" and holder or nil
end

-- True when FlareUI's tracker stands on the right half of the screen (its own reading, its Side method; true when it
-- cannot say).
function Tracker.FlareOnRight()
  local tracker = flareTracker()
  local ok, right = pcall(function()
    return tracker:Side()
  end)
  return not ok or right ~= false
end

-- The first quest FlareUI's tracker shows (nil without it, or minimized): the followed quest of the logbook.
function Tracker.FirstShown()
  return Tracker.FlareUI() and flare.first or nil
end

-- The quests FlareUI's tracker shows in gold (tests, /fs area).
function Tracker.FlareHighlighted()
  return flare.lit
end

H.QuestArea.OnChange(function()
  if Tracker.FlareUI() then
    afterFlareRender()
  end
end)

H.WhenAvailable(function()
  local tracker = flareTracker()
  return tracker ~= nil and type(tracker.Render) == "function"
end, function()
  hooksecurefunc(flareTracker(), "Render", afterFlareRender)
  H.Trace("tracker: installed on FlareUI")
end)
