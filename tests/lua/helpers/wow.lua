-- Minimal WoW API stubs for busted. Only what the addon touches; extend as needed.
-- Unknown frame methods are permissive no-ops so UI code can be loaded headless.
local M = {}

local ADDON_DIR = "addon/ForeverSpeech/"

local frames, chat, timers, sounds, knownEvents

local function newObject(objectType)
  local obj = { [0] = newproxy and newproxy() or {}, _type = objectType, _scripts = {}, _events = {} }
  return setmetatable(obj, {
    __index = function()
      return function() end
    end,
  })
end

local frameMethods = {}

function frameMethods:RegisterEvent(event)
  if knownEvents and not knownEvents[event] then
    error("Attempt to register unknown event \"" .. event .. "\"")
  end
  -- Forever (like Retail) returns false for an event the frame already has (seen 2026-10-07).
  if self._events[event] then
    return false
  end
  self._events[event] = true
  return true
end
function frameMethods:UnregisterEvent(event) self._events[event] = nil end
function frameMethods:IsEventRegistered(event) return self._events[event] == true end
function frameMethods:SetScript(name, fn) self._scripts[name] = fn end
function frameMethods:GetScript(name) return self._scripts[name] end
function frameMethods:HookScript(name, fn)
  local old = self._scripts[name]
  self._scripts[name] = function(...)
    if old then old(...) end
    fn(...)
  end
end
function frameMethods:Show() self._shown = true end
function frameMethods:Hide() self._shown = false end
function frameMethods:IsShown() return self._shown == true end
-- Geometry, with M.layout: every frame laid out at the same place, scale 1 (the secure side tabs' placement).
function frameMethods.GetEffectiveScale() return M.layout and 1 or nil end
function frameMethods.GetRight() return M.layout and 300 or nil end
function frameMethods.GetTop() return M.layout and 600 or nil end
function frameMethods.GetBottom() return M.layout and 200 or nil end
-- Shown (a frame never hidden counts as shown, as a new frame in the client) and its parents too.
function frameMethods:IsVisible()
  local parent = rawget(self, "_parent")
  return rawget(self, "_shown") ~= false and (parent == nil or parent:IsVisible())
end
function frameMethods:SetShown(shown) self._shown = shown and true or false end
function frameMethods:GetObjectType() return self._type end
function frameMethods:GetName() return self._name end
function frameMethods:GetParent() return self._parent end
function frameMethods:SetText(text) self._text = text end
function frameMethods:GetText() return self._text end
function frameMethods.CreateTexture() return M.newRegion("Texture") end
function frameMethods:Click(button)
  local onClick = self._scripts.OnClick
  if onClick then onClick(self, button or "LeftButton") end
end
function frameMethods:SetAttribute(key, value)
  local attributes = rawget(self, "_attributes") or {}
  rawset(self, "_attributes", attributes)
  attributes[key] = value
end
function frameMethods:GetAttribute(key)
  local attributes = rawget(self, "_attributes")
  return attributes and attributes[key]
end
function frameMethods:SetChecked(checked) self._checked = checked and true or false end
function frameMethods:GetChecked() return self._checked == true end
-- A file listed in M.refusedTextures makes SetTexture return false, as the client does for a file it cannot load.
function frameMethods:SetTexture(t)
  self._texture = t
  return not M.refusedTextures[t]
end
function frameMethods:GetTexture() return self._texture end
function frameMethods:SetDesaturated(on) self._desaturated = on and true or false end
function frameMethods:IsDesaturated() return self._desaturated == true end
function frameMethods:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end
function frameMethods:GetVertexColor() return unpack(self._vertex or { 1, 1, 1, 1 }) end
function frameMethods.CreateFontString() return M.newRegion("FontString") end
function frameMethods:SetValue(v) self._value = v end
function frameMethods:GetValue() return self._value end
function frameMethods:SetStatusBarColor(r, g, b) self._barColor = { r, g, b } end
function frameMethods:GetStatusBarColor() return unpack(self._barColor or {}) end

function M.newRegion(objectType)
  local obj = newObject(objectType)
  for k, v in pairs(frameMethods) do
    rawset(obj, k, v)
  end
  return obj
end

function M.reset(opts)
  opts = opts or {}
  frames, chat, timers, sounds = {}, {}, {}, {}
  knownEvents = opts.knownEvents
  M.clock = 0
  M.refusedTextures = {}
  M.frames, M.chat, M.timers, M.sounds = frames, chat, timers, sounds

  _G.ForeverSpeech, _G.ForeverSpeechDB, _G.ForeverSpeechCaptures, _G.ForeverSpeechIndex = nil, nil, nil, nil
  _G.ForeverSpeechGameVoices, _G.MuteSoundFile, _G.UnmuteSoundFile = nil, nil, nil
  -- zone introductions (zones_spec sets them)
  _G.C_Map, _G.UnitOnTaxi, _G.IsFlying, _G.UnitIsDeadOrGhost, _G.IsInInstance = nil, nil, nil, nil, nil
  _G.GetZoneText, _G.GetRealZoneText, _G.UnitName, _G.GetRealmName = nil, nil, nil, nil
  _G.WorldMapFrame, _G.C_MapExplorationInfo = nil, nil
  -- fishing mode (fishing_spec sets them)
  _G.InCombatLockdown, _G.IsPlayerSpell, _G.IsSpellKnown, _G.C_Spell, _G.GetSpellInfo = nil, nil, nil, nil, nil
  _G.C_Container, _G.C_Item, _G.GetInventoryItemLink, _G.EquipItemByName = nil, nil, nil, nil
  _G.DoEmote = nil
  -- disenchant mode and the backpack's side tabs (disenchant_spec sets them)
  _G.ContainerFrameCombinedBags, _G.ContainerFrame1, _G.ContainerFrame_Update = nil, nil, nil
  _G.UpdateContainerFrameAnchors = nil -- bag_frame_spec sets it
  _G.SpellIsTargeting, _G.C_TooltipInfo = nil, nil
  _G.C_TradeSkillUI, _G.Enum = nil, nil -- the professions' places (disenchant_spec sets them)
  _G.ITEM_DISENCHANT_ANY_SKILL, _G.ITEM_DISENCHANT_MIN_SKILL, _G.ITEM_DISENCHANT_NOT_DISENCHANTABLE = nil, nil, nil
  M.layout = nil
  -- quest level (ui_spec sets them)
  _G.UnitLevel, _G.GetQuestDifficultyColor, _G.QuestDifficultyColors, _G.C_QuestLog = nil, nil, nil, nil
  -- time played (ui_spec sets them)
  _G.RequestTimePlayed, _G.NUM_CHAT_WINDOWS, _G.ChatFrame1, _G.GetMaxPlayerLevel = nil, nil, nil, nil
  -- companion journal (companions_spec sets them)
  _G.IsInGroup, _G.IsInRaid, _G.GetNumGroupMembers, _G.GetNumSubgroupMembers = nil, nil, nil, nil
  _G.GetRaidRosterInfo, _G.UnitIsUnit, _G.UnitClass, _G.UnitIsConnected = nil, nil, nil, nil
  _G.GetInstanceInfo, _G.RAID_CLASS_COLORS, _G.GameTooltip = nil, nil, nil
  _G.SendChatMessage, _G.LE_PARTY_CATEGORY_INSTANCE = nil, nil -- quest announcements (announce_spec sets them)
  _G.InCinematic, _G.CinematicFrame, _G.MovieFrame = nil, nil, nil -- zones_spec sets them
  -- secret values, ducking, books, dialogues (2026-10-21: secret_spec, ducking_spec, books_spec, dialogues_spec)
  _G.issecretvalue, _G.SetCVar, _G.C_CVar, _G.UnitRace, _G.LOCALIZED_CLASS_NAMES_FEMALE = nil, nil, nil, nil, nil
  _G.ItemTextGetText, _G.ItemTextGetItem, _G.ItemTextGetPage, _G.ItemTextGetCreator = nil, nil, nil, nil
  _G.MailFrame, _G.C_GossipInfo, _G.GetGossipText, _G.GetSubZoneText = nil, nil, nil, nil
  _G.BINDING_HEADER_FOREVERSPEECH, _G.BINDING_NAME_FOREVERSPEECH_PLAY = nil, nil
  _G.SlashCmdList = {}
  _G.SLASH_FOREVERSPEECH1 = nil
  _G.UIParent = M.newRegion("Frame")
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }
  _G.date = os.date
  _G.time = os.time
  _G.WOW_PROJECT_ID = 99

  _G.CreateFrame = function(objectType, name, parent)
    local f = M.newRegion(objectType)
    f._name, f._parent = name, parent
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
  end
  _G.GetTime = function() return M.clock end
  _G.GetBuildInfo = function() return "1.60.1", "70205", "Oct 1 2026", 16001 end
  _G.GetLocale = function() return "frFR" end
  -- "1" for every CVar the addon reads (sound, dialogue channel), except the gamepad interface, off as on a PC
  _G.GetCVar = function(name) return name == "InputDeviceInterfaceStyle" and "0" or "1" end
  _G.C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = M.clock + delay, fn = fn } end,
  }
  _G.hooksecurefunc = function(tbl, name, hook)
    if type(tbl) == "string" then
      tbl, name, hook = _G, tbl, name
    end
    local orig = tbl[name]
    tbl[name] = function(...)
      local r = { orig(...) }
      hook(...)
      return unpack(r)
    end
  end
  _G.UnitGUID = function() return nil end
  _G.UnitExists = function() return false end
  _G.UnitSex = function() return 2 end
  _G.Minimap = M.newRegion("Frame")
  _G.GetCursorPosition = function() return 0, 0 end
  M.pageSounds = {}
  _G.SOUNDKIT = { IG_QUEST_LIST_OPEN = 875 }
  _G.PlaySound = function(kit) M.pageSounds[#M.pageSounds + 1] = kit end
  M.playing = {} -- handle -> true while "playing"; tests flip it to simulate the end
  _G.PlaySoundFile = function(path, channel)
    if M.missingFiles and M.missingFiles[path] then
      return -- the client returns nothing for a missing file (S1)
    end
    sounds[#sounds + 1] = { path = path, channel = channel }
    M.playing[#sounds] = true
    return true, #sounds
  end
  M.stopped = {}
  _G.StopSound = function(handle)
    M.stopped[#M.stopped + 1] = handle
    M.playing[handle] = nil
  end
  _G.C_Sound = { IsPlaying = function(handle) return M.playing[handle] == true end }
  _G.C_VoiceChat = nil
  M.missingFiles = nil
  M.index = nil -- the index loaded in place of data/index.lua (default: empty, contract v9)
end

-- Runs every frame's OnUpdate `steps` times with `dt` seconds per step.
function M.tick(dt, steps)
  for _ = 1, steps or 1 do
    M.clock = M.clock + dt
    for _, f in ipairs(frames) do
      local onUpdate = f._scripts.OnUpdate
      if onUpdate and f:IsVisible() then -- as the client: a hidden frame gets no OnUpdate
        onUpdate(f, dt)
      end
    end
  end
end

-- Runs due C_Timer callbacks while advancing the clock.
function M.advance(seconds)
  local target = M.clock + seconds
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local nextTimer = timers[1]
    if not nextTimer or nextTimer.at > target then break end
    table.remove(timers, 1)
    M.clock = nextTimer.at
    nextTimer.fn()
  end
  M.clock = target
end

function M.fire(event, ...)
  for _, f in ipairs(frames) do
    if f._events[event] and f._scripts.OnEvent then
      f._scripts.OnEvent(f, event, ...)
    end
  end
end

-- Loads the addon files in TOC order, like the client does.
function M.loadAddon()
  local ns = {}
  for line in io.lines(ADDON_DIR .. "ForeverSpeech.toc") do
    line = line:gsub("%s+$", "")
    if line == "data\\index.lua" then
      -- The generated index holds real data (audio of produced quests): tests start from an
      -- empty index of the same contract and add what they need. addon_spec checks the real file.
      _G.ForeverSpeechIndex = M.index or { version = 9, quests = {}, npcs = {} }
    elseif line == "data\\game_voices.lua" then
      -- generated from Wowhead data, not committed: tests use two file IDs
      _G.ForeverSpeechGameVoices = { version = 1, files = { 543353, 543355 } }
    elseif line ~= "" and not line:find("^#") then
      local path = ADDON_DIR .. line:gsub("\\", "/")
      local chunk = assert(loadfile(path))
      chunk("ForeverSpeech", ns)
    end
  end
  return ns
end

function M.slash(msg)
  _G.SlashCmdList.FOREVERSPEECH(msg)
end

function M.chatText()
  return table.concat(chat, "\n")
end

return M
