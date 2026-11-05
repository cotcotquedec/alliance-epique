-- ForeverSpeech: event dispatch and SavedVariables initialisation.
local H = ForeverSpeech

-- Bumped when a saved setting must be reset once (see migrate).
local SETTINGS_VERSION = 4

local DB_DEFAULTS = {
  enabled = true, -- audio on; off: nothing plays and the game UI gets no button (captures go on)
  debug = false,
  channel = "Dialog",
  fallback = "tts", -- tts | test | none (see Player.PlayQuest)
  autoplay = true, -- read every quest accepted or turned in, whatever the interface (core/autoplay.lua, CLAUDE.md 9.1)
  openOnPlay = true, -- open the main window whenever a quest starts playing
  followTracked = true, -- while nothing plays, the main window shows the quest the player follows (logbook)
  pageSound = true, -- quest page sound when a quest starts
  muteGameVoices = true, -- mute the game's own NPC greetings and farewells with quest NPCs (GameVoices)
  levelLines = true, -- Elise's line 2 s after each level gained (core/levels.lua)
  companionLines = true, -- Elise's line when a companion reaches a friendship tier (core/companions.lua, D18)
  zoneIntros = true, -- Elise introduces each zone the first time the character sets foot in it (core/zones.lua)
  gap = 2, -- seconds of silence between two quests of the play list
  showList = true, -- play list panel next to the main window
  showText = true, -- quest text on the quest tab (in-game text only: capture or quest log)
  dockFlare = true, -- the window docked to FlareUI's quest tracker while it runs (ui/player_frame.lua, 2026-11-05)
  windowShown = false, -- the window was open at the last logout or /reload: opened again (2026-10-21)
  minimapHide = false,
  minimapAngle = 215, -- degrees around the minimap
  modelZoom = 0.6, -- NPC model framing, PlayerModel:SetPortraitZoom: 0 = full body, 1 = face
  -- switches of the options window (2026-10-15): features that were always on
  showQuestLevel = true, -- "[12] Title" in its difficulty color in the quest window
  companionsTrack = true, -- the companion journal counts the time in group (core/companions.lua)
  companionsTooltip = true, -- two lines in a companion's tooltip
  companionsChat = true, -- a chat line when a companion reaches a tier
  fishingTab = true, -- the fishing side tab (shown anyway while fishing mode is on)
  disenchantTab = true, -- the backpack's disenchant side tab (shown anyway while disenchant mode is on)
  professionTabs = true, -- the backpack's Cooking and Tailoring side tabs (ui/bag_tabs.lua)
  bagRows = true, -- the combined bag laid out one bag per row (ui/bag_frame.lua)
  mapButton = true, -- the world map's button replaying Elise's zone introduction
  mapPanel = true, -- the zone story panel beside the world map (ui/map_panel.lua, 2026-10-21)
  announceComplete = true, -- in a group, a chat line when a quest's objectives are all done (core/announce.lua)
  announceChannel = "party", -- party: the group channel (party, raid, instance) | say: /say
  questAreaHighlight = true, -- highlight in the tracker and the log the quests whose area the player stands in
  -- 2026-10-21. New keys only: their defaults fill them in, no migration needed.
  duck = true, -- music, ambience and effects lowered while a line plays (core/ducking.lua)
  readInBattleground = false, -- off: nothing starts by itself in a battleground or an arena (core/silence.lua)
  readBooks = true, -- a book or plaque page read when shown, by Elise (core/books.lua, D19)
  readGossip = true, -- an NPC's dialogue read in its voice when the gossip window opens (core/dialogues.lua, D14)
  sortByLevel = true, -- the quests sorted by level in the objective tracker and the quest log (ui/quest_sort.lua)
  sortOrder = "asc", -- asc: lowest level first | desc: highest first
  emoteWheel = true, -- the emote wheel opens while its key is held (ui/emote_wheel.lua)
}

-- Settings kept by a reset of the options: places and positions, not choices.
local KEPT_ON_RESET = { minimapAngle = true }

-- Audio on/off (options window, /fs on|off). Off: nothing plays, the play buttons are hidden; the minimap icon and
-- /fs open the options window, where it is turned back on.
local enabledListeners = {}

function H.IsEnabled()
  return not ForeverSpeechDB or ForeverSpeechDB.enabled ~= false
end

-- fn(enabled) after each change.
function H.OnEnabledChange(fn)
  enabledListeners[#enabledListeners + 1] = fn
end

-- Every setting back to its default (options window, "Réinitialiser les options"), but places and positions.
function H.ResetSettings()
  local wasEnabled = H.IsEnabled()
  for key, value in pairs(DB_DEFAULTS) do
    if not KEPT_ON_RESET[key] then
      ForeverSpeechDB[key] = value
    end
  end
  H.Trace("settings: reset")
  if H.IsEnabled() ~= wasEnabled then
    H.SetEnabled(ForeverSpeechDB.enabled)
  end
end

function H.SetEnabled(value)
  ForeverSpeechDB.enabled = value and true or false
  H.Trace("enabled: %s", ForeverSpeechDB.enabled)
  for _, fn in ipairs(enabledListeners) do
    local ok, err = pcall(fn, ForeverSpeechDB.enabled)
    if not ok then
      H.Debug("enabled listener error: %s", tostring(err))
    end
  end
end

local frame = CreateFrame("Frame")
local handlers = {}      -- event -> list of handler(event, ...)
local initCallbacks = {} -- run once SavedVariables are ready

H.eventFrame = frame

-- Registers a handler. Raises if the client does not know the event
-- (use TryRegisterEvent for events whose existence is not verified).
function H.RegisterEvent(event, handler)
  if not handlers[event] then
    handlers[event] = {}
    frame:RegisterEvent(event)
  end
  local list = handlers[event]
  list[#list + 1] = handler
end

-- Same as RegisterEvent but returns ok, err instead of raising on unknown events.
-- An event already registered on our frame only gets one more handler: on Forever, RegisterEvent
-- returns false for an event the frame already has (seen 2026-10-07: the second QUEST_COMPLETE handler,
-- the turn-in reading, was dropped).
function H.TryRegisterEvent(event, handler)
  if handlers[event] then
    local list = handlers[event]
    list[#list + 1] = handler
    return true
  end
  local ok, result = pcall(frame.RegisterEvent, frame, event)
  if not ok then
    return false, result
  end
  if result == false then -- some clients may refuse silently instead of raising
    return false, "RegisterEvent returned false"
  end
  if not handlers[event] then
    handlers[event] = {}
  end
  local list = handlers[event]
  list[#list + 1] = handler
  return true
end

-- Runs install() once ready() returns true: now, or on a later ADDON_LOADED / PLAYER_LOGIN
-- (Blizzard UI modules such as the objective tracker or the world map may load after us).
local pendingInstalls = {}

function H.WhenAvailable(ready, install)
  if ready() then
    install()
  else
    pendingInstalls[#pendingInstalls + 1] = { ready = ready, install = install }
  end
end

local function retryInstalls()
  for i = #pendingInstalls, 1, -1 do
    local item = pendingInstalls[i]
    if item.ready() then
      table.remove(pendingInstalls, i)
      item.install()
    end
  end
end

-- Runs fn() after SavedVariables have been loaded and defaulted.
function H.OnInit(fn)
  if H.initialized then
    fn()
  else
    initCallbacks[#initCallbacks + 1] = fn
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then
    return
  end
  for i = 1, #list do
    list[i](event, ...)
  end
end)

-- One-time resets of saved settings. v2: debug back to off (it was on during the phase-1 tests). v3
-- (2026-10-10): the turn-in reading on the reward panel off. v4 (2026-10-21): the "Accepter et lire" and "Terminer et
-- lire" buttons and that reading removed, the automatic reading on for everyone (it is the only way left).
local function migrate(db)
  local from = db.settingsVersion or 1
  if from < 2 then
    db.debug = false
  end
  if from < 4 then
    db.autoplay = true
    db.readOnTurnIn = nil
  end
  db.settingsVersion = SETTINGS_VERSION
end

local function initSavedVariables()
  -- Kept for spike S3: tells whether the client actually restored the files.
  H.svState = {
    dbWasNil = ForeverSpeechDB == nil,
    capturesWasNil = ForeverSpeechCaptures == nil,
  }
  ForeverSpeechDB = ForeverSpeechDB or {}
  ForeverSpeechCaptures = ForeverSpeechCaptures or {}
  for key, value in pairs(DB_DEFAULTS) do
    if ForeverSpeechDB[key] == nil then
      ForeverSpeechDB[key] = value
    end
  end
  migrate(ForeverSpeechDB)
end

H.RegisterEvent("PLAYER_LOGIN", retryInstalls)

H.RegisterEvent("ADDON_LOADED", function(_, addonName)
  retryInstalls()
  if addonName ~= H.name or H.initialized then
    return
  end
  initSavedVariables()
  H.initialized = true
  H.Trace("=== load v%s ===", H.version)
  H.FlushTrace()
  -- One failing module must not prevent the others from initialising.
  for i = 1, #initCallbacks do
    local ok, err = pcall(initCallbacks[i])
    if not ok then
      H.Trace("init error: %s", err)
    end
  end
  initCallbacks = {}
  H.Print("%s", H.L.LOADED)
end)
