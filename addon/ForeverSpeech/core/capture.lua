-- ForeverSpeech: capture of the quest detail text at QUEST_DETAIL (CLAUDE.md section 9.2, D1), and
-- of the turn-in text at QUEST_COMPLETE (reward panel, 2026-10-06; GetRewardText unverified on Forever,
-- spike S9). Stored in ForeverSpeechCaptures for the companion. The Lua-side text hash is only used to
-- deduplicate (questID, text) pairs; divergence detection belongs to the pipeline (D7).
local H = ForeverSpeech

local Capture = {}
H.Capture = Capture

local CAPTURE_VERSION = 1

-- djb2 over the bytes, kept in 32 bits with plain arithmetic (exact in Lua 5.1 doubles).
function Capture.Hash(text)
  local h = 5381
  for i = 1, #text do
    h = (h * 33 + text:byte(i)) % 4294967296
  end
  return string.format("%08x", h)
end

-- "Creature-0-4621-0-80-823-0000407152" -> "Creature", 823 (verified format, S4).
function Capture.ParseGUID(guid)
  guid = H.NotSecret(guid) -- an NPC's GUID is secret in instances and combat (Forever): unknown
  if type(guid) ~= "string" then
    return nil, nil
  end
  local unitType, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  return unitType or guid:match("^(%a+)"), tonumber(id)
end

local function store()
  local db = ForeverSpeechCaptures
  db.version = CAPTURE_VERSION
  db.quests = db.quests or {}
  return db.quests
end

-- A secret value (NPC name and GUID, GetTitleText, GetQuestID in instances and combat) reads as nil: nothing is
-- captured then, and nothing errors (H.Safe, 2026-10-21).
local safe = H.Safe

-- GetQuestItemInfo(type, i) -> name, texture, count, quality, isUsable, itemID (seen in S4).
local function readItems(kind, count)
  local items = {}
  for i = 1, count or 0 do
    local ok, name, texture, num, quality, _, itemID = pcall(GetQuestItemInfo, kind, i)
    if ok and texture then
      items[#items + 1] = {
        name = (name ~= "" and name) or nil,
        texture = texture,
        count = num,
        quality = quality,
        itemID = (itemID and itemID ~= 0) and itemID or nil,
      }
    end
  end
  return items
end

-- True when a rewards table has anything to show.
function Capture.HasRewards(rewards)
  if type(rewards) ~= "table" then
    return false
  end
  return #(rewards.items or {}) > 0 or #(rewards.choices or {}) > 0 or (rewards.money or 0) > 0
    or (rewards.xp or 0) > 0
end

local function readRewards()
  return {
    items = readItems("reward", safe(GetNumQuestRewards)),
    choices = readItems("choice", safe(GetNumQuestChoices)),
    money = safe(GetRewardMoney),
    xp = safe(GetRewardXP),
  }
end

-- Reads the open quest detail. Returns the record, or nil when there is no quest text.
function Capture.Snapshot(startItemID)
  local questID = safe(GetQuestID)
  local text = safe(GetQuestText)
  if not questID or questID == 0 or not text or text == "" then
    return nil
  end
  local guid = safe(UnitGUID, "npc")
  local unitType, npcID = Capture.ParseGUID(guid)
  local creatureType, creatureTypeID = safe(UnitCreatureType, "npc")
  local version, build = GetBuildInfo()
  return {
    questID = questID,
    title = safe(GetTitleText),
    text = text,
    objectives = safe(GetObjectiveText),
    giverType = unitType,                     -- Creature, GameObject, ... (nil if no unit)
    npcID = unitType == "Creature" and npcID or nil,
    giverID = npcID,
    giverName = safe(UnitName, "npc"),
    npcSex = safe(UnitSex, "npc"),
    npcCreatureType = creatureType,
    npcCreatureTypeID = creatureTypeID,
    startItemID = (startItemID and startItemID ~= 0) and startItemID or nil,
    zone = safe(GetZoneText),
    subZone = safe(GetSubZoneText),
    mapID = C_Map and safe(C_Map.GetBestMapForUnit, "player"),
    locale = safe(GetLocale),
    playerSex = safe(UnitSex, "player"),
    -- The client substitutes these in the text ($N, $C, $R): the pipeline needs them to put the
    -- neutral form back (D8), so that one audio fits every character.
    playerName = safe(UnitName, "player"),
    playerClass = safe(UnitClass, "player"),
    playerRace = safe(UnitRace, "player"),
    rewards = readRewards(),
    client = tostring(version) .. "." .. tostring(build),
  }
end

-- Adds the record, deduplicated by (questID, text hash). Returns true when it was new. A known
-- text is completed with the fields added since it was captured (rewards came after the first
-- captures) and takes the fresh rewards.
function Capture.Record(rec)
  local quests = store()
  local list = quests[rec.questID] or {}
  quests[rec.questID] = list
  local hash = Capture.Hash(rec.text)
  local now = time()
  for _, existing in ipairs(list) do
    if existing.hash == hash then
      existing.seen = (existing.seen or 1) + 1
      existing.lastSeen = now
      for key, value in pairs(rec) do
        if existing[key] == nil then
          existing[key] = value
        end
      end
      if Capture.HasRewards(rec.rewards) then
        existing.rewards = rec.rewards
      end
      return false
    end
  end
  rec.hash, rec.firstSeen, rec.lastSeen, rec.seen = hash, now, now, 1
  list[#list + 1] = rec
  return true
end

-- Most recently seen capture for a quest, or nil.
function Capture.Latest(questID)
  local quests = ForeverSpeechCaptures and ForeverSpeechCaptures.quests
  local list = quests and quests[tonumber(questID) or -1]
  if not list then
    return nil
  end
  local best
  for _, rec in ipairs(list) do
    if not best or (rec.lastSeen or 0) >= (best.lastSeen or 0) then
      best = rec
    end
  end
  return best
end

function Capture.Count()
  local quests, records = 0, 0
  for _, list in pairs(ForeverSpeechCaptures.quests or {}) do
    quests = quests + 1
    records = records + #list
  end
  return quests, records
end

-- Captured quests, most recently seen first: { {questID, title, lastSeen}, ... }
function Capture.Recent(limit)
  local out = {}
  for questID in pairs(ForeverSpeechCaptures.quests or {}) do
    local rec = Capture.Latest(questID)
    out[#out + 1] = { questID = questID, title = rec.title, lastSeen = rec.lastSeen or 0 }
  end
  table.sort(out, function(a, b)
    if a.lastSeen ~= b.lastSeen then
      return a.lastSeen > b.lastSeen
    end
    return a.questID > b.questID
  end)
  while limit and #out > limit do
    out[#out] = nil
  end
  return out
end

-- Turn-in texts, ForeverSpeechCaptures.completions[questID] = { record, ... }, deduplicated like the
-- detail texts. The progress text (QUEST_PROGRESS) is not captured: it is never read (2026-10-06).
function Capture.SnapshotCompletion()
  local questID = safe(GetQuestID)
  local text = safe(GetRewardText)
  if not questID or questID == 0 or not text or text == "" then
    return nil
  end
  local unitType, npcID = Capture.ParseGUID(safe(UnitGUID, "npc"))
  local version, build = GetBuildInfo()
  return {
    questID = questID,
    title = safe(GetTitleText),
    text = text,
    enderType = unitType,
    npcID = unitType == "Creature" and npcID or nil,
    enderID = npcID,
    enderName = safe(UnitName, "npc"),
    npcSex = safe(UnitSex, "npc"),
    zone = safe(GetZoneText),
    locale = safe(GetLocale),
    playerSex = safe(UnitSex, "player"),
    playerName = safe(UnitName, "player"),
    playerClass = safe(UnitClass, "player"),
    playerRace = safe(UnitRace, "player"),
    client = tostring(version) .. "." .. tostring(build),
  }
end

function Capture.RecordCompletion(rec)
  local db = ForeverSpeechCaptures
  db.completions = db.completions or {}
  local list = db.completions[rec.questID] or {}
  db.completions[rec.questID] = list
  local hash = Capture.Hash(rec.text)
  local now = time()
  for _, existing in ipairs(list) do
    if existing.hash == hash then
      existing.seen = (existing.seen or 1) + 1
      existing.lastSeen = now
      return false
    end
  end
  rec.hash, rec.firstSeen, rec.lastSeen, rec.seen = hash, now, now, 1
  list[#list + 1] = rec
  return true
end

function Capture.LatestCompletion(questID)
  local completions = ForeverSpeechCaptures and ForeverSpeechCaptures.completions
  local list = completions and completions[tonumber(questID) or -1]
  local best
  for _, rec in ipairs(list or {}) do
    if not best or (rec.lastSeen or 0) >= (best.lastSeen or 0) then
      best = rec
    end
  end
  return best
end

-- NPC dialogue texts (spike S11, 2026-10-10): what the gossip window says when one talks to an NPC,
-- ForeverSpeechCaptures.gossip["<unit type>:<id>"] = { record, ... }, deduplicated by text hash. Unverified on
-- Forever: C_GossipInfo.GetText (Retail) is tried, then GetGossipText (Classic); `api` records which one answered,
-- so that the spike can tell. The options (lines one clicks) are kept by name, for the pipeline to match them
-- with the database's menus.
local function gossipText()
  local G = C_GossipInfo
  local text = G and safe(G.GetText)
  if type(text) == "string" and text ~= "" then
    return text, "C_GossipInfo.GetText"
  end
  text = safe(GetGossipText)
  if type(text) == "string" and text ~= "" then
    return text, "GetGossipText"
  end
  return nil, (G and "C_GossipInfo" or "") .. (GetGossipText and "+GetGossipText" or "")
end

function Capture.SnapshotGossip()
  local text, api = gossipText()
  local unitType, id = Capture.ParseGUID(safe(UnitGUID, "npc"))
  H.Trace("capture: GOSSIP_SHOW unit=%s:%s api=%s textLen=%s", unitType, id, api, text and #text)
  if not text or not id then
    return nil
  end
  local options = {}
  local list = C_GossipInfo and safe(C_GossipInfo.GetOptions)
  for _, option in ipairs(type(list) == "table" and list or {}) do
    options[#options + 1] = option.name
  end
  local version, build = GetBuildInfo()
  return {
    key = tostring(unitType) .. ":" .. id,
    unitType = unitType,
    npcID = unitType == "Creature" and id or nil,
    name = safe(UnitName, "npc"),
    text = text,
    api = api,
    options = options,
    zone = safe(GetZoneText),
    locale = safe(GetLocale),
    playerSex = safe(UnitSex, "player"),
    playerName = safe(UnitName, "player"),
    playerClass = safe(UnitClass, "player"),
    playerRace = safe(UnitRace, "player"),
    client = tostring(version) .. "." .. tostring(build),
  }
end

function Capture.RecordGossip(rec)
  local db = ForeverSpeechCaptures
  db.gossip = db.gossip or {}
  local list = db.gossip[rec.key] or {}
  db.gossip[rec.key] = list
  local hash = Capture.Hash(rec.text)
  local now = time()
  for _, existing in ipairs(list) do
    if existing.hash == hash then
      existing.seen = (existing.seen or 1) + 1
      existing.lastSeen = now
      return false
    end
  end
  rec.key = nil
  rec.hash, rec.firstSeen, rec.lastSeen, rec.seen = hash, now, now, 1
  list[#list + 1] = rec
  return true
end

H.TryRegisterEvent("GOSSIP_SHOW", function()
  local rec = Capture.SnapshotGossip()
  if rec and Capture.RecordGossip(rec) then
    H.Debug("captured a dialogue of %s (%s)", tostring(rec.name), rec.api)
  end
end)

H.RegisterCommand("gossip", function(arg)
  arg = (arg or ""):lower()
  if arg == "on" or arg == "off" then
    ForeverSpeechDB.readGossip = arg == "on"
    if H.GameVoices then
      H.GameVoices.Update()
    end
  end
  local npcs, pages = 0, 0
  if H.Dialogues then
    npcs, pages = H.Dialogues.Counts()
  end
  H.Print("NPC dialogues read in their voice: %s (index: %d NPC(s), %d page(s) with audio)",
    ForeverSpeechDB.readGossip and "on" or "off", npcs, pages)
  local count, texts = 0, 0
  for key, list in pairs(ForeverSpeechCaptures.gossip or {}) do
    count = count + 1
    texts = texts + #list
    local last = list[#list]
    if count <= 5 then
      H.Print("  %s %s (%s): %s", key, H.Escape(last.name or "?"), last.api, H.Escape(last.text:sub(1, 60)))
    end
  end
  H.Print("%d NPC(s), %d dialogue text(s) captured (S11). Written to disk at /reload or logout.", count, texts)
end, "gossip [on|off] - NPC dialogues read in their voice, and the captured ones (spike S11)")

-- Quest opened last in this session (also set for an already captured text).
Capture.lastQuestID = nil
-- Quest whose reward panel opened last: its end is read once turned in (core/autoplay.lua).
Capture.lastCompleteQuestID = nil

H.RegisterEvent("QUEST_DETAIL", function(_, startItemID)
  local rec = Capture.Snapshot(startItemID)
  if not rec then
    return
  end
  Capture.lastQuestID = rec.questID
  if Capture.Record(rec) then
    H.Debug("captured quest %d (%s)", rec.questID, tostring(rec.giverName))
  end
end)

H.TryRegisterEvent("QUEST_COMPLETE", function()
  local questID = safe(GetQuestID)
  Capture.lastCompleteQuestID = (questID and questID ~= 0) and questID or nil
  local rec = Capture.SnapshotCompletion()
  H.Trace("capture: QUEST_COMPLETE quest=%s textLen=%s", questID, rec and #rec.text)
  if rec and Capture.RecordCompletion(rec) then
    H.Debug("captured the turn-in text of quest %d (%s)", rec.questID, tostring(rec.enderName))
  end
end)

H.RegisterCommand("captures", function()
  local quests, records = Capture.Count()
  H.Print("%d quest(s) captured, %d text(s). Written to disk at /reload or logout.", quests, records)
  for _, q in ipairs(Capture.Recent(5)) do
    H.Print("  %d - %s", q.questID, H.Escape(q.title or "?"))
  end
end, "captures - captured quests (latest 5 with their ID)")
