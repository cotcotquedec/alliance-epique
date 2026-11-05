-- ForeverSpeech: the companion journal (D18, 2026-10-15; the criteria: docs/companions.md). The players the character
-- has grouped with, the time spent together, a friendship tier, a few stats, and a line of Elise when a companion
-- reaches a tier.
-- What counts: the party, or the player's own subgroup in a raid; never a battleground or an arena; a member's time
-- only while connected. A group counts (the "groups" stat, the companion enters the table) after COUNTED_AFTER
-- seconds together. One table of MAX_COMPANIONS per character (ForeverSpeechDB.companions[name-realm]); when full,
-- the companion with the least time leaves. A companion is known by the character's GUID, never by its name.
-- The running counters are folded into the totals at each roster change, every TICK seconds and at logout; an open
-- group is saved too, and resumed after a /reload or a short disconnection (RESUME_WITHIN): it is the same group.
-- The tiers come from the index (contract v8, from data/zones/@elise/companions/scripts.json): the highest tier whose
-- time is reached; the rank tier (best friend) is the first of the table, with its time reached.
-- Elise: the highest tier reached in one update, once ("Rencontre" at most once per group), one of its lines drawn
-- without repeat (a bag per tier, kept per character), automatic only with its audio (as her level-up lines).
-- Unverified on Forever: GROUP_ROSTER_UPDATE, IsInGroup, IsInRaid, GetNumGroupMembers, GetNumSubgroupMembers,
-- GetRaidRosterInfo, UnitIsUnit, UnitGUID of a party unit ("Player-..."), UnitIsConnected, UNIT_CONNECTION,
-- IsInInstance, GetInstanceInfo, QUEST_TURNED_IN.
local H = ForeverSpeech
local L = H.L

local Companions = {}
H.Companions = Companions

local COUNTED_AFTER = 300 -- seconds together before a group counts
local MAX_COMPANIONS = 100
local TICK = 60            -- seconds between two folds while grouped
local RESUME_WITHIN = 600  -- seconds: an open group saved at logout or /reload is resumed if back within
local SPEAK_DELAY = 2      -- seconds before Elise speaks (the chat line first)

local sessions = {}        -- GUID -> { name, class, sex, online, seconds, counted, instances = {name = true} }
local lastFold             -- GetTime() of the last fold
local toResume             -- the open group saved before the /reload: GUID -> saved session (taken at the first update)
local encounterSaid = false -- "Rencontre" said in this group
local announced = {}       -- line ID -> "Bon ami · Arthas", the window's title of a line being played
local listeners = {}

-- A secret value (instances and combat, Forever) reads as nil (H.Safe, 2026-10-21).
local call = H.Safe

local function character()
  local name = call(UnitName, "player") or "?"
  local realm = call(GetRealmName) or "?"
  return tostring(name) .. "-" .. tostring(realm)
end

-- This character's journal: { list = {GUID -> entry}, groupSeconds, best = GUID, bags = {tier -> {line IDs}},
-- open = {GUID -> {seconds, counted, instances}}, openAt }. nil before SavedVariables are loaded.
local function journal()
  if type(ForeverSpeechDB) ~= "table" then
    return nil
  end
  ForeverSpeechDB.companions = ForeverSpeechDB.companions or {}
  local key = character()
  local j = ForeverSpeechDB.companions[key]
  if not j then
    j = { list = {}, groupSeconds = 0, bags = {} }
    ForeverSpeechDB.companions[key] = j
  end
  return j
end

function Companions.OnChange(fn)
  listeners[#listeners + 1] = fn
end

local function notify()
  for _, fn in ipairs(listeners) do
    pcall(fn)
  end
end

-- Tiers ------------------------------------------------------------------------------------------------------------

-- The place and the tier of the best friend (the rank tier), or nil.
local function rankTier()
  for i, tier in ipairs(H.Index.CompanionTiers()) do
    if tier.rank then
      return i, tier
    end
  end
  return nil
end

-- The place of the highest tier a time reaches (rank tier left out), 0 for none.
local function tierPlace(seconds)
  local found = 0
  for i, tier in ipairs(H.Index.CompanionTiers()) do
    if not tier.rank and tier.from and seconds >= tier.from then
      found = i
    end
  end
  return found
end

-- The GUID of the first of the table, if the time of the best friend tier is reached. Ties: the smaller GUID.
local function firstOfTable(j)
  local _, tier = rankTier()
  if not tier then
    return nil
  end
  local best, seconds
  for guid, entry in pairs(j.list) do
    if not seconds or entry.seconds > seconds or (entry.seconds == seconds and guid < best) then
      best, seconds = guid, entry.seconds
    end
  end
  return best and seconds >= (tier.from or math.huge) and best or nil
end

local function tierName(tier, sex)
  if not tier then
    return nil
  end
  return (sex == 3 and tier.nameF) or tier.name
end

-- The tier of a companion: { place, key, name (by the companion's sex), from } or nil.
function Companions.Tier(guid)
  local j = journal()
  local entry = j and j.list[guid]
  if not entry then
    return nil
  end
  local place, tier
  if firstOfTable(j) == guid then
    place, tier = rankTier()
  end
  if not tier then
    place = tierPlace(entry.seconds)
    tier = H.Index.CompanionTiers()[place]
  end
  if not tier then
    return nil
  end
  return { place = place, key = tier.key, name = tierName(tier, entry.sex), from = tier.from }
end

-- Roster -----------------------------------------------------------------------------------------------------------

local function excluded()
  local inInstance, kind = call(IsInInstance)
  return inInstance and (kind == "pvp" or kind == "arena") or false
end

-- The units of the player's companions: party1..4, or the player's subgroup in a raid.
local function units()
  local list = {}
  if not call(IsInGroup) then
    return list
  end
  if call(IsInRaid) then
    local count, mine = tonumber(call(GetNumGroupMembers)) or 0, nil
    local groups = {}
    for i = 1, count do
      local _, _, subgroup = call(GetRaidRosterInfo, i)
      groups[i] = subgroup
      if call(UnitIsUnit, "raid" .. i, "player") then
        mine = subgroup
      end
    end
    for i = 1, count do
      if mine and groups[i] == mine and not call(UnitIsUnit, "raid" .. i, "player") then
        list[#list + 1] = "raid" .. i
      end
    end
  else
    local count = tonumber(call(GetNumSubgroupMembers)) or ((tonumber(call(GetNumGroupMembers)) or 1) - 1)
    for i = 1, math.min(count, 4) do
      list[#list + 1] = "party" .. i
    end
  end
  return list
end

local function member(unit)
  local guid = call(UnitGUID, unit)
  if type(guid) ~= "string" or not guid:find("^Player%-") then
    return nil
  end
  local name, realm = call(UnitName, unit)
  if realm and realm ~= "" then
    name = name .. "-" .. realm
  end
  local _, class = call(UnitClass, unit)
  local connected = call(UnitIsConnected, unit)
  return guid, { name = name, class = class, sex = call(UnitSex, unit), online = connected ~= false }
end

-- Counting -----------------------------------------------------------------------------------------------------------

local function count(j)
  local n = 0
  for _ in pairs(j.list) do
    n = n + 1
  end
  return n
end

-- Room for one more: the companion with the least time, not in the group, leaves.
local function makeRoom(j)
  if count(j) < MAX_COMPANIONS then
    return
  end
  local lowest
  for guid, entry in pairs(j.list) do
    if not sessions[guid] and (not lowest or entry.seconds < j.list[lowest].seconds) then
      lowest = guid
    end
  end
  if lowest then
    H.Trace("companions: table full, %s leaves", j.list[lowest].name)
    j.list[lowest] = nil
    if j.best == lowest then
      j.best = nil
    end
  end
end

local function instancesOf(session)
  local n = 0
  for _ in pairs(session.instances) do
    n = n + 1
  end
  return n
end

-- A group counted: the companion enters the table (or gets one more group), with the time of this session.
local function countGroup(j, guid, s)
  s.counted = true
  local entry = j.list[guid]
  if not entry then
    makeRoom(j)
    entry = { seconds = 0, groups = 0, longest = 0, dungeons = 0, quests = 0, levels = 0, tier = 0,
              firstAt = call(time), firstZone = call(GetRealZoneText), firstLevel = call(UnitLevel, "player") }
    j.list[guid] = entry
  end
  entry.name, entry.class, entry.sex = s.name or entry.name, s.class or entry.class, s.sex or entry.sex
  entry.groups = (entry.groups or 0) + 1
  entry.seconds = (entry.seconds or 0) + s.seconds
  entry.longest = math.max(entry.longest or 0, s.seconds)
  entry.dungeons = (entry.dungeons or 0) + instancesOf(s)
  entry.lastAt = call(time)
  H.Trace("companions: group counted with %s (%s groups, %s s)", s.name, entry.groups, entry.seconds)
end

-- Adds the time since the last fold to each connected member (and to the group time).
local function fold(j)
  local t = GetTime()
  local elapsed = lastFold and math.max(0, t - lastFold) or 0
  lastFold = t
  local anyone = false
  for guid, s in pairs(sessions) do
    if s.online then
      anyone = true
      s.seconds = s.seconds + elapsed
      local entry = s.counted and j.list[guid]
      if entry then
        entry.seconds = entry.seconds + elapsed
        entry.longest = math.max(entry.longest or 0, s.seconds)
        entry.lastAt = call(time)
      end
    end
  end
  if anyone then
    j.groupSeconds = (j.groupSeconds or 0) + elapsed
  end
end

-- Saves the open group, resumed after a /reload (sessions live in memory).
local function saveOpen(j)
  local open = {}
  for guid, s in pairs(sessions) do
    open[guid] = { seconds = s.seconds, counted = s.counted, instances = s.instances }
  end
  j.open, j.openAt = open, call(time)
end

-- Elise ------------------------------------------------------------------------------------------------------------

-- Draws a line of a tier without repeat: the bag holds the lines not said yet (with audio only); empty, it refills.
local function draw(j, place, tier)
  local lines = (ForeverSpeechIndex and ForeverSpeechIndex.companions and ForeverSpeechIndex.companions.lines) or {}
  local bag = j.bags[tier.key]
  if type(bag) ~= "table" or #bag == 0 then
    bag = {}
    for id, entry in pairs(lines) do
      if math.floor(id / 100) == place and entry.intro then
        bag[#bag + 1] = id
      end
    end
    table.sort(bag)
    j.bags[tier.key] = bag
  end
  while #bag > 0 do
    local id = table.remove(bag, math.random(#bag))
    if lines[id] and lines[id].intro then
      return id
    end
  end
  return nil
end

-- Elise's line for a tier reached. Returns "off", "no audio" or the Player.PlayLine status (after SPEAK_DELAY).
local function speak(j, guid, place)
  if not ForeverSpeechDB.companionLines or not H.IsEnabled() then
    return "off"
  end
  local tier = H.Index.CompanionTiers()[place]
  local id = tier and draw(j, place, tier)
  if not id then
    H.Trace("companions: no audio for %s", tier and tier.key)
    return "no audio"
  end
  local entry = j.list[guid]
  announced[id] = string.format("%s · %s", tierName(tier, entry.sex), entry.name or "?")
  C_Timer.After(SPEAK_DELAY, function()
    local status, detail = H.Player.PlayLine("companion", id, H.Player.AUTO)
    H.Trace("companions: line %s for %s: %s %s", id, entry.name, status, detail)
  end)
  return "queued"
end

-- The tiers reached since the last update: a chat line each, and Elise for the highest one.
local function checkTiers(j)
  local reached = {}
  for guid, s in pairs(sessions) do
    local entry = s.counted and j.list[guid]
    if entry then
      local place = tierPlace(entry.seconds)
      if place > (entry.tier or 0) then
        entry.tier = place
        reached[#reached + 1] = { guid = guid, place = place }
      end
    end
  end
  local best = firstOfTable(j)
  if best ~= j.best then
    j.best = best
    if best and sessions[best] then
      reached[#reached + 1] = { guid = best, place = (rankTier()) }
    end
  end
  if #reached == 0 then
    return
  end
  table.sort(reached, function(a, b) return a.place > b.place end)
  local tiers = H.Index.CompanionTiers()
  local encounters = {}
  for _, r in ipairs(reached) do
    local entry, tier = j.list[r.guid], tiers[r.place]
    if tier.key == "encounter" then
      encounters[#encounters + 1] = entry.name or "?"
    elseif ForeverSpeechDB.companionsChat ~= false then
      H.Print(L.COMPANION_TIER, entry.name or "?", (tierName(tier, entry.sex):gsub("^%u", string.lower)))
    end
  end
  if #encounters > 0 and ForeverSpeechDB.companionsChat ~= false then
    H.Print(L.COMPANION_ENCOUNTERS, table.concat(encounters, ", "))
  end
  local top = reached[1]
  if tiers[top.place].key == "encounter" then
    if encounterSaid then
      return
    end
    encounterSaid = true
  end
  speak(j, top.guid, top.place)
end

-- Update -----------------------------------------------------------------------------------------------------------

-- Folds the counters, then reads the group: members gone end their session, new ones start one.
function Companions.Update()
  local j = journal()
  if not j then
    return
  end
  if ForeverSpeechDB.companionsTrack == false then -- option (2026-10-15): nothing counted, the open group dropped
    sessions, lastFold, toResume = {}, nil, {}
    j.open = nil
    notify()
    return
  end
  fold(j)
  local present = {}
  if not excluded() then
    for _, unit in ipairs(units()) do
      local guid, info = member(unit)
      if guid then
        present[guid] = info
      end
    end
  end
  if not toResume then -- the roster may come a little after login: a saved member is resumed when it shows up
    local recent = j.openAt and call(time) and call(time) - j.openAt <= RESUME_WITHIN
    toResume = recent and j.open or {}
  end
  for guid, saved in pairs(toResume) do
    if present[guid] and not sessions[guid] then
      sessions[guid] = { seconds = saved.seconds or 0, counted = saved.counted, instances = saved.instances or {} }
      H.Trace("companions: %s resumed (%s s)", tostring(present[guid].name), sessions[guid].seconds)
    end
    if present[guid] then
      toResume[guid] = nil
    end
  end
  for guid in pairs(sessions) do
    if not present[guid] then
      H.Trace("companions: %s left (%s s)", sessions[guid].name, sessions[guid].seconds)
      sessions[guid] = nil
    end
  end
  for guid, info in pairs(present) do
    local s = sessions[guid]
    if not s then
      s = { seconds = 0, instances = {} }
      sessions[guid] = s
      H.Trace("companions: %s joined", info.name)
    end
    s.name, s.class, s.sex, s.online = info.name, info.class, info.sex, info.online
    local entry = j.list[guid]
    if entry then
      entry.name, entry.class, entry.sex = info.name or entry.name, info.class or entry.class, info.sex or entry.sex
    end
  end
  for guid, s in pairs(sessions) do
    if not s.counted and s.seconds >= COUNTED_AFTER then
      countGroup(j, guid, s)
    end
  end
  if next(sessions) == nil then
    encounterSaid = false
  end
  saveOpen(j)
  checkTiers(j)
  notify()
end

-- Stats while grouped: an instance entered (once per instance and group), a quest turned in, a level gained.
local function together(field)
  local j = journal()
  if not j then
    return
  end
  for guid, s in pairs(sessions) do
    local entry = s.counted and s.online and j.list[guid]
    if entry then
      entry[field] = (entry[field] or 0) + 1
    end
  end
  notify()
end

local function enteredWorld()
  Companions.Update()
  local inInstance, kind = call(IsInInstance)
  if not inInstance or (kind ~= "party" and kind ~= "raid") then
    return
  end
  local name = call(GetInstanceInfo) or "?"
  local j = journal()
  for guid, s in pairs(sessions) do
    if s.online and not s.instances[name] then
      s.instances[name] = true
      local entry = s.counted and j and j.list[guid]
      if entry then
        entry.dungeons = (entry.dungeons or 0) + 1
      end
    end
  end
end

local function tick()
  if next(sessions) ~= nil then
    Companions.Update()
  end
  C_Timer.After(TICK, tick)
end

-- Reading ----------------------------------------------------------------------------------------------------------

function Companions.Get(guid)
  local j = journal()
  return j and j.list[guid] or nil
end

-- The first n companions by time together: { {guid, entry, rank}, ... }.
function Companions.Top(n)
  local j, list = journal(), {}
  for guid, entry in pairs(j and j.list or {}) do
    list[#list + 1] = { guid = guid, entry = entry }
  end
  table.sort(list, function(a, b)
    if a.entry.seconds ~= b.entry.seconds then
      return a.entry.seconds > b.entry.seconds
    end
    return a.guid < b.guid
  end)
  local top = {}
  for i = 1, math.min(n or #list, #list) do
    list[i].rank = i
    top[i] = list[i]
  end
  return top
end

-- { groupSeconds, total (played, or nil), companions }: the character's own figures.
function Companions.Summary()
  local j = journal()
  return { groupSeconds = j and j.groupSeconds or 0, total = H.Played and H.Played.Total() or nil,
           companions = j and count(j) or 0 }
end

-- The share of a time in another, 0 to 100 (rounded), or nil without the whole.
function Companions.Share(part, whole)
  if not whole or whole <= 0 then
    return nil
  end
  return math.floor(math.min(1, (part or 0) / whole) * 100 + 0.5)
end

-- "35 min" under an hour, "12 h 40" beyond.
function Companions.FormatDuration(seconds)
  seconds = math.floor(tonumber(seconds) or 0)
  if seconds < 3600 then
    return string.format("%d min", math.floor(seconds / 60))
  end
  return string.format("%d h %02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

-- The window's title of a line of Elise being played: "Bon ami · Arthas", or nil.
function Companions.Announced(id)
  return announced[tonumber(id) or -1]
end

-- Events -----------------------------------------------------------------------------------------------------------

H.TryRegisterEvent("GROUP_ROSTER_UPDATE", Companions.Update)
H.TryRegisterEvent("UNIT_CONNECTION", Companions.Update)
H.TryRegisterEvent("PLAYER_ENTERING_WORLD", enteredWorld)
H.TryRegisterEvent("ZONE_CHANGED_NEW_AREA", enteredWorld)
H.TryRegisterEvent("PLAYER_LOGOUT", Companions.Update)
H.TryRegisterEvent("QUEST_TURNED_IN", function()
  together("quests")
end)
H.TryRegisterEvent("PLAYER_LEVEL_UP", function()
  together("levels")
end)
H.OnInit(function()
  C_Timer.After(TICK, tick)
end)

H.RegisterCommand("friends", function(arg)
  arg = (arg or ""):lower()
  if arg == "on" or arg == "off" then
    ForeverSpeechDB.companionLines = arg == "on"
    H.Print("companion lines: %s", arg)
    return
  end
  local tierKey = arg:match("^say%s+(%S+)$")
  if tierKey then -- a line of a tier, with the client's speech synthesis while her audio is missing
    for place, tier in ipairs(H.Index.CompanionTiers()) do
      if tier.key == tierKey then
        local id = place * 100 + math.random(10)
        H.Print("%s: %s", id, tostring(H.Player.PlayLine("companion", id)))
        return
      end
    end
    H.Print("unknown tier %s", tierKey)
    return
  end
  Companions.Update()
  if arg ~= "list" and Companions.Toggle then -- the window (2026-10-21); "list": in the chat as before
    Companions.Toggle()
    return
  end
  for _, item in ipairs(Companions.Top(10)) do
    local tier = Companions.Tier(item.guid)
    H.Print("%d. %s, %s, %s, %d groups", item.rank, item.entry.name or "?", tier and tier.name or "-",
      Companions.FormatDuration(item.entry.seconds), item.entry.groups or 0)
  end
end, "friends [list|on|off|say <tier>] - the companions' window (list: in the chat), Elise's lines on and off")
