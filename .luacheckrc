-- luacheck config: WoW addon (Lua 5.1) + busted tests.
std = "lua51"
max_line_length = 120
codes = true

exclude_files = { ".claude/", ".luarocks/", ".venv/", ".venv-voices/", ".data/", "data/", ".backups/", "dist/" }

-- Globals owned by the addon (TOC SavedVariables, generated index, slash command registration).
globals = {
  "ForeverSpeech", "ForeverSpeechDB", "ForeverSpeechCaptures", "ForeverSpeechIndex", "ForeverSpeechGameVoices",
 
  "SLASH_FOREVERSPEECH1", "SlashCmdList",
  -- key bindings (2026-10-21, Bindings.xml): the names the key binding UI reads
  "BINDING_HEADER_FOREVERSPEECH", "BINDING_NAME_FOREVERSPEECH_PLAY", "BINDING_NAME_FOREVERSPEECH_NEXT",
  "BINDING_NAME_FOREVERSPEECH_STOP", "BINDING_NAME_FOREVERSPEECH_EMOTEWHEEL",
}

-- WoW API used by the addon. Add names here only once their existence on Forever is verified or probed.
read_globals = {
  "APIDocumentation", "C_AddOns", "C_CVar", "C_Map", "C_Sound", "C_Timer", "C_VoiceChat",
  "ChatFontNormal", "CreateFrame", "DEFAULT_CHAT_FRAME", "Enum", "GetBuildInfo", "GetCVar",
  "GetLocale", "GetMouseFoci", "GetMouseFocus", "GetNumQuestChoices", "GetNumQuestRewards",
  "GetObjectiveText", "GetQuestID", "GetQuestItemInfo", "GetQuestText", "GetRewardMoney",
  "GetRewardXP", "GetSubZoneText", "GetTime", "GetTitleText", "GetZoneText", "LoadAddOn",
  "PlaySoundFile", "QuestFrame", "QuestFrameDetailPanel", "Screenshot", "StopSound", "UIParent",
  "UnitClass", "UnitClassification", "UnitCreatureType", "UnitExists", "UnitGUID", "UnitIsUnit",
  "UnitName", "UnitRace", "UnitSex", "WOW_PROJECT_ID", "date", "hooksecurefunc", "time",
  -- phase 1 UI (S4 names; quest log reward functions are probed at runtime, see QuestData)
  "C_CurrencyInfo", "C_QuestLog", "GameTooltip", "GetNumQuestLogChoices", "GetNumQuestLogRewards",
  "GetQuestLogChoiceInfo", "GetQuestLogQuestText", "GetQuestLogRewardInfo", "GetQuestLogRewardMoney",
  "GetQuestLogRewardXP", "QuestFrameAcceptButton", "QuestFrameDeclineButton", "QuestLogQuests_Update",
  "QuestMapFrame", "QuestMapFrame_ShowQuestDetails", "QuestScrollFrame",
  "PlaySound", "SOUNDKIT", "Minimap", "GetCursorPosition", "ReloadUI",
  -- fishing mode (2026-10-13, unverified on Forever: every call is probed or wrapped)
  "C_GamePad", "GetBindingAction", "GetBindingKey", "GetBindingText", "GetCurrentBindingSet", "IsAltKeyDown",
  "IsControlKeyDown", "IsMouselooking", "IsShiftKeyDown", "SaveBindings", "SetBinding",
  "InCombatLockdown", "IsPlayerSpell", "IsSpellKnown", "C_Spell", "GetSpellInfo", "C_Item", "GetItemInfoInstant",
  "C_Container", "GetContainerNumSlots", "GetContainerItemLink", "GetInventoryItemLink", "EquipItemByName",
  -- quick emotes (2026-10-13)
  "DoEmote",
  -- interface look (2026-10-21, unverified on Forever: T43; atlases probed through C_Texture.GetAtlasInfo)
  "C_Texture", "BackdropTemplateMixin",
  -- the options in the game's own panel (2026-10-21, Settings API, unverified on Forever: T46)
  "HideUIPanel",
  -- bag side tabs and disenchant mode (2026-10-18, unverified on Forever: in-game check H18, every call is probed)
  "EventRegistry", "SpellIsTargeting", "C_TooltipInfo", "ITEM_DISENCHANT_ANY_SKILL",
  "ITEM_DISENCHANT_MIN_SKILL", "ITEM_DISENCHANT_NOT_DISENCHANTABLE", "SpellCanTargetItem", "SpellCanTargetItemID", "ItemLocation",
  "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame_Update", "GetContainerItemID", "UpdateContainerFrameAnchors",
  -- the professions' places (2026-11-05, unverified on Forever: H37)
  "C_TradeSkillUI",
  "GetQuestDifficultyColor",
  "QuestDifficultyColors",
  "RequestTimePlayed",
  "GetMaxPlayerLevel",
  "IsInGroup",
  "IsInRaid",
  "LE_PARTY_CATEGORY_INSTANCE",
  "SendChatMessage",
  "GetNumGroupMembers",
  "GetNumSubgroupMembers",
  "GetRaidRosterInfo",
  "UnitIsConnected",
  "GetInstanceInfo",
  "InCinematic",
  "NUM_CHAT_WINDOWS",
  -- money footer (2026-10-13)
  -- turn-in (2026-10-06, unverified on Forever: spike S9; every call is probed or wrapped)
  "GetQuestReward", "GetRewardText", "QuestFrameCompleteQuestButton",
  -- "Terminer et lire" (2026-10-10, unverified on Forever: the button is placed only if the frames exist)
  "QuestFrameCancelButton",
  -- logbook (2026-10-10, unverified on Forever: probed and wrapped in QuestData.Tracked)
  "C_SuperTrack",
  -- the game's NPC voices muted with quest NPCs (2026-10-10; MuteSoundFile verified, S10; the others are wrapped)
  "MuteSoundFile", "UnmuteSoundFile", "C_GossipInfo", "GetNumAvailableQuests", "GetNumActiveQuests",
  "GetActiveTitle", "IsQuestComplete",
  -- objective progress bars (2026-10-10, unverified on Forever: wrapped)
  "GetQuestProgressBarPercent",
  -- zone introductions of Elise (2026-10-11, unverified on Forever: spike S12; each one is probed before use)
  "GetRealZoneText", "GetRealmName", "IsFlying", "IsInInstance", "UnitIsDeadOrGhost", "UnitOnTaxi",
  -- level-up lines of Elise (2026-10-11, unverified: PLAYER_LEVEL_UP)
  "UnitLevel",
  -- world map button (2026-10-12; WorldMapFrame exists, S4; GetMapID and OnMapChanged probed)
  "WorldMapFrame", "C_MapExplorationInfo",
  -- NPC dialogue capture (2026-10-10, unverified on Forever: spike S11; wrapped)
  "GetGossipText",
  -- 2026-10-21, unverified on Forever (docs/ingame/queue.md), every call wrapped: secret values, ducking, books
  "issecretvalue", "SetCVar", "ItemTextGetText", "ItemTextGetItem", "ItemTextGetPage", "ItemTextGetCreator",
  "MailFrame", "LOCALIZED_CLASS_NAMES_FEMALE",
}

files["addon/ForeverSpeech/data/index.lua"] = { max_line_length = false }
files["addon/ForeverSpeech/data/game_voices.lua"] = { max_line_length = false }

files["tests/"] = {
  std = "+busted",
  globals = {
    "_G", "QuestLog_Update", "GetQuestReward", "C_VoiceChat", "C_Sound", "UnitGUID", "UnitName", "UnitSex", "UnitCreatureType",
    "GetQuestID", "GetQuestText", "GetTitleText", "GetObjectiveText", "GetZoneText", "StopSound",
    "QuestFrame", "QuestFrameDetailPanel", "QuestFrameAcceptButton", "QuestFrameDeclineButton",
    "QuestObjectiveTracker", "QuestScrollFrame", "QuestLogQuests_Update", "QuestMapFrame",
    "QuestMapFrame_ShowQuestDetails", "GetNumQuestChoices", "GetQuestItemInfo", "GetRewardXP",
    "C_QuestLog", "GetQuestLogQuestText", "accepted", "questLogRows", "Minimap", "SOUNDKIT", "PlaySound",
    "GetCursorPosition", "ReloadUI", "AddonCompartmentFrame", "C_SuperTrack",
    "QuestFrameRewardPanel", "QuestFrameCompleteQuestButton", "QuestFrameCancelButton",
    "MuteSoundFile", "UnmuteSoundFile", "C_GossipInfo", "GetGossipText",
    "issecretvalue", "SetCVar", "GetCVar", "C_CVar", "IsInInstance", "ItemTextGetText", "ItemTextGetItem",
    "ItemTextGetPage", "ItemTextGetCreator", "MailFrame", "UnitClass", "UnitRace", "BINDING_NAME_FOREVERSPEECH_PLAY",
  },
  read_globals = { "newproxy" },
}
