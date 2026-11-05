-- ForeverSpeech: mutes the game's own NPC voice lines, greetings, farewells and "pissed" lines, with the NPCs that
-- have a quest for the player only (option muteGameVoices, on by default; asked 2026-10-10: they get in the way now
-- that quests are read, the other NPCs keep their voices). Only while the audio is on. The file IDs come from
-- data/game_voices.lua (generated, pipeline/game_voices.py): Classic voices only, the NPCs added by Forever keep
-- theirs (spike S10). MuteSoundFile / UnmuteSoundFile: verified on Forever 2026-10-10 (S10).
-- The greeting starts with the click, before the NPC's window tells what it offers: the voices are muted as soon as
-- the mouse is over (or the interact key points at) an NPC that has a quest for the player according to the index
-- (giver of a quest neither done nor in the log, ender of a quest of the log ready to turn in); while its window is
-- open, the window's own quest list decides; after it closes, FAREWELL_HOLD seconds more for the farewell.
-- Since 2026-10-21 an NPC whose dialogue the addon reads in its voice (core/dialogues.lua: a page with audio, setting
-- readGossip) counts as one with a quest: its greeting is muted too.
local H = ForeverSpeech

local GameVoices = {}
H.GameVoices = GameVoices

local FAREWELL_HOLD = 2
local POLL_INTERVAL = 0.2
local HOVER_UNITS = { "mouseover", "softinteract" } -- "softinteract": Retail unit token, unverified on Forever

local muted = false
local talking         -- while an NPC window is open: true if it offers or awaits a quest, else false; nil otherwise
local holdUntil = 0   -- GetTime() until which the farewell stays muted
local hoverKey, hoverHas -- cache of the hover check: GUIDs under the cursor / interact key, and the answer
local givers, enders  -- npcID -> { questID, ... } from the index, built on first use
-- NPCs whose window showed no quest to take: the index knows no level, class or prerequisite, so it says yes for them
-- (a class trainer's quests of the other classes). Forgotten when the quest log changes or the player levels up.
local nothingToGive = {}
local warned = false

function GameVoices.Available()
  local data = ForeverSpeechGameVoices
  return type(MuteSoundFile) == "function" and type(UnmuteSoundFile) == "function"
    and type(data) == "table" and type(data.files) == "table"
end

function GameVoices.IsMuted()
  return muted
end

-- A secret value (an NPC's GUID in instances and combat, Forever) reads as nil: the NPC is unknown (H.Safe).
local call = H.Safe

local function buildMaps()
  givers, enders = {}, {}
  local quests = ForeverSpeechIndex and ForeverSpeechIndex.quests or {}
  for questID, quest in pairs(quests) do
    for field, map in pairs({ giver = givers, ender = enders }) do
      local npc = quest[field]
      if npc then
        map[npc] = map[npc] or {}
        table.insert(map[npc], questID)
      end
    end
  end
end

local function inLog(questID)
  return C_QuestLog and call(C_QuestLog.GetLogIndexForQuestID, questID) ~= nil
end

-- Done before: C_QuestLog.IsQuestFlaggedCompleted (unverified on Forever; without it, never done).
local function done(questID)
  return C_QuestLog and call(C_QuestLog.IsQuestFlaggedCompleted, questID) == true
end

-- Ready to turn in: C_QuestLog.IsComplete, else IsQuestComplete (both unverified on Forever; without them, in the log
-- is enough).
local function ready(questID)
  local complete = C_QuestLog and call(C_QuestLog.IsComplete, questID)
  if complete == nil then
    complete = call(IsQuestComplete, questID)
  end
  return complete ~= false and complete ~= 0
end

-- An NPC whose dialogue the addon reads in its voice (core/dialogues.lua, 2026-10-21): its greeting is muted too.
local function hasDialogue(npcID)
  return npcID ~= nil and H.Dialogues ~= nil and H.Dialogues.HasAudio(npcID)
end

-- True if the NPC has a quest for the player according to the index: a quest to turn in, or one to take.
function GameVoices.HasQuestFor(npcID)
  if not givers then
    buildMaps()
  end
  for _, questID in ipairs(enders[npcID] or {}) do
    if inLog(questID) and ready(questID) then
      return true
    end
  end
  if nothingToGive[npcID] then
    return false
  end
  for _, questID in ipairs(givers[npcID] or {}) do
    if not inLog(questID) and not done(questID) then
      return true
    end
  end
  return false
end

local function npcOf(unit)
  local unitType, npcID = H.Capture.ParseGUID(call(UnitGUID, unit))
  return unitType == "Creature" and npcID or nil, unitType
end

-- The NPC under the cursor or the interact key has a quest for the player (cached while they stay the same).
local function hovering()
  local guids = {}
  for i, unit in ipairs(HOVER_UNITS) do
    guids[i] = call(UnitGUID, unit) or ""
  end
  local key = table.concat(guids, "|")
  if key ~= hoverKey then
    hoverKey, hoverHas = key, false
    for _, unit in ipairs(HOVER_UNITS) do
      local npcID = npcOf(unit)
      if npcID and (GameVoices.HasQuestFor(npcID) or hasDialogue(npcID)) then
        hoverHas = npcID
        break
      end
    end
  end
  return hoverHas
end

local function wanted()
  if not (ForeverSpeechDB.muteGameVoices and H.IsEnabled()) then
    return false, "off"
  end
  if talking ~= nil then
    return talking, "window"
  end
  if GetTime() < holdUntil then
    return true, "farewell"
  end
  local npcID = hovering()
  if npcID then
    return true, "hover npc=" .. npcID
  end
  return false, "no quest"
end

-- Mutes or unmutes the voice lines to match the settings and the NPC at hand. Returns how many files changed.
function GameVoices.Update()
  if not GameVoices.Available() then
    if not warned then
      warned = true
      H.Trace("game voices: unavailable MuteSoundFile=%s data=%s", type(MuteSoundFile), type(ForeverSpeechGameVoices))
    end
    return 0
  end
  local want, why = wanted()
  want = want and true or false
  if want == muted then
    return 0
  end
  local fn, files, changed = want and MuteSoundFile or UnmuteSoundFile, ForeverSpeechGameVoices.files, 0
  for _, fileID in ipairs(files) do
    if pcall(fn, fileID) then
      changed = changed + 1
    end
  end
  muted = want
  H.Trace("game voices: %s %s of %s files (%s)", want and "muted" or "unmuted", changed, #files, why)
  return changed
end

-- What an open NPC window offers. Quest pages (detail, progress, reward) are quests by definition; the gossip and
-- quest greeting pages list them (C_GossipInfo, GetNumAvailableQuests...: unverified on Forever, else the index).
local function learn(available)
  local npcID = npcOf("npc")
  if npcID then
    nothingToGive[npcID] = available == 0 or nil
    hoverKey = nil
  end
end

local function gossipHasQuest()
  local G = C_GossipInfo
  local available, active = G and call(G.GetAvailableQuests), G and call(G.GetActiveQuests)
  if type(available) == "table" and type(active) == "table" then
    learn(#available)
    if #available > 0 then
      return true
    end
    for _, quest in ipairs(active) do
      if quest.isComplete ~= false then
        return true
      end
    end
    return false
  end
  local npcID = npcOf("npc")
  return npcID ~= nil and GameVoices.HasQuestFor(npcID)
end

local function greetingHasQuest()
  local available = call(GetNumAvailableQuests) or 0
  learn(available)
  if available > 0 then
    return true
  end
  for i = 1, call(GetNumActiveQuests) or 0 do
    local _, isComplete = call(GetActiveTitle, i)
    if isComplete ~= false then
      return true
    end
  end
  return false
end

local function onWindow(event)
  if event == "GOSSIP_SHOW" then
    talking = gossipHasQuest() or hasDialogue((npcOf("npc")))
  elseif event == "QUEST_GREETING" then
    talking = greetingHasQuest()
  else
    talking = true
  end
  GameVoices.Update()
end

local function onWindowClosed()
  if talking then
    holdUntil = GetTime() + FAREWELL_HOLD
  end
  talking = nil
  GameVoices.Update()
end

for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
  H.TryRegisterEvent(event, onWindow)
end
for _, event in ipairs({ "GOSSIP_CLOSED", "QUEST_FINISHED" }) do
  H.TryRegisterEvent(event, onWindowClosed)
end

-- The hover check reacts at once to a new unit under the cursor or the interact key, and polls for the cursor
-- leaving (no event for that). The quest log changing invalidates the cached answer.
local function onHover()
  hoverKey = nil
  GameVoices.Update()
end
for _, event in ipairs({ "UPDATE_MOUSEOVER_UNIT", "PLAYER_SOFT_INTERACT_CHANGED" }) do
  H.TryRegisterEvent(event, onHover)
end
H.TryRegisterEvent("QUEST_LOG_UPDATE", function()
  hoverKey = nil
end)
for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }) do
  H.TryRegisterEvent(event, function()
    nothingToGive, hoverKey = {}, nil
  end)
end

local pollFrame = CreateFrame("Frame")
local sincePoll = 0
pollFrame:SetScript("OnUpdate", function(_, dt)
  sincePoll = sincePoll + dt
  if sincePoll >= POLL_INTERVAL then
    sincePoll = 0
    if muted or (ForeverSpeechDB and ForeverSpeechDB.muteGameVoices) then
      GameVoices.Update()
    end
  end
end)

H.OnInit(GameVoices.Update)
H.OnEnabledChange(GameVoices.Update)

-- Diagnostic (spike S10, 2026-10-10: the voices were still heard after "muted 1035 of 1035 files"). A greeting of the
-- commonest NPC voice (HumanMaleStandard, 189 NPCs) is played as a file then as its sound kit, three times: as it
-- is now, muted by hand, unmuted. Each step is numbered in the chat (the player says what is heard) and the
-- client's answers go to the trace. The setting is applied again at the end.
local TEST_FILE, TEST_KIT, TEST_STEP = 552196, 5974, 3

local function setAll(fn)
  for _, fileID in ipairs(ForeverSpeechGameVoices.files) do
    pcall(fn, fileID)
  end
end

local function probe(step, what, state)
  local ok, willPlay, handle
  if what == "file" then
    ok, willPlay, handle = pcall(PlaySoundFile, TEST_FILE, "Master")
  else
    ok, willPlay, handle = pcall(PlaySound, TEST_KIT, "Master")
  end
  H.Print("S10 step %d/6: %s, %s - heard?", step, what == "file" and "greeting file " .. TEST_FILE
    or "greeting sound kit " .. TEST_KIT, state)
  C_Timer.After(0.3, function()
    local playing = handle and C_Sound and C_Sound.IsPlaying and select(2, pcall(C_Sound.IsPlaying, handle))
    H.Trace("S10 step %s: %s %s ok=%s willPlay=%s handle=%s playing=%s", step, what, state, ok, willPlay, handle,
      playing)
  end)
end

function GameVoices.Test()
  if not GameVoices.Available() then
    H.Print("the game's NPC voices cannot be muted on this client (MuteSoundFile or data/game_voices.lua missing)")
    return
  end
  H.Trace("S10 test: muted=%s files=%s", muted, #ForeverSpeechGameVoices.files)
  local steps = {
    function() probe(1, "file", muted and "muted now" or "voices on now") end,
    function() probe(2, "kit", muted and "muted now" or "voices on now") end,
    function() setAll(MuteSoundFile) probe(3, "file", "muted again now") end,
    function() probe(4, "kit", "muted again now") end,
    function() setAll(UnmuteSoundFile) probe(5, "file", "unmuted") end,
    function() probe(6, "kit", "unmuted") end,
    function()
      muted = false
      GameVoices.Update()
      H.Print("S10 done: setting applied again (%s). Talk to a human guard: does he greet you? Then /reload.",
        muted and "muted" or "voices on")
    end,
  }
  for i, step in ipairs(steps) do
    C_Timer.After((i - 1) * TEST_STEP, step)
  end
end

H.RegisterCommand("npcvoices", function(arg)
  arg = arg:lower()
  if arg == "test" then
    GameVoices.Test()
    return
  end
  if arg == "on" or arg == "off" then
    ForeverSpeechDB.muteGameVoices = arg == "off"
    GameVoices.Update()
  end
  if not GameVoices.Available() then
    H.Print("the game's NPC voices cannot be muted on this client (MuteSoundFile or data/game_voices.lua missing)")
    return
  end
  H.Print("the game's NPC voices (greetings, farewells): %s", ForeverSpeechDB.muteGameVoices
    and "muted with the NPCs that have a quest for you" or "on")
end, "npcvoices on|off|test - the game's own NPC greetings and farewells (off: muted with quest NPCs; test: S10)")
