-- ForeverSpeech: audio playback with a play list. One sound at a time, no pause (D4).
-- The list keeps its order and holds each quest once. Reading a quest (PlayQuest: play buttons,
-- "Accepter et lire") always puts it in the list, at the end or at its place if already there;
-- if the list is playing it goes on, else this quest starts now. Between two quests the list waits
-- a few seconds (setting "gap"). Stop halts the list (the items not played yet stay), Next skips
-- to the first item not played yet. PlayNow (double-click in the list) jumps to an item without
-- moving it; Clear drops the items not played yet, Reset empties the list.
-- Each item is one part of a quest: "detail" (acceptance text, said by the giver) or "complete"
-- (turn-in text, said by the ender; decided 2026-10-06), so a quest may be in the list twice. An item may also be a
-- line of Elise (2026-10-11): a zone introduction (core/zones.lua) or a level-up line (core/levels.lua),
-- { key = "z1429" | "l12", line = "zone" | "level", lineID = mapID | level }. Since 2026-10-21 also a book page
-- (core/books.lua, read by Elise) or an NPC's dialogue page (core/dialogues.lua, its voice): line = "book" | "gossip",
-- lineID = an ID of the session. An item started by the addon itself (zone, level, companion, auto reading) is
-- { auto = true }: none starts in a battleground or an arena (core/silence.lua), where entering drops them.
-- Verified on Forever 1.60.1 (docs/spikes): PlaySoundFile returns (true, handle) or nothing for a
-- missing file; SOUNDKIT_FINISHED never fires for PlaySoundFile, so the end is detected by polling
-- C_Sound.IsPlaying; C_VoiceChat.SpeakText(voiceID, text, rate, volume, overlap) is available.
local H = ForeverSpeech

local Player = {}
H.Player = Player

Player.TEST_FILE = "Interface\\AddOns\\ForeverSpeech\\audio\\test\\test_2.ogg"

local POLL_INTERVAL = 0.25
local TTS_RATE, TTS_VOLUME = 0, 100
local TTS_VOICE_PREFERENCE = { "thomas [fr-fr]", "jacques [fr-fr]", "[fr-fr]", "[fr-" }

local current   -- { key, kind = "file"|"tts", handle, questID, part, line, lineID, source, dur }
-- the play list in order, each key once: { key, questID, part, played }, { key = "z1429", line = "zone",
-- lineID = 1429 } or { key = "test", test = true }
local list = {}

Player.PARTS = { detail = true, complete = true }

-- List key of a quest part: "q783" (acceptance, as before the turn-in part existed), "q783:complete".
local function keyOf(questID, part)
  if part == "complete" then
    return "q" .. questID .. ":complete"
  end
  return "q" .. questID
end
Player.KeyOf = keyOf

-- Lines of Elise: list key prefix of each kind.
Player.LINES = { zone = "z", level = "l", companion = "c", -- companion: D18, 2026-10-15
  book = "b", gossip = "g" } -- 2026-10-21

-- Options of the Play* functions for what the addon starts by itself.
Player.AUTO = { auto = true }

-- An automatic start refused here (a battleground, core/silence.lua): the reason, else nil.
local function refusedAuto(opts)
  if opts and opts.auto and H.Silence and H.Silence.Active() then
    return "battleground"
  end
  return nil
end

local function lineKey(kind, id)
  return Player.LINES[kind] .. id
end
Player.LineKey = lineKey
local LIST_MAX = 19 -- rows of the list panel; beyond, the oldest played items are dropped
local waiting = false -- silence between two quests of the list: the list is still playing
local nextToken = 0   -- cancels a scheduled start when something else starts or the list stops
-- Page sound the client plays when a quest opens (FrameXML QuestFrame); numeric ID as fallback
-- if the SOUNDKIT table is missing (unverified on Forever). Played on the Master channel, two
-- copies at once, to stand out above the voice (the SFX slider is often low).
local PAGE_SOUND_FALLBACK = 875
local PAGE_SOUND_COPIES = 2
local listeners = {}
local pollFrame = CreateFrame("Frame")
local elapsed, sincePoll = 0, 0

-- fn(event, info): "start" | "stop" (info.reason: finished, stopped, skipped, cleared, replaced) | "queue"
-- | "focus" (a quest already playing or queued was requested again) | "idle" (the list has nothing left to
-- play: its last item ended or was skipped, or it was cleared; not on Stop, which only halts it).
function Player.OnChange(fn)
  listeners[#listeners + 1] = fn
end

local function notify(event, info)
  for i = 1, #listeners do
    local ok, err = pcall(listeners[i], event, info)
    if not ok then
      H.Debug("player listener error: %s", tostring(err))
    end
  end
end

function Player.Current()
  return current
end

-- part nil: any part of the quest.
function Player.IsPlaying(questID, part)
  if not current then
    return false
  end
  return questID == nil or (current.questID == questID and (part == nil or (current.part or "detail") == part))
end

local function find(key)
  for i, item in ipairs(list) do
    if item.key == key then
      return i, item
    end
  end
  return nil
end

local function isCurrent(item)
  return current ~= nil and current.key == item.key
end

local function add(item)
  item.played = false
  list[#list + 1] = item
  local i = 1
  while #list > LIST_MAX and i <= #list do
    local old = list[i]
    if old.played and not isCurrent(old) then
      table.remove(list, i)
    else
      i = i + 1
    end
  end
end

local function drop(key)
  local i = find(key)
  if i then
    table.remove(list, i)
  end
end

-- Items not played yet, in list order (the current one is played).
function Player.Queue()
  local pending = {}
  for _, item in ipairs(list) do
    if not item.played then
      pending[#pending + 1] = item
    end
  end
  return pending
end

-- part nil: any part of the quest. Second result: the position in the queue.
function Player.IsQueued(questID, part)
  for i, item in ipairs(Player.Queue()) do
    if item.questID == questID and (part == nil or (item.part or "detail") == part) then
      return true, i
    end
  end
  return false
end

-- The play list in order: { {questID, part, line, lineID, test, state = "done"|"playing"|"queued", position}, ... }
function Player.List()
  local entries, position = {}, 0
  for _, item in ipairs(list) do
    local entry = { questID = item.questID, part = item.part, line = item.line, lineID = item.lineID, test = item.test }
    if isCurrent(item) then
      entry.state = "playing"
    elseif item.played then
      entry.state = "done"
    else
      position = position + 1
      entry.state, entry.position = "queued", position
    end
    entries[#entries + 1] = entry
  end
  return entries
end

-- Removes a quest part not played yet from the list (part nil: "detail"). Returns true if it was queued.
function Player.Remove(questID, part)
  local key = keyOf(questID, part)
  for i, item in ipairs(list) do
    if item.key == key and not item.played then
      table.remove(list, i)
      notify("queue", item)
      return true
    end
  end
  return false
end

-- True while a line of Elise plays; IsLineQueued: queued, and its position.
function Player.IsLinePlaying(kind, id)
  return current ~= nil and current.line == kind and current.lineID == tonumber(id)
end

function Player.IsLineQueued(kind, id)
  for i, item in ipairs(Player.Queue()) do
    if item.line == kind and item.lineID == tonumber(id) then
      return true, i
    end
  end
  return false
end

-- Removes a line of Elise not played yet from the list. Returns true if it was queued.
function Player.RemoveLine(kind, id)
  if not Player.LINES[kind] then
    return false
  end
  local key = lineKey(kind, tonumber(id) or -1)
  for i, item in ipairs(list) do
    if item.key == key and not item.played then
      table.remove(list, i)
      notify("queue", item)
      return true
    end
  end
  return false
end

local function playPageSound()
  if not ForeverSpeechDB.pageSound or type(PlaySound) ~= "function" then
    return
  end
  local kit = (type(SOUNDKIT) == "table" and SOUNDKIT.IG_QUEST_LIST_OPEN) or PAGE_SOUND_FALLBACK
  for _ = 1, PAGE_SOUND_COPIES do
    pcall(PlaySound, kit, "Master")
  end
end

-- True while a sound plays or the list waits between two quests.
function Player.IsBusy()
  return current ~= nil or waiting
end

local function cancelNext()
  nextToken = nextToken + 1
  waiting = false
end

local function stopPolling()
  pollFrame:SetScript("OnUpdate", nil)
end

local playNext -- defined after the quest helpers

-- Starts the next item after the gap set in the options (seconds, 0 = right away).
local function scheduleNext()
  cancelNext()
  local gap = tonumber(ForeverSpeechDB.gap) or 0
  if gap <= 0 or not Player.Queue()[1] then
    playNext()
    return
  end
  waiting = true
  local token = nextToken
  H.Trace("player: next in %ss", gap)
  C_Timer.After(gap, function()
    if token == nextToken then
      waiting = false
      playNext()
    end
  end)
end

local function finish(reason)
  local info = current
  current = nil
  stopPolling()
  if info then
    info.reason = reason
    H.Trace("player: ended %s quest=%s source=%s", reason, info.questID, info.source)
    notify("stop", info)
  end
  if reason == "finished" then
    scheduleNext()
  elseif reason == "skipped" then
    playNext()
  end
end

local function onUpdate(_, dt)
  elapsed = elapsed + dt
  sincePoll = sincePoll + dt
  if sincePoll < POLL_INTERVAL or not current or current.kind ~= "file" then
    return
  end
  sincePoll = 0
  if C_Sound and C_Sound.IsPlaying then
    local ok, playing = pcall(C_Sound.IsPlaying, current.handle)
    if ok and not playing then
      finish("finished")
    end
  elseif current.dur and elapsed >= current.dur then
    finish("finished")
  end
end

local function start(info)
  cancelNext()
  current = info
  elapsed, sincePoll = 0, 0
  local _, item = find(info.key)
  if item then
    item.played = true
  end
  if info.questID or info.line then
    playPageSound()
  end
  if info.kind == "file" then
    pollFrame:SetScript("OnUpdate", onUpdate)
  end
  H.Trace("player: started %s quest=%s part=%s line=%s %s source=%s voice=%s", info.kind, info.questID, info.part,
    info.line, info.lineID, info.source, info.voice)
  notify("start", info)
end

-- Stops everything and drops the items not played yet.
function Player.Clear()
  cancelNext()
  local had = current ~= nil or #Player.Queue() > 0
  for i = #list, 1, -1 do
    if not list[i].played then
      table.remove(list, i)
    end
  end
  Player.Stop("cleared")
  notify("queue", {})
  notify("idle", {})
  return had
end

-- Stops everything and empties the play list.
function Player.Reset()
  cancelNext()
  list = {}
  Player.Stop("cleared")
  notify("queue", {})
  notify("idle", {})
end

-- Stops the current audio and halts the list: nothing else starts, the items not played yet stay.
-- Internal callers pass "replaced", "cleared" or "skipped" (Next).
function Player.Stop(reason)
  if not current then
    if waiting then -- stopped during the silence between two quests
      cancelNext()
      notify("queue", {})
      return true
    end
    return false
  end
  if not reason or reason == "stopped" then
    cancelNext()
  end
  if current.kind == "file" then
    StopSound(current.handle)
  elseif C_VoiceChat and C_VoiceChat.StopSpeakingText then
    pcall(C_VoiceChat.StopSpeakingText)
  end
  finish(reason or "stopped")
  return true
end

-- Skips to the first item not played yet, right away (no gap). Returns true if something starts.
function Player.Next()
  cancelNext()
  if current then
    Player.Stop("skipped")
  else
    playNext()
  end
  return current ~= nil
end

-- Plays an .ogg path. Returns true if the client accepted it (false for a missing file).
function Player.PlayFile(path, info)
  Player.Stop("replaced")
  local willPlay, handle = PlaySoundFile(path, ForeverSpeechDB.channel or "Dialog")
  if not willPlay then
    H.Debug("PlaySoundFile refused %s", path)
    return false
  end
  info = info or {}
  info.kind, info.handle, info.path = "file", handle, path
  start(info)
  return true
end

function Player.PickVoice()
  if not (C_VoiceChat and C_VoiceChat.GetTtsVoices) then
    return nil
  end
  local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
  if not ok or type(voices) ~= "table" then
    return nil
  end
  for _, wanted in ipairs(TTS_VOICE_PREFERENCE) do
    for _, voice in ipairs(voices) do
      if tostring(voice.name):lower():find(wanted, 1, true) then
        return voice
      end
    end
  end
  return nil
end

-- Reads text with the client's text-to-speech (French voice only). Returns true on success.
function Player.Speak(text, info)
  if not text or text == "" or not (C_VoiceChat and C_VoiceChat.SpeakText) then
    return false
  end
  local voice = Player.PickVoice()
  if not voice then
    return false
  end
  Player.Stop("replaced")
  local ok = pcall(C_VoiceChat.SpeakText, voice.voiceID, text, TTS_RATE, TTS_VOLUME, false)
  if not ok then
    return false
  end
  info = info or {}
  info.kind, info.voice = "tts", voice.name
  start(info)
  return true
end

-- The end of an utterance is matched by utteranceID: a FINISHED event for a replaced utterance
-- can arrive after the new one started and must not stop it.
H.TryRegisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED", function(_, utteranceID)
  if current and current.kind == "tts" and current.utteranceID == nil then
    current.utteranceID = utteranceID
  end
end)

local function onTTSDone(_, utteranceID)
  if current and current.kind == "tts" and current.utteranceID ~= nil and current.utteranceID == utteranceID then
    finish("finished")
  end
end
H.TryRegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FINISHED", onTTSDone)
H.TryRegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FAILED", onTTSDone)

-- Quest playback ------------------------------------------------------------------

-- Starts a quest now. Fallback when the index has no entry (CLAUDE.md section 8): "tts" (default:
-- client TTS on the captured or quest log text, test sound if none), "test" sound, or "none".
local function startQuest(questID, part)
  part = part or "detail"
  local key = keyOf(questID, part)
  local entry = H.Index.Lookup(questID, part)
  if entry then
    local info = { key = key, questID = questID, part = part, source = entry.src, dur = entry.dur }
    if Player.PlayFile(H.Index.FileFor(entry), info) then
      return true, "index"
    end
    H.Debug("index file missing for quest %d (%s)", questID, part)
  end
  local fallback = ForeverSpeechDB.fallback
  if fallback == "tts" then
    local text = H.QuestData and H.QuestData.Text(questID, part)
    if text and Player.Speak(text, { key = key, questID = questID, part = part, source = "tts" }) then
      return true, "tts"
    end
  end
  if fallback ~= "none"
    and Player.PlayFile(Player.TEST_FILE, { key = key, questID = questID, part = part, source = "test" }) then
    return true, "test"
  end
  return false, "no audio"
end

-- Starts a line of Elise now: her audio, else (fallback "tts") the client's speech synthesis on her text. No test
-- sound: a line without either is left out.
local function startLine(kind, id)
  local entry = H.Index.Line(kind, id)
  if not entry then
    return false, "unknown " .. kind
  end
  local key = lineKey(kind, id)
  if entry.intro then
    local info = { key = key, line = kind, lineID = id, source = entry.intro.src, dur = entry.intro.dur }
    if Player.PlayFile(H.Index.FileFor(entry.intro), info) then
      return true, "index"
    end
    H.Debug("index file missing for %s %d", kind, id)
  end
  if ForeverSpeechDB.fallback == "tts" and entry.text and not entry.noTTS
    and Player.Speak(entry.text, { key = key, line = kind, lineID = id, source = "tts" }) then
    return true, "tts"
  end
  return false, "no audio"
end

local function startItem(item)
  if item.test then
    return Player.PlayFile(Player.TEST_FILE, { key = "test", source = "test" }), "test"
  end
  if item.line then
    return startLine(item.line, item.lineID)
  end
  return startQuest(item.questID, item.part)
end

-- Starts the first item not played yet; items without audio leave the list.
playNext = function()
  if not H.IsEnabled() then
    return false
  end
  local item = Player.Queue()[1]
  while item do
    notify("queue", item)
    if startItem(item) then
      return true
    end
    drop(item.key)
    item = Player.Queue()[1]
  end
  notify("idle", {})
  return false
end

-- Adds the item at the end of the list and plays it now if nothing is playing. An item already
-- in the list is not added again. Returns a status and a detail: "playing", how | "queued",
-- position | "duplicate", "playing"|"queued"|"played" | "failed", reason.
function Player.Enqueue(item)
  if not H.IsEnabled() then
    return "failed", "audio off"
  end
  local refused = refusedAuto(item)
  if refused then
    return "failed", refused
  end
  local _, listed = find(item.key)
  if listed and listed.test and listed.played and not isCurrent(listed) then
    drop(listed.key) -- the test sound can always be played again
    listed = nil
  end
  if listed then
    notify("focus", listed)
    if isCurrent(listed) then
      return "duplicate", "playing"
    end
    return "duplicate", listed.played and "played" or "queued"
  end
  add(item)
  if Player.IsBusy() then
    notify("queue", item)
    return "queued", #Player.Queue()
  end
  local ok, how = startItem(item)
  if ok then
    return "playing", how
  end
  drop(item.key)
  return "failed", how
end

-- Play button of the window and double-click in the play list: stops the current audio and plays
-- the quest part from the start now (added at the end if it is not in the list yet). The list keeps
-- its order; afterwards playback goes on with the first item not played yet. part nil: "detail".
function Player.PlayNow(questID, part)
  questID = tonumber(questID)
  if not questID then
    return "failed", "invalid questID"
  end
  if not H.IsEnabled() then
    return "failed", "audio off"
  end
  part = Player.PARTS[part] and part or "detail"
  local key = keyOf(questID, part)
  if not find(key) then
    add({ key = key, questID = questID, part = part })
  end
  Player.Stop("replaced")
  local ok, how = startQuest(questID, part)
  if ok then
    return "playing", how
  end
  drop(key)
  playNext()
  return "failed", how
end

-- Reads a quest part (play buttons, "Accepter et lire", "Terminer la quête", /fs play): it always
-- goes in the list, at the end, or at its place if it is already there (a played part becomes not
-- played again). If the list is playing, it goes on; else this part starts now. part nil: "detail".
-- opts.auto (Player.AUTO): started by the addon itself, not by the player (refused in a battleground).
function Player.PlayQuest(questID, part, opts)
  questID = tonumber(questID)
  if not questID then
    return "failed", "invalid questID"
  end
  if not H.IsEnabled() then
    return "failed", "audio off"
  end
  local refused = refusedAuto(opts)
  if refused then
    return "failed", refused
  end
  part = Player.PARTS[part] and part or "detail"
  local key = keyOf(questID, part)
  local _, listed = find(key)
  if not listed then
    return Player.Enqueue({ key = key, questID = questID, part = part, auto = opts and opts.auto or nil })
  end
  if isCurrent(listed) then
    notify("focus", listed)
    return "duplicate", "playing"
  end
  if not Player.IsBusy() then
    return Player.PlayNow(questID, part)
  end
  if not listed.played then
    notify("focus", listed)
    return "duplicate", "queued"
  end
  listed.played = false
  notify("queue", listed)
  for i, item in ipairs(Player.Queue()) do
    if item == listed then
      return "queued", i
    end
  end
end

-- Lines of Elise (2026-10-11): the same rules as a quest part. PlayLine puts one in the list (at the end, or at its
-- place if already there: a played one becomes not played again) and starts it if nothing plays; PlayLineNow
-- (window Play button, double-click in the list) plays it now from the start. kind: "zone" (map ID) or "level".
local function checkLine(kind, id)
  id = tonumber(id)
  if not Player.LINES[kind] or not id or not H.Index.Line(kind, id) then
    return nil, "unknown " .. tostring(kind)
  end
  if not H.IsEnabled() then
    return nil, "audio off"
  end
  return id
end

function Player.PlayLineNow(kind, id, opts)
  local why
  id, why = checkLine(kind, id)
  if not id then
    return "failed", why
  end
  why = refusedAuto(opts)
  if why then
    return "failed", why
  end
  local key = lineKey(kind, id)
  if not find(key) then
    add({ key = key, line = kind, lineID = id, auto = opts and opts.auto or nil })
  end
  Player.Stop("replaced")
  local ok, how = startLine(kind, id)
  if ok then
    return "playing", how
  end
  drop(key)
  playNext()
  return "failed", how
end

-- opts.auto (Player.AUTO): started by the addon itself, not by the player (refused in a battleground).
function Player.PlayLine(kind, id, opts)
  local why
  id, why = checkLine(kind, id)
  if not id then
    return "failed", why
  end
  why = refusedAuto(opts)
  if why then
    return "failed", why
  end
  local key = lineKey(kind, id)
  local _, listed = find(key)
  if not listed then
    return Player.Enqueue({ key = key, line = kind, lineID = id, auto = opts and opts.auto or nil })
  end
  if isCurrent(listed) then
    notify("focus", listed)
    return "duplicate", "playing"
  end
  if not Player.IsBusy() then
    return Player.PlayLineNow(kind, id, opts)
  end
  if not listed.played then
    notify("focus", listed)
    return "duplicate", "queued"
  end
  listed.played = false
  notify("queue", listed)
  for i, item in ipairs(Player.Queue()) do
    if item == listed then
      return "queued", i
    end
  end
end

-- Pages read while their window is open (2026-10-21): a book page, an NPC's dialogue --------------------------

-- Drops the items of a line kind not played yet. Returns how many.
local function dropQueued(kind)
  local dropped = 0
  for i = #list, 1, -1 do
    local item = list[i]
    if item.line == kind and not item.played and not isCurrent(item) then
      table.remove(list, i)
      dropped = dropped + 1
    end
  end
  if dropped > 0 then
    notify("queue", {})
  end
  return dropped
end

-- A new page of a window that shows one at a time (a book's page turned, an NPC's next dialogue page): the pages of
-- that kind not played yet leave the list; if a page of that kind plays, it stops and this one starts now, else this
-- one goes in the list like any line (Player.PlayLine).
function Player.PlayPage(kind, id, opts)
  id = tonumber(id)
  if current and current.line == kind and current.lineID == id then
    notify("focus", current)
    return "duplicate", "playing"
  end
  dropQueued(kind)
  if current and current.line == kind then
    return Player.PlayLineNow(kind, id, opts)
  end
  return Player.PlayLine(kind, id, opts)
end

-- The window of a line kind closed: its page that still plays stops (the list goes on), the ones not played yet leave
-- the list. Returns true if one was playing.
function Player.StopPages(kind)
  dropQueued(kind)
  if current and current.line == kind then
    Player.Stop("skipped")
    return true
  end
  return false
end

-- Entering a battleground or an arena (core/silence.lua): what the addon started by itself leaves the list, and stops
-- if it plays. What the player asked for stays. Returns how many items were dropped.
function Player.DropAuto()
  local dropped = 0
  for i = #list, 1, -1 do
    local item = list[i]
    if item.auto and not item.played and not isCurrent(item) then
      table.remove(list, i)
      dropped = dropped + 1
    end
  end
  local playing = current and select(2, find(current.key))
  if playing and playing.auto then
    Player.Stop("skipped")
    dropped = dropped + 1
  elseif dropped > 0 then
    notify("queue", {})
  end
  return dropped
end

-- Commands -------------------------------------------------------------------------

local function report(label, status, detail)
  if status == "playing" then
    H.Print("playing %s (%s)", label, detail)
  elseif status == "queued" then
    H.Print("%s queued (position %d)", label, detail)
  elseif status == "duplicate" then
    H.Print("%s is already %s", label, detail)
  else
    H.Print("cannot play %s: %s", label, detail)
  end
end

-- Turning the audio off stops everything and drops what was not played yet.
H.OnEnabledChange(function(enabled)
  if not enabled then
    Player.Clear()
  end
end)

H.RegisterCommand("on", function()
  H.SetEnabled(true)
  H.Print("audio on")
end, "on - turn the audio on")

H.RegisterCommand("off", function()
  H.SetEnabled(false)
  H.Print("audio off: nothing plays, the play buttons are hidden (/fs on to turn it back on)")
end, "off - turn the audio off")

H.RegisterCommand("test", function()
  report("the test sound", Player.Enqueue({ key = "test", test = true }))
end, "test - play the test sound")

H.RegisterCommand("play", function(arg)
  local id, part = arg:match("^(%S*)%s*(%S*)$")
  part = (part == "end" or part == "fin" or part == "complete") and "complete" or "detail"
  if id == "" then
    local recent = H.Capture.lastQuestID or (H.Capture.Recent(1)[1] or {}).questID
    if not recent then
      H.Print("no quest captured yet: open a quest at an NPC, or use /fs play <questID>")
      return
    end
    id = tostring(recent)
  end
  local label = "quest " .. H.Escape(id) .. (part == "complete" and " (end)" or "")
  report(label, Player.PlayQuest(id, part))
end, "play [questID] [end] - play or queue a quest, or its turn-in text (default: last opened quest)")

H.RegisterCommand("stop", function()
  if not Player.Stop() then
    H.Print("nothing is playing")
  end
end, "stop - stop the current audio, the play list halts")

H.RegisterCommand("next", function()
  if not Player.Next() then
    H.Print("nothing left to play")
  end
end, "next - skip to the next quest of the play list")

H.RegisterCommand("clear", function()
  Player.Clear()
  H.Print("playback stopped, queue emptied")
end, "clear - stop everything and drop the quests not played yet")

H.RegisterCommand("reset", function()
  Player.Reset()
  H.Print("play list emptied")
end, "reset - stop everything and empty the play list")

H.RegisterCommand("queue", function()
  local cur = Player.Current()
  local function label(item)
    if item.line then
      local entry = H.Index.Line(item.line, item.lineID) or {}
      return item.line .. " " .. item.lineID .. " (" .. tostring(entry.name) .. ")"
    end
    if not item.questID then
      return "test sound"
    end
    return "quest " .. item.questID .. (item.part == "complete" and " (end)" or "")
  end
  H.Print("now: %s", cur and label(cur) or "nothing")
  for i, item in ipairs(Player.Queue()) do
    H.Print("  %d. %s", i, label(item))
  end
end, "queue - show the play queue")

local CHANNELS = { Master = true, Dialog = true, SFX = true, Music = true, Ambience = true }

H.RegisterCommand("channel", function(arg)
  for name in pairs(CHANNELS) do
    if name:lower() == arg:lower() then
      ForeverSpeechDB.channel = name
    end
  end
  H.Print("audio channel: %s", ForeverSpeechDB.channel)
end, "channel Dialog|Master|SFX|Music|Ambience")

H.RegisterCommand("fallback", function(arg)
  arg = arg:lower()
  if arg == "test" or arg == "tts" or arg == "none" then
    ForeverSpeechDB.fallback = arg
  end
  H.Print("fallback when no audio file: %s", ForeverSpeechDB.fallback)
end, "fallback test|tts|none - what plays without an audio file")
