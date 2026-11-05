-- ForeverSpeech: the quests sorted by level in the objective tracker and the quest log (2026-10-21, asked by the
-- player; setting sortByLevel, on by default). Lowest level first, or highest first (setting sortOrder "asc" | "desc",
-- 2026-10-21); a quest of unknown level last either way, equal levels in the game's order. Nothing Blizzard is
-- replaced (anti-taint):
-- - tracker: it shows the watch list in its order (C_QuestLog.GetQuestIDForQuestWatchIndex). The quests out of
--   place are unwatched and watched again in level order (AddQuestWatch appends), with their watch type. Never in
--   combat (the tracker holds secure quest item buttons): after it.
-- - quest log: QuestScrollFrame.Contents lays its rows out by layoutIndex (Retail VerticalLayoutFrame). After
--   QuestLogQuests_Update, in each run of quest rows between two headers, the quests (title row and its objective
--   rows, all carrying questID) take the same layoutIndex values in level order, then Contents:Layout(). Without
--   Layout or layoutIndex, nothing changes.
-- Sorted again after each quest accepted, turned in or removed and each objective update (2026-10-21), and by hand
-- with the button on the tracker's "Tous les objectifs" header (ObjectiveTrackerFrame.Header, left of its minimize
-- button; the tracker's top right corner otherwise), in case the automatic sorting misses a case.
-- Unverified on Forever (H31): the watch API, the tracker following the watch list, the log's layout frame, the
-- tracker header. /fs sort probe stores what the client has in ForeverSpeechDB.sortProbe (on disk after /reload).
local H = ForeverSpeech
local L = H.L

local Sort = {}
H.QuestSort = Sort

local DEBOUNCE = 0.3 -- seconds: the quest events come in bursts

local call = H.Safe
local scheduled, applying, afterCombat, byHandAfterCombat
local failedOrder -- the tracker order the game did not keep: not tried again for the same quests

local function enabled()
  return ForeverSpeechDB and ForeverSpeechDB.sortByLevel and true or false
end

local function inCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function descending()
  return ForeverSpeechDB and ForeverSpeechDB.sortOrder == "desc"
end

-- Stable sort of items by the level of their quest (item.questID), in the setting's direction, unknown last.
local function byLevel(items)
  local desc = descending()
  local keyed = {}
  for i, item in ipairs(items) do
    local level = H.QuestData.Level(item.questID)
    keyed[i] = { item = item, level = level, pos = i }
  end
  table.sort(keyed, function(a, b)
    if a.level ~= b.level then
      if not a.level or not b.level then
        return b.level == nil
      end
      if desc then
        return a.level > b.level
      end
      return a.level < b.level
    end
    return a.pos < b.pos
  end)
  local out = {}
  for i, k in ipairs(keyed) do
    out[i] = k.item
  end
  return out
end
Sort.ByLevel = byLevel

-- Tracker ----------------------------------------------------------------------------------------------------------

local function watchAPI()
  local q = C_QuestLog
  if q and type(q.GetNumQuestWatches) == "function" and type(q.GetQuestIDForQuestWatchIndex) == "function"
    and type(q.AddQuestWatch) == "function" and type(q.RemoveQuestWatch) == "function" then
    return q
  end
end

local function watched(q)
  local list = {}
  local n = tonumber(call(q.GetNumQuestWatches)) or 0
  for i = 1, n do
    local questID = call(q.GetQuestIDForQuestWatchIndex, i)
    if type(questID) == "number" and questID > 0 then
      list[#list + 1] = questID
    end
  end
  return list
end
Sort.Watched = function()
  local q = watchAPI()
  return q and watched(q) or {}
end

-- force: by hand, an order the game did not keep is tried again.
local function sortTracker(force)
  if H.TrackerButtons.FlareUI() then -- FlareUI's tracker sorts itself (its option « Par niveau »), not by watch list
    return "FlareUI"
  end
  local q = watchAPI()
  if not q then
    return "no watch API"
  end
  local current = watched(q)
  local items = {}
  for i, questID in ipairs(current) do
    items[i] = { questID = questID }
  end
  local wanted = {}
  for i, item in ipairs(byLevel(items)) do
    wanted[i] = item.questID
  end
  local first
  for i = 1, #wanted do
    if wanted[i] ~= current[i] then
      first = i
      break
    end
  end
  if not first then
    return "sorted"
  end
  local key = table.concat(wanted, ",")
  if key == failedOrder and not force then
    return "kept by the game"
  end
  if inCombat() then
    afterCombat = true
    return "after combat"
  end
  -- The prefix is already in place; each quest of the rest, in level order, goes to the end of the list.
  applying = true
  for i = first, #wanted do
    local questID = wanted[i]
    local watchType = type(q.GetQuestWatchType) == "function" and call(q.GetQuestWatchType, questID) or nil
    pcall(q.RemoveQuestWatch, questID)
    pcall(q.AddQuestWatch, questID, watchType)
  end
  applying = false
  local now = table.concat(watched(q), ",")
  if now ~= key then
    failedOrder = key
    H.Trace("sort: tracker order not kept by the game (%s, wanted %s)", now, key)
    return "kept by the game"
  end
  failedOrder = nil
  return "moved " .. (#wanted - first + 1)
end

local lastRun -- FlareUI's tracker: its result traced once, not after every quest log update
local function run()
  scheduled = false
  if not enabled() then
    return
  end
  local result = sortTracker()
  if result ~= "FlareUI" or lastRun ~= "FlareUI" then
    H.Trace("sort: tracker %s", result)
  end
  lastRun = result
end

local function schedule()
  if applying or scheduled or not enabled() then
    return
  end
  scheduled = true
  C_Timer.After(DEBOUNCE, run)
end
Sort.Schedule = schedule

-- A quest accepted, turned in or removed, an objective updated (QUEST_LOG_UPDATE, UNIT_QUEST_LOG_CHANGED), a watch
-- added or removed, a level gained (the levels of the colors change, not the order: cheap to check).
for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
  "UNIT_QUEST_LOG_CHANGED", "QUEST_WATCH_LIST_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP" }) do
  H.TryRegisterEvent(event, schedule)
end
H.TryRegisterEvent("PLAYER_REGEN_ENABLED", function()
  if byHandAfterCombat then -- asked by hand: sorted even with the setting off
    byHandAfterCombat, afterCombat = false, false
    C_Timer.After(DEBOUNCE, function()
      H.Trace("sort: by hand after combat, tracker %s", sortTracker(true))
    end)
  elseif afterCombat then
    afterCombat = false
    schedule()
  end
end)

-- Quest log --------------------------------------------------------------------------------------------------------

local function rowQuest(row)
  local questID = tonumber(rawget(row, "questID"))
  return questID and questID > 0 and questID or nil
end

-- Sorts one run of quest rows (rows[i..j], in layout order): returns true when a layoutIndex changed.
local function sortRun(rows, i, j)
  local units, slots = {}, {}
  for k = i, j do
    local row = rows[k]
    slots[#slots + 1] = row.layoutIndex
    local questID = rowQuest(row)
    local unit = units[#units]
    if not unit or unit.questID ~= questID then
      unit = { questID = questID, rows = {} }
      units[#units + 1] = unit
    end
    unit.rows[#unit.rows + 1] = row
  end
  local changed, slot = false, 0
  for _, unit in ipairs(byLevel(units)) do
    for _, row in ipairs(unit.rows) do
      slot = slot + 1
      if row.layoutIndex ~= slots[slot] then
        row.layoutIndex = slots[slot]
        changed = true
      end
    end
  end
  return changed
end

local function sortLog()
  local contents = QuestScrollFrame and QuestScrollFrame.Contents
  if not (contents and type(contents.Layout) == "function" and type(contents.GetChildren) == "function") then
    return "no layout frame"
  end
  local rows = {}
  for _, child in ipairs({ contents:GetChildren() }) do
    if tonumber(rawget(child, "layoutIndex")) and child:IsShown() then
      rows[#rows + 1] = child
    end
  end
  table.sort(rows, function(a, b) return a.layoutIndex < b.layoutIndex end)
  local changed, i = false, 1
  while i <= #rows do
    if rowQuest(rows[i]) then
      local j = i
      while j < #rows and rowQuest(rows[j + 1]) do
        j = j + 1
      end
      changed = sortRun(rows, i, j) or changed
      i = j + 1
    else
      i = i + 1
    end
  end
  if changed then
    contents:Layout()
  end
  return changed and "sorted" or "unchanged"
end
Sort.SortLog = sortLog

local function onLogUpdate()
  if enabled() then
    H.Trace("sort: quest log %s", sortLog())
  end
end

-- Loaded after ui/questlog_buttons.lua: its row hook runs first, and a quest keeps the relative order of its rows.
H.WhenAvailable(function()
  return type(QuestLogQuests_Update) == "function"
end, function()
  hooksecurefunc("QuestLogQuests_Update", onLogUpdate)
  H.Trace("sort: quest log hook installed")
end)

-- By hand -----------------------------------------------------------------------------------------------------------

-- Sorts the tracker and the quest log now, even with the setting off; says the result in the chat.
function Sort.SortNow()
  local tracker = sortTracker(true)
  local log = sortLog()
  H.Trace("sort: by hand, tracker %s, quest log %s", tracker, log)
  if tracker == "after combat" then
    byHandAfterCombat = true
    H.Print(L.SORT_AFTER_COMBAT)
  elseif tracker == "kept by the game" then
    H.Print(L.SORT_KEPT)
  elseif tracker == "no watch API" then
    H.Print(L.SORT_UNAVAILABLE)
  elseif tracker == "FlareUI" then
    H.Print(L.SORT_FLAREUI)
  else
    H.Print(L.SORT_DONE)
  end
  return tracker, log
end

local function trackerHeader()
  local frame = _G.ObjectiveTrackerFrame
  return frame, frame and rawget(frame, "Header")
end

-- The other direction (right click on the button, /fs sort asc|desc), then sorted now.
function Sort.SetOrder(order)
  ForeverSpeechDB.sortOrder = order == "desc" and "desc" or "asc"
  failedOrder = nil
  H.Print(descending() and L.SORT_ORDER_DESC or L.SORT_ORDER_ASC)
  return Sort.SortNow()
end

local function tooltip()
  return L.SORT_BUTTON, descending() and L.SORT_DESC or L.SORT_ASC, L.SORT_HINT
end

-- The sort button on the tracker's header, left of its minimize button: left click sorts, right click turns the
-- direction around.
local function installButton()
  local frame, header = trackerHeader()
  local parent = header or frame
  local b = H.Style.RowButton(parent, "list", 16, tooltip)
  local minimize = header and rawget(header, "MinimizeButton")
  if minimize then
    b:SetPoint("RIGHT", minimize, "LEFT", -4, 0)
  else
    b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -24, 0)
  end
  if b.RegisterForClicks then
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  end
  b:SetScript("OnClick", function(_, mouse)
    H.Style.Sound()
    if mouse == "RightButton" then
      Sort.SetOrder(descending() and "asc" or "desc")
    else
      Sort.SortNow()
    end
  end)
  Sort.button = b
  H.Trace("sort: button on %s (minimize=%s)", header and "the tracker header" or "the tracker", minimize ~= nil)
end

H.WhenAvailable(function()
  return _G.ObjectiveTrackerFrame ~= nil
end, installButton)

-- Probe (H31) -------------------------------------------------------------------------------------------------------

local function frameName(f)
  if type(f) ~= "table" then
    return tostring(f)
  end
  return (f.GetName and f:GetName()) or (f.GetDebugName and f:GetDebugName()) or "?"
end

local function probe()
  local out = {}
  local function add(fmt, ...)
    out[#out + 1] = string.format(fmt, ...)
  end
  local q = C_QuestLog or {}
  for _, name in ipairs({ "GetNumQuestWatches", "GetQuestIDForQuestWatchIndex", "AddQuestWatch", "RemoveQuestWatch",
    "GetQuestWatchType", "SortQuestWatches" }) do
    add("C_QuestLog.%s: %s", name, type(q[name]))
  end
  local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
  add("trackQuestSorting: %s", tostring(type(getCVar) == "function" and call(getCVar, "trackQuestSorting")))
  for i, questID in ipairs(Sort.Watched()) do
    add("watch %d: quest %s level %s type %s", i, questID, tostring(H.QuestData.Level(questID)),
      tostring(type(q.GetQuestWatchType) == "function" and call(q.GetQuestWatchType, questID)))
  end
  local frame, header = trackerHeader()
  add("ObjectiveTrackerFrame: %s Header %s MinimizeButton %s Text %s", tostring(frame ~= nil), tostring(header ~= nil),
    tostring(header and rawget(header, "MinimizeButton") ~= nil),
    tostring(header and rawget(header, "Text") and header.Text.GetText and header.Text:GetText()))
  local contents = QuestScrollFrame and QuestScrollFrame.Contents
  add("Contents: %s Layout %s MarkDirty %s", tostring(contents ~= nil), type(contents and contents.Layout),
    type(contents and contents.MarkDirty))
  if contents and contents.GetChildren then
    local children = { contents:GetChildren() }
    add("children: %d", #children)
    for i, child in ipairs(children) do
      if i > 40 then
        break
      end
      local point, rel, relPoint, x, y = child:GetPoint(1)
      add("child %d: %s shown=%s questID=%s layoutIndex=%s header=%s point=%s %s %s %s %s", i,
        tostring(child.GetObjectType and child:GetObjectType()), tostring(child:IsShown()),
        tostring(rawget(child, "questID")), tostring(rawget(child, "layoutIndex")),
        tostring(rawget(child, "headerIndex") or rawget(child, "questLogIndex")), tostring(point), frameName(rel),
        tostring(relPoint), tostring(x), tostring(y))
    end
  end
  ForeverSpeechDB.sortProbe = out
  return out
end
Sort.Probe = probe

H.RegisterCommand("sort", function(arg)
  arg = (arg or ""):lower()
  if arg == "on" or arg == "off" then
    ForeverSpeechDB.sortByLevel = arg == "on"
    failedOrder = nil
    schedule()
  elseif arg == "asc" or arg == "desc" then
    Sort.SetOrder(arg)
    return
  elseif arg == "probe" then
    local out = probe()
    H.Print("sort probe: %d lines stored in ForeverSpeechDB.sortProbe (on disk after /reload)", #out)
    return
  end
  H.Print("quests sorted by level (tracker and quest log): %s, %s", enabled() and "on" or "off",
    descending() and "highest first" or "lowest first")
end, "sort [on|off|asc|desc|probe] - quests sorted by level in the objective tracker and the quest log")
