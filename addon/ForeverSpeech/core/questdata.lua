-- ForeverSpeech: what the UI and TTS know about a quest. Source order: capture at QUEST_DETAIL
-- (exact client text, D1), then the quest log for quests accepted before the addon saw them.
-- Quest log text and reward functions are not in the client API documentation: every call is
-- probed and wrapped (verified later in-game, see docs/ingame-tests.md T3).
local H = ForeverSpeech

local QuestData = {}
H.QuestData = QuestData

-- A secret value (instances and combat, Forever) reads as nil (H.Safe, 2026-10-21).
local call = H.Safe

local function logIndex(questID)
  return C_QuestLog and call(C_QuestLog.GetLogIndexForQuestID, questID)
end

-- Description and objectives from the quest log. Retail takes a log index; Classic reads the
-- selected quest, so the selection is set then restored when the index form returns nothing.
local function logText(questID)
  local index = logIndex(questID)
  if not index then
    return nil
  end
  local description, objectives = call(GetQuestLogQuestText, index)
  H.Trace("questdata: GetQuestLogQuestText(%s) -> descLen=%s", index, description and #description)
  if (not description or description == "") and C_QuestLog and C_QuestLog.SetSelectedQuest then
    local previous = call(C_QuestLog.GetSelectedQuest)
    call(C_QuestLog.SetSelectedQuest, questID)
    description, objectives = call(GetQuestLogQuestText)
    H.Trace("questdata: GetQuestLogQuestText() after select -> descLen=%s", description and #description)
    if previous and previous ~= 0 and previous ~= questID then
      call(C_QuestLog.SetSelectedQuest, previous)
    end
  end
  if description == "" then
    description = nil
  end
  return description, objectives
end

local function logItems(countFn, infoFn, questID)
  local items = {}
  for i = 1, call(countFn, questID) or 0 do
    local name, texture, count, quality, _, itemID = call(infoFn, i, questID)
    if texture then
      items[#items + 1] = { name = name, texture = texture, count = count, quality = quality, itemID = itemID }
    end
  end
  return items
end

local function logRewards(questID)
  return {
    items = logItems(GetNumQuestLogRewards, GetQuestLogRewardInfo, questID),
    choices = logItems(GetNumQuestLogChoices, GetQuestLogChoiceInfo, questID),
    money = call(GetQuestLogRewardMoney, questID),
    xp = call(GetQuestLogRewardXP, questID),
  }
end

-- Speaker of a part's audio when no NPC says it: the narrator, Elise (contract v4), as its ID and name, or nil.
local function narrator(questID, kind)
  local entry = H.Index.Lookup(questID, kind)
  local npc = entry and entry.npc and H.Index.NPC(entry.npc)
  if npc then
    return entry.npc, npc.name
  end
end

-- Completes npcID, displayID and giverName from the generated index (contract v2).
local function withGiver(data)
  data.npcID = data.npcID or H.Index.Giver(data.questID)
  local npc = data.npcID and H.Index.NPC(data.npcID)
  if npc then
    data.displayID = npc.display
    data.giverName = data.giverName or npc.name
  elseif not data.npcID then
    local name
    data.speakerID, name = narrator(data.questID, "detail")
    data.giverName = data.giverName or name
  end
  return data
end

-- The NPC of the turn-in (part "complete"): ender from the turn-in capture, else from the index.
local function withEnder(data)
  local capture = H.Capture.LatestCompletion(data.questID)
  data.npcID = (capture and capture.npcID) or H.Index.Ender(data.questID)
  data.giverName = capture and capture.enderName or nil
  data.displayID, data.speakerID = nil, nil
  local npc = data.npcID and H.Index.NPC(data.npcID)
  if npc then
    data.displayID = npc.display
    data.giverName = data.giverName or npc.name
  elseif not data.npcID then
    local name
    data.speakerID, name = narrator(data.questID, "complete")
    data.giverName = data.giverName or name
  end
  return data
end

-- { questID, title, description, objectives, npcID, displayID, speakerID, giverName, giverType, rewards, source }
-- speakerID: the narrator when no NPC says the part (its portrait in the player window).
-- part "complete": the same quest, with the NPC of the turn-in as speaker (npcID, displayID, giverName).
function QuestData.Get(questID, part)
  questID = tonumber(questID)
  if not questID then
    return nil
  end
  if part == "complete" then
    local data = QuestData.Get(questID)
    if not data then
      local capture = H.Capture.LatestCompletion(questID)
      if not capture then
        return nil
      end
      data = { questID = questID, title = capture.title, rewards = {}, source = "capture" }
    end
    return withEnder(data)
  end
  local capture = H.Capture.Latest(questID)
  if capture then
    return withGiver({
      questID = questID,
      title = capture.title,
      description = capture.text,
      objectives = capture.objectives,
      npcID = capture.npcID,
      giverName = capture.giverName,
      giverType = capture.giverType,
      -- captures made before rewards were read have none: the quest log may know them
      rewards = H.Capture.HasRewards(capture.rewards) and capture.rewards or logRewards(questID),
      source = "capture",
    })
  end
  local title = C_QuestLog and call(C_QuestLog.GetTitleForQuestID, questID)
  local description, objectives = logText(questID)
  if not title and not description then
    return nil
  end
  local rewards = logRewards(questID)
  H.Trace("questdata: quest %s from questlog title=%s descLen=%s items=%s choices=%s money=%s xp=%s", questID,
    title, description and #description, #rewards.items, #rewards.choices, rewards.money, rewards.xp)
  return withGiver({
    questID = questID,
    title = title,
    description = description,
    objectives = objectives,
    rewards = rewards,
    source = "questlog",
  })
end

-- Share of an objective done, 0 to 1, when it has a counter (2026-10-10, progress bars): numFulfilled / numRequired
-- when numRequired is at least 2 (Retail fields, unverified on Forever), else GetQuestProgressBarPercent for a
-- "progressbar" objective (unverified), else the "3/12" (at least 2 required) or "45 %" of its text. nil without a
-- counter ("Parler à ...", "Atteindre une compétence de 20..."): such an objective has no completion to show.
local function share(objective, questID)
  local have, need = tonumber(objective.numFulfilled), tonumber(objective.numRequired)
  if not (have and need and need > 1) then
    if objective.type == "progressbar" then
      local percent = tonumber(call(GetQuestProgressBarPercent, questID))
      if percent then
        return math.max(0, math.min(1, percent / 100))
      end
    end
    local a, b = objective.text:match("(%d+)%s*/%s*(%d+)")
    if tonumber(b) and tonumber(b) > 1 then
      have, need = tonumber(a), tonumber(b)
    else
      local percent = tonumber(objective.text:match("(%d+)%s*%%"))
      return percent and math.max(0, math.min(1, percent / 100)) or nil
    end
  end
  if objective.finished then
    return 1
  end
  return math.max(0, math.min(1, have / need))
end

-- Live objective lines of a quest in the player's log, read at each call (S4: GetQuestObjectives exists on
-- Forever): { {text = "Masque rouge : 3/12", finished = false, share = 0.25, type, have, need}, ... }, or nil.
-- share is nil for an objective without a counter; type, have and need are the client's raw fields (diagnostics).
function QuestData.Progress(questID)
  if not (C_QuestLog and logIndex(questID)) then
    return nil
  end
  local objectives = call(C_QuestLog.GetQuestObjectives, questID)
  if type(objectives) ~= "table" then
    return nil
  end
  local lines = {}
  for _, objective in ipairs(objectives) do
    if type(objective) == "table" and objective.text and objective.text ~= "" then
      lines[#lines + 1] = { text = objective.text, finished = objective.finished and true or false,
        share = share(objective, questID), type = objective.type, have = objective.numFulfilled,
        need = objective.numRequired }
    end
  end
  return #lines > 0 and lines or nil
end

-- The quest the player follows: the focused (super-tracked) quest, else the first quest of the objective
-- tracker. Second result: where it came from, "focus" | "tracker". Retail APIs, unverified on Forever
-- (2026-10-10): C_SuperTrack.GetSuperTrackedQuestID, C_QuestLog.GetQuestIDForQuestWatchIndex. nil if none.
-- FlareUI's tracker (2026-11-05) sorts itself: its first quest shown, not the watch list's first.
function QuestData.Tracked()
  local focused = C_SuperTrack and call(C_SuperTrack.GetSuperTrackedQuestID)
  if type(focused) == "number" and focused > 0 then
    return focused, "focus"
  end
  local shown = H.TrackerButtons and H.TrackerButtons.FirstShown()
  if shown then
    return shown, "tracker"
  end
  local first = C_QuestLog and call(C_QuestLog.GetQuestIDForQuestWatchIndex, 1)
  if type(first) == "number" and first > 0 then
    return first, "tracker"
  end
  return nil
end

-- Level of a quest (2026-10-14, the player window's level badge): the quest log's (C_QuestLog.GetInfo(logIndex).level,
-- Retail field, unverified on Forever), else the generated index's (contract v7). Second result: "questlog" |
-- "index". nil when neither knows it.
function QuestData.Level(questID)
  local index = logIndex(questID)
  local info = index and call(C_QuestLog.GetInfo, index)
  local level = type(info) == "table" and tonumber(info.level)
  if level and level > 0 then
    return level, "questlog"
  end
  level = H.Index.QuestLevel(questID)
  if level and level > 0 then
    return level, "index"
  end
  return nil
end

-- The client's QuestDifficultyColors (Classic FrameXML), for a client without that table.
local DIFFICULTY_COLORS = {
  impossible = { r = 1.00, g = 0.10, b = 0.10 },
  verydifficult = { r = 1.00, g = 0.50, b = 0.25 },
  difficult = { r = 1.00, g = 0.82, b = 0.00 },
  standard = { r = 0.25, g = 0.75, b = 0.25 },
  trivial = { r = 0.50, g = 0.50, b = 0.50 },
}
local DIFFICULTY_KEYS = { "impossible", "verydifficult", "difficult", "standard", "trivial" }

-- Gray level of the Classic client: a quest at or under it is gray (little or no experience).
local function grayLevel(playerLevel)
  if playerLevel <= 5 then
    return 0
  elseif playerLevel <= 39 then
    return playerLevel - math.floor(playerLevel / 10) - 5
  elseif playerLevel <= 59 then
    return playerLevel - math.floor(playerLevel / 5) - 1
  end
  return playerLevel - 9
end

-- Difficulty by the Classic quest log's rules (GetQuestDifficultyColor of the Classic FrameXML).
local function difficultyKey(level, playerLevel)
  local diff = level - playerLevel
  if diff >= 5 then
    return "impossible"
  elseif diff >= 3 then
    return "verydifficult"
  elseif diff >= -2 then
    return "difficult"
  elseif level > grayLevel(playerLevel) then
    return "standard"
  end
  return "trivial"
end

local function sameColor(a, b)
  return math.abs((a.r or 0) - (b.r or 0)) < 0.01 and math.abs((a.g or 0) - (b.g or 0)) < 0.01
    and math.abs((a.b or 0) - (b.b or 0)) < 0.01
end

-- Difficulty of a quest level for the player (2026-10-14), as the quest log colors it: its key ("impossible" red,
-- "verydifficult" orange, "difficult" yellow, "standard" green, "trivial" gray) and its color {r, g, b}. The client's
-- own GetQuestDifficultyColor when it has one and playerLevel is the current level (unverified on Forever); else the
-- Classic rules. playerLevel: the player's level (default UnitLevel; PLAYER_LEVEL_UP gives the new one before
-- UnitLevel does). The key is nil when the client's color is none of its table's. nil without both levels.
function QuestData.Difficulty(level, playerLevel)
  level = tonumber(level)
  local current = tonumber(call(UnitLevel, "player"))
  playerLevel = tonumber(playerLevel) or current
  if not (level and level > 0 and playerLevel and playerLevel > 0) then
    return nil
  end
  local colors = type(QuestDifficultyColors) == "table" and QuestDifficultyColors or DIFFICULTY_COLORS
  if playerLevel == current then
    local color = call(GetQuestDifficultyColor, level)
    if type(color) == "table" and tonumber(color.r) then
      for _, key in ipairs(DIFFICULTY_KEYS) do
        local known = colors[key]
        if type(known) == "table" and (known == color or sameColor(known, color)) then
          return key, color
        end
      end
      return nil, color
    end
  end
  local key = difficultyKey(level, playerLevel)
  local color = colors[key]
  return key, type(color) == "table" and color or DIFFICULTY_COLORS[key]
end

-- Title only (cheap: no quest log selection), for lists.
function QuestData.Title(questID)
  local capture = H.Capture.Latest(questID)
  if capture and capture.title then
    return capture.title
  end
  return C_QuestLog and call(C_QuestLog.GetTitleForQuestID, questID) or nil
end

-- Text to read aloud (D6): the acceptance text, i.e. the description followed by the objectives
-- announced as "Objectif : ...". nil when there is no description.
function QuestData.ComposeSpeech(description, objectives)
  if not description or description == "" then
    return nil
  end
  if objectives and objectives ~= "" then
    return description .. "\n\n" .. H.L.SPEECH_OBJECTIVE .. objectives
  end
  return description
end

-- part "complete": the turn-in text captured at QUEST_COMPLETE (the quest has left the log by then).
function QuestData.Text(questID, part)
  if part == "complete" then
    local capture = H.Capture.LatestCompletion(questID)
    return capture and capture.text or nil
  end
  local data = QuestData.Get(questID)
  return data and QuestData.ComposeSpeech(data.description, data.objectives) or nil
end


-- The group's progress on a quest (2026-11-05): the game's own lines, as Retail's quest tooltip shows them
-- (C_TooltipInfo.GetQuestPartyProgress(questID, omitTitle, ignoreActivePlayer), read the same way by FlareUI): each
-- member on the quest, then their objectives, in the game's colours. A member's line is known by its type
-- (Enum.TooltipDataLineType.QuestPlayer; member is nil when the client has no such type); an objective is done when the
-- game says so (completed) or greys it. Only in a group; nil without the API or without a line.
-- Unverified on Forever: T66 (H40). { { text, r, g, b, member, done }, ... }
function QuestData.PartyProgress(questID)
  local api = C_TooltipInfo and C_TooltipInfo.GetQuestPartyProgress
  if not questID or (tonumber(H.Safe(_G.GetNumSubgroupMembers)) or 0) == 0 or type(api) ~= "function" then
    return nil
  end
  local data = H.Safe(api, questID, true, true)
  if type(data) ~= "table" or type(data.lines) ~= "table" then
    return nil
  end
  local types = Enum and Enum.TooltipDataLineType
  local playerType = type(types) == "table" and types.QuestPlayer or nil
  local lines = {}
  for _, line in ipairs(data.lines) do
    local text = type(line) == "table" and H.NotSecret(line.leftText)
    if type(text) == "string" and text ~= "" then
      local r, g, b = 1, 1, 1
      if type(line.leftColor) == "table" and line.leftColor.GetRGB then
        r, g, b = line.leftColor:GetRGB()
      end
      local member
      if playerType ~= nil then
        member = line.type == playerType
      end
      local done = member ~= true and (line.completed == true or (r == g and g == b and r < 0.9))
      lines[#lines + 1] = { text = text, r = r, g = g, b = b, member = member, done = done }
    end
  end
  return #lines > 0 and lines or nil
end
