-- ForeverSpeech: checks that the client has what the addon calls (functions, frames, events, frame templates,
-- atlases, textures), so a new client build tells at once what is missing instead of one in-game test per feature
-- (CLAUDE.md §2: an unverified API is probed, never assumed; docs/ingame/queue.md).
-- Runs by itself once per client build, a few seconds after entering the world, out of combat: the result goes to
-- ForeverSpeechDB.check (on disk after /reload or logout), and a chat line only when something is missing.
--   /fs check   runs it again and lists what is missing in the chat
-- The lists follow the addon's code: tests/lua/check_spec.lua fails when the code uses a name they lack.
local H = ForeverSpeech

local Check = {}
H.Check = Check

local DELAY = 5 -- seconds after entering the world: the game's own UI modules are loaded by then

-- Names in _G, dotted for a field ("C_QuestLog.GetInfo"). A table lists alternatives: the addon uses the first one
-- the client has (legacy Classic names as fallbacks of the modern ones), missing only when none exists.
Check.GLOBALS = {
  -- game frames and UI helpers
  "UIParent", "Minimap", "GameTooltip", "ChatFontNormal", "DEFAULT_CHAT_FRAME", "WorldMapFrame", "QuestMapFrame",
  "QuestScrollFrame", "QuestFrame", "QuestFrameDetailPanel", "QuestFrameAcceptButton", "QuestFrameDeclineButton",
  "QuestFrameCompleteQuestButton", "QuestFrameCancelButton", "ObjectiveTrackerFrame", "MailFrame",
  "AddonCompartmentFrame", "SettingsPanel", "QuestFont", "QuestTitleFont", "NUM_CHAT_WINDOWS",
  { "ContainerFrameCombinedBags", "ContainerFrame1" },
  { "ContainerFrameCombinedBags.UpdateItems", "ContainerFrame_Update" },
  "UpdateContainerFrameAnchors", "BackdropTemplateMixin", "PortraitFrameMixin", "NineSliceUtil", "EventRegistry",
  "TooltipDataProcessor", "ButtonFrameTemplate_HidePortrait", "HideUIPanel", "SetPortraitToTexture",
  "SetPortraitTextureFromCreatureDisplayID", "ItemLocation", "Enum", "SOUNDKIT", "RAID_CLASS_COLORS",
  "ITEM_QUALITY_COLORS", "LOCALIZED_CLASS_NAMES_FEMALE", "QuestDifficultyColors", "LE_PARTY_CATEGORY_INSTANCE",
  "ITEM_DISENCHANT_ANY_SKILL", "ITEM_DISENCHANT_MIN_SKILL", "ITEM_DISENCHANT_NOT_DISENCHANTABLE", "WOW_PROJECT_ID",
  "QuestLogQuests_Update", "QuestMapFrame_ShowQuestDetails", "Game18Font",
  -- the options in the game's panel (H28)
  "Settings.RegisterCanvasLayoutCategory", "Settings.RegisterCanvasLayoutSubcategory",
  "Settings.RegisterAddOnCategory", "Settings.OpenToCategory",
  -- the interface faded while moving (ui/fade.lua, H42)
  "IsPlayerMoving", "UnitOnTaxi", "UnitAffectingCombat", "GetUIPanel", "ChatEdit_GetActiveWindow", "GetCursorInfo",
  "WorldFrame", "StaticPopup1", "GameMenuFrame", "LootFrame", "EditModeManagerFrame",
  -- frames, sound, timers
  "CreateFrame", "hooksecurefunc", "PlaySound", "PlaySoundFile", "StopSound", "MuteSoundFile", "UnmuteSoundFile",
  "C_Sound.IsPlaying", "C_Timer.After", "C_Texture.GetAtlasInfo", "GetTime", "GetBuildInfo", "GetLocale",
  "GetCursorPosition", { "GetMouseFoci", "GetMouseFocus" }, "ReloadUI", "Screenshot", "InCombatLockdown", "InCinematic",
  { "C_AddOns.LoadAddOn", "LoadAddOn" }, { "C_CVar.GetCVar", "GetCVar" }, { "C_CVar.SetCVar", "SetCVar" },
  "issecretvalue",
  -- speech (client TTS fallback)
  "C_VoiceChat.SpeakText", "C_VoiceChat.StopSpeakingText", "C_VoiceChat.GetTtsVoices",
  -- quest window and quest log
  "GetQuestID", "GetTitleText", "GetQuestText", "GetObjectiveText", "GetRewardText", "GetQuestReward",
  "GetNumQuestChoices", "GetNumQuestRewards", "GetQuestItemInfo", "GetRewardMoney", "GetRewardXP", "IsQuestComplete",
  "GetNumActiveQuests", "GetNumAvailableQuests", "GetActiveTitle", "GetQuestProgressBarPercent",
  "GetQuestDifficultyColor", "GetQuestLogQuestText", "GetQuestLogRewardInfo", "GetQuestLogRewardMoney",
  "GetQuestLogRewardXP", "GetNumQuestLogRewards", "GetNumQuestLogChoices", "GetQuestLogChoiceInfo",
  "C_QuestLog.GetInfo", "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.GetNumQuestLogEntries",
  "C_QuestLog.GetQuestIDForQuestWatchIndex", "C_QuestLog.GetQuestObjectives", "C_QuestLog.GetQuestsOnMap",
  "C_QuestLog.GetSelectedQuest", "C_QuestLog.SetSelectedQuest", "C_QuestLog.GetTitleForQuestID",
  "C_QuestLog.IsComplete", "C_QuestLog.IsQuestFlaggedCompleted", "C_QuestLog.GetNumQuestWatches",
  "C_QuestLog.AddQuestWatch", "C_QuestLog.RemoveQuestWatch", "C_QuestLog.GetQuestWatchType",
  "C_SuperTrack.GetSuperTrackedQuestID", "C_CurrencyInfo.GetCoinTextureString",
  -- gossip, books, mail
  "C_GossipInfo.GetOptions", { "C_GossipInfo.GetText", "GetGossipText" }, "ItemTextGetText", "ItemTextGetItem",
  "ItemTextGetPage", "ItemTextGetCreator",
  -- units, zones, map
  "UnitGUID", "UnitName", "UnitSex", "UnitRace", "UnitClass", "UnitLevel", "UnitExists", "UnitIsUnit",
  "UnitCreatureType", "UnitClassification", "UnitIsConnected", "UnitIsDeadOrGhost", "UnitOnTaxi", "IsFlying",
  "IsInInstance", "GetInstanceInfo", "GetZoneText", "GetRealZoneText", "GetSubZoneText", "GetRealmName",
  "GetMaxPlayerLevel", "RequestTimePlayed", "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo",
  "C_Map.GetPlayerMapPosition", "C_MapExplorationInfo.GetExploredMapTextures",
  -- group and chat
  "IsInGroup", "IsInRaid", "GetNumGroupMembers", "GetNumSubgroupMembers", "GetRaidRosterInfo", "SendChatMessage",
  "DoEmote",
  -- spells, items, bags
  { "IsPlayerSpell", "IsSpellKnown" }, { "C_Spell.GetSpellInfo", "GetSpellInfo" }, "C_Spell.GetSpellName",
  "C_Spell.GetSpellTexture", "SpellIsTargeting", { "SpellCanTargetItem", "SpellCanTargetItemID" },
  "C_TooltipInfo.GetBagItem", { "C_Item.GetItemInfoInstant", "GetItemInfoInstant" },
  { "C_Item.EquipItemByName", "EquipItemByName" }, "C_Item.GetItemQualityColor", "GetInventoryItemLink",
  { "C_Container.GetContainerNumSlots", "GetContainerNumSlots" },
  { "C_Container.GetContainerItemLink", "GetContainerItemLink" },
  { "C_Container.GetContainerItemID", "GetContainerItemID" }, "C_Container.GetContainerItemInfo",
  "C_Container.GetContainerNumFreeSlots", "C_Container.GetBagName",
  -- the professions' places (the backpack's tabs, H37)
  "C_TradeSkillUI.IsNearProfessionSpellFocus", "Enum.Profession",
  -- the group's progress on a quest (the window's objectives, H40)
  "C_TooltipInfo.GetQuestPartyProgress", "Enum.TooltipDataLineType",
  -- key bindings and modifiers
  "GetBindingAction", "GetBindingKey", "GetBindingText", "GetCurrentBindingSet", "SetBinding", "SaveBindings",
  "IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown", "IsMouselooking",
  -- gamepad (the emote wheel's stick, H33-H35)
  "C_GamePad.IsEnabled", "C_GamePad.GetActiveDeviceID", "C_GamePad.GetDeviceMappedState",
}

-- Events the addon registers.
Check.EVENTS = {
  "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "ADDON_LOADED", "BAG_UPDATE_DELAYED", "GOSSIP_CLOSED",
  "GOSSIP_SHOW", "GROUP_ROSTER_UPDATE", "ITEM_TEXT_CLOSED", "ITEM_TEXT_READY", "PLAYER_CONTROL_GAINED",
  "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_LOGIN", "PLAYER_LOGOUT",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_SOFT_INTERACT_CHANGED", "QUEST_ACCEPTED",
  "QUEST_COMPLETE", "QUEST_DETAIL", "QUEST_FINISHED", "QUEST_GREETING", "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE",
  "QUEST_PROGRESS", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_WATCH_LIST_CHANGED", "SPELLS_CHANGED",
  "SUPER_TRACKING_CHANGED", "TIME_PLAYED_MSG", "UNIT_CONNECTION", "UNIT_QUEST_LOG_CHANGED", "UPDATE_MOUSEOVER_UNIT",
  "VOICE_CHAT_TTS_PLAYBACK_FAILED", "VOICE_CHAT_TTS_PLAYBACK_FINISHED", "VOICE_CHAT_TTS_PLAYBACK_STARTED",
  "ZONE_CHANGED_NEW_AREA",
}

-- Frame templates, with the frame type each one is created on.
Check.TEMPLATES = {
  BackdropTemplate = "Frame", DefaultPanelFlatTemplate = "Frame", GameTooltipTemplate = "GameTooltip",
  InsetFrameTemplate = "Frame", PortraitFrameTemplate = "Frame", SecureActionButtonTemplate = "Button",
  UICheckButtonTemplate = "CheckButton", UIPanelButtonTemplate = "Button",
  UIPanelCloseButton = "Button", UIPanelScrollFrameTemplate = "ScrollFrame",
}

-- Atlases; a name ending in "_" is counted: the addon asks for it with a number of wedges (2 to 12).
Check.ATLASES = {
  "checkbox-minimal", "checkmark-minimal", "checkmark-minimal-disabled", "questlog-icon-setting", "Radial_Wheel_BG",
  "Radial_Wheel_Icon_Close", "Radial_Wheel_Select_Pointer",
  "Radial_Wheel_Select_Wedge_Count_",
}
local COUNTS = { 2, 12 }

-- The game's textures the addon draws (its own media are in its folder).
Check.TEXTURES = {
  "Interface\\Buttons\\ButtonHilight-Square", "Interface\\Buttons\\CheckButtonHilight",
  "Interface\\Buttons\\UI-ActionButton-Border", "Interface\\Buttons\\UI-CheckBox-Check",
  "Interface\\Buttons\\UI-CheckBox-Down", "Interface\\Buttons\\UI-CheckBox-Highlight",
  "Interface\\Buttons\\UI-CheckBox-Up", "Interface\\Buttons\\UI-Common-MouseHilight",
  "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Interface\\Buttons\\UI-OptionsButton",
  "Interface\\Buttons\\UI-Quickslot2", "Interface\\CharacterFrame\\TempPortraitAlphaMask",
  "Interface\\Collections\\CollectionsBackgroundTile",
  "Interface\\Common\\UI-TooltipDivider-Transparent", "Interface\\Common\\WhiteIconFrame",
  "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", "Interface\\GossipFrame\\AvailableQuestIcon",
  "Interface\\GossipFrame\\GossipGossipIcon", "Interface\\Icons\\INV_Enchant_Disenchant",
  "Interface\\Icons\\INV_Misc_ArmorKit_17", "Interface\\Icons\\INV_Misc_Book_09", "Interface\\Icons\\INV_Misc_Food_15",
  "Interface\\Icons\\INV_Misc_Gear_01", "Interface\\Icons\\INV_Misc_Map_01", "Interface\\Icons\\INV_Misc_Note_01",
  "Interface\\Icons\\INV_Misc_Note_02", "Interface\\Icons\\Spell_Fire_FlameBlades",
  "Interface\\Icons\\Spell_Holy_ElunesGrace", "Interface\\Icons\\Spell_Holy_HolyBolt",
  "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
  "Interface\\Icons\\Trade_Alchemy", "Interface\\Icons\\Trade_BlackSmithing", "Interface\\Icons\\Trade_Engineering",
  "Interface\\Icons\\Trade_Engraving", "Interface\\Icons\\Trade_Fishing", "Interface\\Icons\\Trade_Tailoring",
  "Interface\\Minimap\\MiniMap-TrackingBorder",
  "Interface\\Minimap\\UI-Minimap-Background", "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
  "Interface\\QuestFrame\\UI-QuestTitleHighlight", "Interface\\SpellBook\\SpellBook-SkillLineTab",
  "Interface\\TargetingFrame\\UI-StatusBar", "Interface\\Tooltips\\UI-Tooltip-Background",
  "Interface\\Tooltips\\UI-Tooltip-Border", "Interface\\WorldMap\\UI-QuestBlob-Inside",
  "Interface\\WorldMap\\UI-QuestBlob-Outside",
}

local function resolve(name)
  local value = _G
  for part in name:gmatch("[^%.]+") do
    if type(value) ~= "table" then
      return nil
    end
    value = value[part]
  end
  return value
end

local function hasGlobal(entry)
  if type(entry) == "table" then
    for _, name in ipairs(entry) do
      if resolve(name) ~= nil then
        return true
      end
    end
    return false
  end
  return resolve(entry) ~= nil
end

local probe -- a frame of our own: events are registered on it, then dropped at once
local templates = {} -- template -> true/false: a frame made from a template stays, so each one is made once

local function hasEvent(event)
  local utils = C_EventUtils -- luacheck: ignore 113 (probed: Retail's event validation, maybe absent)
  if type(utils) == "table" and type(utils.IsEventValid) == "function" then
    local ok, valid = pcall(utils.IsEventValid, event)
    if ok then
      return valid == true
    end
  end
  probe = probe or CreateFrame("Frame")
  if probe:IsEventRegistered(event) then
    return true
  end
  local ok, result = pcall(probe.RegisterEvent, probe, event)
  if ok and result ~= false then
    probe:UnregisterEvent(event)
    return true
  end
  return false
end

local function hasTemplate(template, kind)
  if templates[template] == nil then
    local ok, f = pcall(CreateFrame, kind, nil, UIParent, template)
    if ok and f then
      f:Hide()
    end
    templates[template] = ok and f ~= nil
  end
  return templates[template]
end

local function hasAtlas(atlas)
  local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
  return ok and info ~= nil
end

local function hasTexture(path)
  local ok, id = pcall(GetFileIDFromPath, path) -- luacheck: ignore 113 (probed before the call)
  return ok and id ~= nil
end

local function sorted(set)
  local list = {}
  for name in pairs(set) do
    list[#list + 1] = name
  end
  table.sort(list)
  return list
end

-- Runs every check. Returns the result stored in ForeverSpeechDB.check: { build, interface, at, total,
-- missing = { "kind name", ... }, unchecked = { kind = why }, counted = { atlas = { counts it has } } }.
function Check.Run()
  local version, build, _, interface = GetBuildInfo()
  local missing, unchecked, counted, total = {}, {}, {}, 0
  local function count(kind, name, ok)
    total = total + 1
    if not ok then
      missing[#missing + 1] = kind .. " " .. name
    end
  end
  for _, entry in ipairs(Check.GLOBALS) do
    count("global", type(entry) == "table" and table.concat(entry, "|") or entry, hasGlobal(entry))
  end
  for _, event in ipairs(Check.EVENTS) do
    count("event", event, hasEvent(event))
  end
  for _, template in ipairs(sorted(Check.TEMPLATES)) do
    count("template", template, hasTemplate(template, Check.TEMPLATES[template]))
  end
  if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
    for _, atlas in ipairs(Check.ATLASES) do
      if atlas:sub(-1) == "_" then
        local found = {}
        for n = COUNTS[1], COUNTS[2] do
          if hasAtlas(atlas .. n) then
            found[#found + 1] = n
          end
        end
        counted[atlas] = found
        count("atlas", atlas .. "8", hasAtlas(atlas .. "8")) -- the wheel has 8 wedges
      else
        count("atlas", atlas, hasAtlas(atlas))
      end
    end
  else
    unchecked.atlas = "no C_Texture.GetAtlasInfo"
  end
  if type(GetFileIDFromPath) == "function" then -- luacheck: ignore 113 (probed)
    for _, path in ipairs(Check.TEXTURES) do
      count("texture", path, hasTexture(path))
    end
  else
    unchecked.texture = "no GetFileIDFromPath"
  end
  local result = { build = tostring(version) .. "." .. tostring(build), interface = interface, total = total,
                   at = date("%Y-%m-%d %H:%M"), missing = missing, unchecked = unchecked, counted = counted }
  ForeverSpeechDB.check = result
  H.Trace("check: build %s, %d checked, %d missing", result.build, total, #missing)
  return result
end

local function report(result, detail)
  if #result.missing == 0 then
    H.Print("game check (build %s): all %d names found", result.build, result.total)
  else
    H.Print("game check (build %s): %d of %d names missing%s", result.build, #result.missing, result.total,
      detail and ":" or " (/fs check for the list)")
  end
  if detail then
    for _, line in ipairs(result.missing) do
      H.Print("  %s", H.Escape(line))
    end
    for kind, why in pairs(result.unchecked) do
      H.Print("  %s not checked: %s", kind, why)
    end
  end
end

-- Once per client build, quietly: a chat line only when something is missing.
local function auto()
  if InCombatLockdown and InCombatLockdown() then
    H.Trace("check: in combat, left for the next login")
    return
  end
  local version, build = GetBuildInfo()
  local last = ForeverSpeechDB.check
  if last and last.build == tostring(version) .. "." .. tostring(build) then
    return
  end
  local result = Check.Run()
  if #result.missing > 0 then
    report(result, false)
  end
end

local scheduled = false
H.RegisterEvent("PLAYER_ENTERING_WORLD", function()
  if not scheduled then
    scheduled = true
    C_Timer.After(DELAY, auto)
  end
end)

H.RegisterCommand("check", function()
  if InCombatLockdown and InCombatLockdown() then
    H.Print("game check: after the fight")
    return
  end
  report(Check.Run(), true)
end, "check - which functions, events, templates, atlases and textures of the game the addon finds")
