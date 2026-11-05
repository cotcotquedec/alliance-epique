-- ForeverSpeech: disenchant mode (2026-10-18), the backpack's side tab (ui/bag_tabs.lua). A click on the tab casts
-- Disenchant as the spellbook would (a secure tab): while the cursor waits for the item, every bag slot holding an
-- item that can be disenchanted stands out; the click on the item is the game's. Shown only to a character who knows
-- Disenchant; not in combat. (A first version, the same day, lit the items on a switch and put a secure button over
-- the hovered one: the player wanted the tab to be the spell.)
-- What can be disenchanted: the item's tooltip says it (TooltipSays). A first version read the Forever Database
-- (VMaNGOS disenchant_id), which does not know Forever's own items: most greens of its quests (H18).
-- Unverified on Forever: the Disenchant spell ID (13262, the same in Classic and Retail; H18), C_Container.
local H = ForeverSpeech

local Disenchant = {}
H.Disenchant = Disenchant

Disenchant.SPELL_ID = 13262
local BAGS = 4 -- backpack (0) and the four bag slots

local on = false
local listeners = {}

local function notify()
  for _, fn in ipairs(listeners) do
    local ok, err = pcall(fn)
    if not ok then
      H.Debug("disenchant listener error: %s", tostring(err))
    end
  end
end

-- fn() after each change of the mode, when combat starts or ends, when the bags or the spells change.
function Disenchant.OnChange(fn)
  listeners[#listeners + 1] = fn
end

function Disenchant.InCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

function Disenchant.Known()
  local id = Disenchant.SPELL_ID
  if IsPlayerSpell and IsPlayerSpell(id) then
    return true
  end
  return IsSpellKnown and IsSpellKnown(id) or false
end

-- The spell's name in the client's language (the tooltip), or nil.
function Disenchant.SpellName()
  local id = Disenchant.SPELL_ID
  if C_Spell and C_Spell.GetSpellName then
    return C_Spell.GetSpellName(id)
  end
  return GetSpellInfo and (GetSpellInfo(id)) or nil
end

-- The game's own tooltip lines (frFR: « Peut être désenchanté », « Ne peut pas être désenchanté », « Désenchantement :
-- … requis »), the French text as a fallback when a global string is missing.
local function phrases()
  local yes = ITEM_DISENCHANT_ANY_SKILL or "Peut être désenchanté"
  local no = ITEM_DISENCHANT_NOT_DISENCHANTABLE or "Ne peut pas être désenchanté"
  local skill
  if type(ITEM_DISENCHANT_MIN_SKILL) == "string" then -- "Disenchanting requires %s (%d)": a pattern of it
    skill = ITEM_DISENCHANT_MIN_SKILL:gsub("%%%d*%$?[sd]", "\001"):gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
    skill = "^" .. skill:gsub("\001", ".-") .. "$"
  end
  return yes, no, skill
end

local scanner -- a hidden tooltip, when C_TooltipInfo is missing

-- The text lines of the tooltip of the bag's slot item (colors taken out).
local function tooltipLines(bag, slot)
  local out = {}
  if C_TooltipInfo and C_TooltipInfo.GetBagItem then
    local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if ok and type(data) == "table" and type(data.lines) == "table" then
      for _, line in ipairs(data.lines) do
        out[#out + 1] = line.leftText
      end
      return out
    end
  end
  scanner = scanner or CreateFrame("GameTooltip", nil, UIParent, "GameTooltipTemplate")
  scanner:SetOwner(UIParent, "ANCHOR_NONE")
  scanner:ClearLines()
  pcall(scanner.SetBagItem, scanner, bag, slot)
  for _, region in ipairs({ scanner:GetRegions() }) do
    if region.GetObjectType and region:GetObjectType() == "FontString" then
      out[#out + 1] = region:GetText()
    end
  end
  scanner:Hide()
  return out
end

local function plain(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- What the item's tooltip says (2026-10-18, the player's idea: the game writes it under the item): true for « Peut
-- être désenchanté » or a skill requirement (the skill is not counted: too high, the game refuses), false for « Ne
-- peut pas être désenchanté » or no such line. Unverified: C_TooltipInfo on Forever, the line for every item (T36).
function Disenchant.TooltipSays(bag, slot)
  local yes, no, skill = phrases()
  for _, text in ipairs(tooltipLines(bag, slot)) do
    if type(text) == "string" then
      text = plain(text)
      if text == no then
        return false
      end
      if text == yes or (skill and text:find(skill)) then
        return true
      end
    end
  end
  return false
end

local function itemID(bag, slot)
  if C_Container and C_Container.GetContainerItemID then
    return C_Container.GetContainerItemID(bag, slot)
  end
  return GetContainerItemID and GetContainerItemID(bag, slot) or nil
end

-- True when the item in the bag's slot can be disenchanted.
function Disenchant.CanSlot(bag, slot)
  if bag == nil or slot == nil or bag < 0 or bag > BAGS then -- the bank and the keyring are left alone
    return false
  end
  return itemID(bag, slot) ~= nil and Disenchant.TooltipSays(bag, slot)
end

-- In-game check (2026-10-18): while the tab's Disenchant targets, every bag item with what its tooltip says, in
-- ForeverSpeechDB.disenchantCheck (on disk after /reload).
local function record()
  local rows = {}
  for bag = 0, BAGS do
    local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local id = itemID(bag, slot)
      if id then
        local info = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
        rows[#rows + 1] = string.format("%d/%d id=%d quality=%s tooltip=%s", bag, slot, id,
          tostring(type(info) == "table" and info.quality or "?"), tostring(Disenchant.TooltipSays(bag, slot)))
      end
    end
  end
  if ForeverSpeechDB then
    ForeverSpeechDB.disenchantCheck = rows
    ForeverSpeechDB.disenchantCheckSource = (C_TooltipInfo and C_TooltipInfo.GetBagItem) and "C_TooltipInfo" or "scan"
  end
end

-- The count of bag items that can be disenchanted.
function Disenchant.Count()
  local n = 0
  for bag = 0, BAGS do
    local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      if Disenchant.CanSlot(bag, slot) then
        n = n + 1
      end
    end
  end
  return n
end

-- True while the Disenchant cast by the tab waits for its item (the cursor targets): the bag items light up.
function Disenchant.IsOn()
  return on
end

local function targeting()
  return SpellIsTargeting and SpellIsTargeting() and true or false
end

-- The tab was clicked: the game has cast Disenchant (the template runs the click before PostClick); while the cursor
-- targets an item, the mode is on. Polled: the client tells no event when the targeting ends.
local watch
function Disenchant.Armed()
  if not targeting() then
    return
  end
  if not on then
    on = true
    record()
    H.Trace("disenchant: targeting, %s item(s)", Disenchant.Count())
    notify()
  end
  watch = watch or CreateFrame("Frame")
  watch:SetScript("OnUpdate", function(self)
    if not targeting() then
      self:SetScript("OnUpdate", nil)
      on = false
      H.Trace("disenchant: targeting over")
      notify()
    end
  end)
end

for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "BAG_UPDATE_DELAYED" }) do
  H.TryRegisterEvent(event, notify)
end

H.RegisterCommand("disenchant", function()
  if not Disenchant.Known() then
    H.Print("%s", H.L.DISENCHANT_UNKNOWN)
  else
    H.Print(H.L.DISENCHANT_COUNT, Disenchant.Count())
  end
end, "disenchant - how many bag items can be disenchanted (the backpack's tab casts the spell)")
