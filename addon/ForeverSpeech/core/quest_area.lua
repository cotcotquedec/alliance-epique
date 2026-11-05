-- ForeverSpeech: the quests whose objective area (the shaded blob of the minimap and the map) the player stands in
-- (2026-10-18), highlighted in the objective tracker and the quest log (setting questAreaHighlight).
-- The client decides, not us: the world map draws a quest's area with a QuestPOIFrame and finds the quest under the
-- cursor with its C-side UpdateMouseOverTooltip(x, y), in normalized map coordinates. This module owns an invisible
-- QuestPOIFrame and asks it with the player's position, one quest drawn at a time (with every area drawn at once,
-- the hit test never answers). Verified on Forever on 2026-10-18 (H16, /fs zonetest): quest 112 inside its area,
-- none outside.
local H = ForeverSpeech

local Area = {}
H.QuestArea = Area

local PERIOD = 1      -- seconds between two looks
local MOVE = 0.001    -- map share the player must move for a new look (about 3 yards in Elwynn)
local FORCE = 10      -- seconds after which a look happens even without moving (areas change with objectives)

local layer, layerFailed
local inside = {}     -- questID -> true
local last = {}       -- map, x, y, at of the last look
local dirty = true
local listeners = {}

-- A secret value (instances and combat, Forever) reads as nil (H.Safe, 2026-10-21).
local call = H.Safe

local function getLayer()
  if layer or layerFailed then
    return layer
  end
  local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, UIParent)
  if not ok or not f or type(f.UpdateMouseOverTooltip) ~= "function" then
    layerFailed = true
    H.Trace("quest area: no QuestPOIFrame (%s)", ok and "no hit test" or f)
    return nil
  end
  -- Shown, as in the probe's hit tests, but transparent and not clickable.
  f:SetSize(600, 400)
  f:SetPoint("CENTER")
  f:SetAlpha(0)
  if f.EnableMouse then
    f:EnableMouse(false)
  end
  call(f.SetFillTexture, f, "Interface\\WorldMap\\UI-QuestBlob-Inside")
  call(f.SetBorderTexture, f, "Interface\\WorldMap\\UI-QuestBlob-Outside")
  layer = f
  return f
end

-- questIDs with a point on the map (the client's list), or {}.
local function questsOnMap(mapID)
  local out = {}
  local pois = C_QuestLog and call(C_QuestLog.GetQuestsOnMap, mapID)
  for _, poi in ipairs(type(pois) == "table" and pois or {}) do
    if tonumber(poi.questID) then
      out[#out + 1] = poi.questID
    end
  end
  return out
end

-- The player's map and normalized position, or nil.
local function position()
  local mapID = C_Map and call(C_Map.GetBestMapForUnit, "player")
  local pos = mapID and call(C_Map.GetPlayerMapPosition, mapID, "player")
  if not pos then
    return nil
  end
  local x, y = pos:GetXY()
  if not x or (x == 0 and y == 0) then
    return nil
  end
  return mapID, x, y
end

local function same(a, b)
  for k in pairs(a) do
    if not b[k] then
      return false
    end
  end
  for k in pairs(b) do
    if not a[k] then
      return false
    end
  end
  return true
end

local function notify()
  for _, fn in ipairs(listeners) do
    local ok, err = pcall(fn)
    if not ok then
      H.Debug("quest area listener error: %s", tostring(err))
    end
  end
end

-- The quests whose area holds the point, by the client's hit test.
local function test(f, mapID, x, y)
  local found = {}
  call(f.SetMapID, f, mapID)
  for _, questID in ipairs(questsOnMap(mapID)) do
    call(f.DrawNone, f)
    call(f.DrawBlob, f, questID, true)
    if call(f.UpdateMouseOverTooltip, f, x, y) == questID then
      found[questID] = true
    end
  end
  call(f.DrawNone, f)
  return found
end

-- One look (setting on): the listeners hear of every change of the set.
function Area.Update(force)
  local now = {}
  if ForeverSpeechDB.questAreaHighlight then
    local f = getLayer()
    local mapID, x, y = position()
    if f and mapID then
      local moved = mapID ~= last.map or not last.x or math.abs(x - last.x) > MOVE or math.abs(y - last.y) > MOVE
      local stale = not last.at or GetTime() - last.at >= FORCE
      if not (force or dirty or moved or stale) then
        return
      end
      last.map, last.x, last.y, last.at = mapID, x, y, GetTime()
      dirty = false
      now = test(f, mapID, x, y)
    end
  end
  if not same(now, inside) then
    inside = now
    local ids = {}
    for questID in pairs(inside) do
      ids[#ids + 1] = questID
    end
    H.Trace("quest area: inside %s", #ids > 0 and table.concat(ids, ",") or "none")
    notify()
  end
end

-- True when the player stands in the quest's area (and the setting is on).
function Area.Inside(questID)
  return inside[tonumber(questID) or 0] == true
end

-- fn() after each change of the set.
function Area.OnChange(fn)
  listeners[#listeners + 1] = fn
end

-- After the setting changes: a look now (an empty set when off).
function Area.Refresh()
  dirty = true
  Area.Update(true)
end

local ticker = CreateFrame("Frame")
local elapsed = 0
ticker:SetScript("OnUpdate", function(_, dt)
  elapsed = elapsed + (dt or 0)
  if elapsed < PERIOD or not H.initialized then
    return
  end
  elapsed = 0
  Area.Update()
end)

local function markDirty()
  dirty = true
end
H.TryRegisterEvent("QUEST_LOG_UPDATE", markDirty)
H.TryRegisterEvent("ZONE_CHANGED_NEW_AREA", markDirty)
H.TryRegisterEvent("QUEST_POI_UPDATE", markDirty)

H.RegisterCommand("area", function()
  Area.Refresh()
  local titles = {}
  for questID in pairs(inside) do
    titles[#titles + 1] = H.QuestData.Title(questID) or ("#" .. questID)
  end
  local mapID, x, y = position()
  H.Print("quest areas (map %s at %s, %s): %s", tostring(mapID), x and string.format("%.3f", x) or "?",
    y and string.format("%.3f", y) or "?", #titles > 0 and table.concat(titles, ", ") or "none")
end, "area - the quests whose objective area you stand in (highlighted in the tracker and the quest log)")
