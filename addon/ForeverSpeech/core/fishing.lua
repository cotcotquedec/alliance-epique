-- ForeverSpeech: fishing mode (2026-10-13), the first switch of the side tabs (ui/side_tabs.lua, ui/fishing_tab.lua).
-- On: the weapons held are remembered and the fishing pole of the bags is equipped (Fishing is cast from the action
-- bars). Off: the weapons come back. Per character, kept across /reload (ForeverSpeechDB.fishing[<character>]).
-- Never in combat: equipping is left alone there.
-- Unverified on Forever: the Fishing spell IDs (Classic ranks, or Retail's single spell), whether a pole must be
-- equipped at all, C_Container / C_Item (with their Classic globals as fallback), EquipItemByName.
local H = ForeverSpeech

local Fishing = {}
H.Fishing = Fishing

-- Retail's single Fishing spell first, then the Classic ranks from the highest (Artisan to Apprentice).
local SPELL_IDS = { 131474, 18248, 7732, 7731, 7620 }
local MAIN_HAND, OFF_HAND = 16, 17
local WEAPON_CLASS, POLE_SUBCLASS = 2, 20 -- Enum.ItemClass.Weapon, Enum.ItemWeaponSubclass.Fishingpole
local BAGS = 4 -- backpack (0) and the four bag slots
local OFF_HAND_DELAY = 0.5 -- seconds between the main hand and the off hand: an item swap is not immediate

local listeners = {}

local function character()
  local name = UnitName and UnitName("player") or "?"
  local realm = GetRealmName and GetRealmName() or "?"
  return tostring(name) .. "-" .. tostring(realm)
end

local function state()
  if not ForeverSpeechDB then -- before the SavedVariables are loaded
    return {}
  end
  ForeverSpeechDB.fishing = ForeverSpeechDB.fishing or {}
  local key = character()
  ForeverSpeechDB.fishing[key] = ForeverSpeechDB.fishing[key] or {}
  return ForeverSpeechDB.fishing[key]
end

local function notify()
  for _, fn in ipairs(listeners) do
    local ok, err = pcall(fn)
    if not ok then
      H.Debug("fishing listener error: %s", tostring(err))
    end
  end
end

-- fn() after each change of the mode, and when combat starts or ends.
function Fishing.OnChange(fn)
  listeners[#listeners + 1] = fn
end

function Fishing.InCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function known(id)
  if IsPlayerSpell and IsPlayerSpell(id) then
    return true
  end
  return IsSpellKnown and IsSpellKnown(id) or false
end

-- The Fishing spell the character knows, nil if none.
function Fishing.SpellID()
  for _, id in ipairs(SPELL_IDS) do
    if known(id) then
      return id
    end
  end
  return nil
end

-- Name and icon of the known Fishing spell (C_Spell on recent clients, GetSpellInfo on older ones).
function Fishing.SpellInfo()
  local id = Fishing.SpellID()
  if not id then
    return nil
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    if info then
      return id, info.name, info.iconID
    end
  end
  if GetSpellInfo then
    local name, _, icon = GetSpellInfo(id)
    return id, name, icon
  end
  return id
end

local function itemClass(item)
  local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not (getInfo and item) then
    return nil
  end
  local _, _, _, _, _, classID, subclassID = getInfo(item)
  return classID, subclassID
end

local function isPole(item)
  local classID, subclassID = itemClass(item)
  return classID == WEAPON_CLASS and subclassID == POLE_SUBCLASS
end

local function bagSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag) or 0
  end
  return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function bagItem(bag, slot)
  if C_Container and C_Container.GetContainerItemLink then
    return C_Container.GetContainerItemLink(bag, slot)
  end
  return GetContainerItemLink and GetContainerItemLink(bag, slot)
end

local function equipped(slot)
  return GetInventoryItemLink and GetInventoryItemLink("player", slot)
end

-- The first fishing pole of the bags (its link), nil if none.
function Fishing.FindPole()
  for bag = 0, BAGS do
    for slot = 1, bagSlots(bag) do
      local link = bagItem(bag, slot)
      if link and isPole(link) then
        return link
      end
    end
  end
  return nil
end

function Fishing.PoleEquipped()
  return isPole(equipped(MAIN_HAND))
end

-- A pole in the hand or in the bags.
function Fishing.HasPole()
  return Fishing.PoleEquipped() or Fishing.FindPole() ~= nil
end

local function equip(item, slot)
  local fn = (C_Item and C_Item.EquipItemByName) or EquipItemByName
  if not fn then
    return false
  end
  local ok, err = pcall(fn, item, slot)
  H.Trace("fishing: equip %s slot=%s ok=%s %s", item, slot, ok, err)
  return ok
end

function Fishing.IsOn()
  return state().on == true
end

-- Starts fishing mode. Returns ok, reason ("combat", "unknown", "nopole").
function Fishing.Start()
  if Fishing.InCombat() then
    return false, "combat"
  end
  if not Fishing.SpellID() then
    return false, "unknown"
  end
  local s = state()
  if not Fishing.PoleEquipped() then
    local pole = Fishing.FindPole()
    if not pole then
      return false, "nopole"
    end
    s.main, s.off = equipped(MAIN_HAND), equipped(OFF_HAND)
    equip(pole, MAIN_HAND)
  end
  s.on = true
  H.Trace("fishing: on main=%s off=%s", s.main, s.off)
  notify()
  return true
end

-- Ends fishing mode: the weapons held before come back (the off hand a moment after the main hand). Returns ok,
-- reason ("combat").
function Fishing.Stop()
  if Fishing.InCombat() then
    return false, "combat"
  end
  local s = state()
  local main, off = s.main, s.off
  if main then
    equip(main, MAIN_HAND)
  end
  if off then
    C_Timer.After(OFF_HAND_DELAY, function()
      if not Fishing.InCombat() then
        equip(off, OFF_HAND)
      end
    end)
  end
  s.on, s.main, s.off = false, nil, nil
  H.Trace("fishing: off main=%s off=%s", main, off)
  notify()
  return true
end

function Fishing.Toggle()
  if Fishing.IsOn() then
    return Fishing.Stop()
  end
  return Fishing.Start()
end

local MESSAGES = { combat = "FISHING_COMBAT", unknown = "FISHING_UNKNOWN", nopole = "FISHING_NO_POLE" }

-- Toggles and says why in the chat when something is in the way.
function Fishing.ToggleAndReport()
  local _, reason = Fishing.Toggle()
  if reason then
    H.Print("%s", H.L[MESSAGES[reason]])
  end
end

for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
  H.TryRegisterEvent(event, notify)
end
-- learning Fishing, or a pole coming into or leaving the bags or the hands, shows or hides the tab
for _, event in ipairs({ "SPELLS_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
  H.TryRegisterEvent(event, notify)
end

H.RegisterCommand("fish", function()
  Fishing.ToggleAndReport()
end, "fish - fishing mode on/off (pole equipped, weapons back)")
