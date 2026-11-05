-- ForeverSpeech: the backpack's side tabs (2026-10-18), a bar of side tabs (ui/side_tabs.lua, bar "bag") on the left
-- edge of the frame showing the backpack: the combined bag (ContainerFrameCombinedBags) or the separate backpack
-- frame (ContainerFrameN holding bag 0). The rule (2026-10-20): the professions' tabs go on the backpack. Fishing
-- (ui/fishing_tab.lua) on top, then one tab per crafting profession (Cooking and Tailoring on 2026-10-20, every one
-- with a window on 2026-11-05: Mining's is Smelting): secure tabs casting the profession's spell by its name (the
-- rank the character knows), which opens its window as the spellbook would; shown only to a character who knows it
-- (any rank). Greyed, still clickable, when the game says the place its recipes need is not nearby (a fire, a forge,
-- an anvil). Then Disenchant (core/disenchant.lua), a secure tab casting the spell
-- (type spell, 13262) as the spellbook would; while the cursor waits for the item, a golden border on every bag slot
-- whose item can be disenchanted. The click on the item is the game's.
-- Item buttons: EnumerateValidItems and GetBagID (Retail style), else ContainerFrameNItemM and its parent's ID
-- (Classic style). Refresh: the frames' OnShow, UpdateItems (Retail) or ContainerFrame_Update (Classic), and the
-- mode's changes. Unverified on Forever: all of it (H18, T36), the professions' places (H37, T62).
local H = ForeverSpeech
local L = H.L
local Disenchant = H.Disenchant

local ICON = "Interface\\Icons\\INV_Enchant_Disenchant"
local FRAMES, MAX_SLOTS = 13, 36 -- NUM_CONTAINER_FRAMES, the most slots of a Classic container frame
local BAR_TOP, BAR_BOTTOM = 30, 8 -- the bar's margins on the bag frame's edge
local GLOW = { 1, 0.82, 0, 0.9 }

local BagTabs = {}
H.BagTabs = BagTabs

local glows = setmetatable({}, { __mode = "k" }) -- item button → the addon's border texture on it

local function frames()
  local list = {}
  if ContainerFrameCombinedBags then
    list[#list + 1] = ContainerFrameCombinedBags
  end
  for i = 1, FRAMES do
    local f = _G["ContainerFrame" .. i]
    if f then
      list[#list + 1] = f
    end
  end
  return list
end

local function frameBag(f)
  if f.GetBagID then
    local ok, bag = pcall(f.GetBagID, f)
    if ok and bag ~= nil then
      return bag
    end
  end
  return f.GetID and f:GetID() or nil
end

-- True for the frame showing the backpack (bag 0).
function BagTabs.IsBackpackFrame(f)
  if ContainerFrameCombinedBags and f == ContainerFrameCombinedBags then
    return true
  end
  return frameBag(f) == 0
end

-- Bag and slot of an item button.
function BagTabs.Slot(button)
  local bag
  if button.GetBagID then
    local ok, value = pcall(button.GetBagID, button)
    bag = ok and value or nil
  end
  if bag == nil and button.GetParent and button:GetParent() and button:GetParent().GetID then
    bag = button:GetParent():GetID()
  end
  return bag, button.GetID and button:GetID() or nil
end

-- The shown item buttons of a bag frame.
local function buttons(f)
  local list = {}
  if f.EnumerateValidItems then
    local ok, iter, st, ctl = pcall(f.EnumerateValidItems, f)
    if ok and type(iter) == "function" then
      for _, b in iter, st, ctl do
        list[#list + 1] = b
      end
      return list
    end
  end
  local name = f.GetName and f:GetName()
  for i = 1, MAX_SLOTS do
    local b = name and _G[name .. "Item" .. i]
    if b and b:IsShown() then
      list[#list + 1] = b
    end
  end
  return list
end

local function glow(button)
  local tex = glows[button]
  if not tex then
    tex = button:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(GLOW[1], GLOW[2], GLOW[3], GLOW[4])
    tex:SetPoint("CENTER", button, "CENTER", 0, 0)
    local w = button.GetWidth and button:GetWidth() or 37
    tex:SetSize(w * 1.8, w * 1.8) -- the border art fills the middle of its texture
    glows[button] = tex
  end
  return tex
end

-- Shows or hides the border of every shown bag slot, per the mode and the item.
function BagTabs.Refresh()
  local on = Disenchant.IsOn()
  for _, f in ipairs(frames()) do
    if f:IsShown() then
      for _, b in ipairs(buttons(f)) do
        local bag, slot = BagTabs.Slot(b)
        local can = on and Disenchant.CanSlot(bag, slot)
        if can then
          glow(b):Show()
        elseif glows[b] then
          glows[b]:Hide()
        end
      end
    end
  end
end

-- True when the slot's border is shown (tests, /fs debug).
function BagTabs.IsLit(button)
  return glows[button] ~= nil and glows[button]:IsShown()
end

-- The Blizzard refresh runs first; ours just after it, once per frame.
local pending = false
local function refreshSoon()
  if pending then
    return
  end
  pending = true
  C_Timer.After(0, function()
    pending = false
    BagTabs.Refresh()
    H.SideTabs.Update() -- the secure tab follows the bag's screen position, known once it is laid out
  end)
end

local function onShow(f)
  local bar = H.SideTabs.Bar("bag")
  if BagTabs.IsBackpackFrame(f) then
    H.SideTabs.Attach(f, "bag", BAR_TOP, BAR_BOTTOM)
  elseif bar and H.SideTabs.Owner("bag") == f then -- Classic reuses its frames: this one now shows another bag
    bar:Hide()
  end
  refreshSoon()
end

local function install()
  for _, f in ipairs(frames()) do
    f:HookScript("OnShow", onShow)
    if type(f.UpdateItems) == "function" then
      hooksecurefunc(f, "UpdateItems", refreshSoon)
    end
    f:HookScript("OnSizeChanged", refreshSoon)
    if f:IsShown() then
      onShow(f)
    end
  end
  if type(ContainerFrame_Update) == "function" then
    hooksecurefunc("ContainerFrame_Update", refreshSoon)
  end
  if type(UpdateContainerFrameAnchors) == "function" then -- the bags moved (H18: exists on Forever)
    hooksecurefunc("UpdateContainerFrameAnchors", refreshSoon)
  end
  H.Trace("bag: frames=%s combined=%s classic=%s", #frames(), ContainerFrameCombinedBags ~= nil,
    type(ContainerFrame_Update) == "function")
end

H.WhenAvailable(function()
  return ContainerFrame1 ~= nil or ContainerFrameCombinedBags ~= nil
end, install)

Disenchant.OnChange(function()
  refreshSoon()
  H.SideTabs.Update()
end)

-- The crafting professions, in the spellbook's order (primary, then secondary): the spell that opens the window, by
-- rank (Apprentice to Artisan, VMaNGOS spell_template; the first is also Retail's), and a fallback icon. Mining's
-- window is Smelting's (2656). Herbalism and Skinning have no window; Fishing has its own tab.
-- focus: the game's profession (Enum.Profession) whose recipes need a place nearby, per VMaNGOS requiresSpellFocus:
-- every Cooking recipe a fire, 11 of the 12 smelting recipes a forge, 234 of the 250 Blacksmithing recipes an anvil
-- (Engineering, 101 of 169, and the others, a few, are left alone); place: what the tooltip says is missing.
local PROFESSIONS = {
  { key = "alchemy", ids = { 2259, 3101, 3464, 11611 }, icon = "Interface\\Icons\\Trade_Alchemy" },
  { key = "blacksmithing", ids = { 2018, 3100, 3538, 9785 }, icon = "Interface\\Icons\\Trade_BlackSmithing",
    focus = "Blacksmithing", place = "PLACE_ANVIL" },
  { key = "enchanting", ids = { 7411, 7412, 7413, 13920 }, icon = "Interface\\Icons\\Trade_Engraving" },
  { key = "engineering", ids = { 4036, 4037, 4038, 12656 }, icon = "Interface\\Icons\\Trade_Engineering" },
  { key = "leatherworking", ids = { 2108, 3104, 3811, 10662 }, icon = "Interface\\Icons\\INV_Misc_ArmorKit_17" },
  { key = "tailoring", ids = { 3908, 3909, 3910, 12180 }, icon = "Interface\\Icons\\Trade_Tailoring" },
  { key = "smelting", ids = { 2656 }, icon = "Interface\\Icons\\Spell_Fire_FlameBlades", focus = "Mining",
    place = "PLACE_FORGE" },
  { key = "cooking", ids = { 2550, 3102, 3413, 18260 }, icon = "Interface\\Icons\\INV_Misc_Food_15",
    focus = "Cooking", place = "PLACE_FIRE" },
  { key = "firstaid", ids = { 3273, 3274, 7924, 10846 }, icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
}
BagTabs.PROFESSIONS = PROFESSIONS

local function knownSpell(id)
  if IsPlayerSpell and IsPlayerSpell(id) then
    return true
  end
  return IsSpellKnown and IsSpellKnown(id) or false
end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then
    return C_Spell.GetSpellName(id)
  end
  return GetSpellInfo and (GetSpellInfo(id)) or nil
end

local function spellIcon(id)
  return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) or nil
end

local function knownProfession(p)
  for _, id in ipairs(p.ids) do
    if knownSpell(id) then
      return true
    end
  end
  return false
end

-- Whether the place a profession's recipes need is nearby, as the game says (C_TradeSkillUI.IsNearProfessionSpellFocus,
-- Retail's; unverified on Forever, H37): true or false; nil when the game cannot say (no such function or profession,
-- an error, a secret value): the tab is then never greyed.
function BagTabs.Near(p)
  local api = C_TradeSkillUI and C_TradeSkillUI.IsNearProfessionSpellFocus
  local profession = p.focus and Enum and Enum.Profession and Enum.Profession[p.focus]
  if type(api) ~= "function" or profession == nil then
    return nil
  end
  local ok, value = pcall(api, profession)
  if not ok or type(value) ~= "boolean" then
    return nil
  end
  return value
end

for _, p in ipairs(PROFESSIONS) do
  local name = spellName(p.ids[1])
  H.SideTabs.Register({
    key = p.key,
    bar = "bag",
    icon = spellIcon(p.ids[1]) or p.icon,
    secure = { type = "spell", spell = name or p.ids[1] }, -- by its name: the rank the character knows
    shown = function()
      if ForeverSpeechDB and ForeverSpeechDB.professionTabs == false then
        return false
      end
      return knownProfession(p)
    end,
    dimmed = p.focus and function() -- greyed, the click still opens the window
      return BagTabs.Near(p) == false
    end or nil,
    locked = Disenchant.InCombat,
    onClick = function() end,
    tooltip = function(tooltip)
      tooltip:SetText(name or p.key)
      tooltip:AddLine(L.PROFESSION_CLICK, 1, 1, 1, true)
      if p.focus and BagTabs.Near(p) == false then
        tooltip:AddLine(L[p.place], 1, 0.3, 0.3, true)
      end
    end,
  })
end

-- Nothing tells when the player walks up to a fire: while the backpack's bar is shown, the places are asked again
-- twice a second, and the tabs redrawn when one changes.
local POLL = 0.5
local nearNow = {} -- profession key → the last answer (true, false, or nil: unknown)
local poll = CreateFrame("Frame")
local since = 0
poll:SetScript("OnUpdate", function(_, elapsed)
  since = since + (elapsed or 0)
  if since < POLL then
    return
  end
  since = 0
  local bar = H.SideTabs.Bar("bag")
  if not (bar and bar:IsVisible()) then
    return
  end
  local changed = false
  for _, p in ipairs(PROFESSIONS) do
    if p.focus and knownProfession(p) then
      local value = BagTabs.Near(p)
      if value ~= nearNow[p.key] then
        nearNow[p.key] = value
        changed = true
        H.Trace("bag: %s near=%s", p.key, value)
      end
    end
  end
  if changed then
    H.SideTabs.Update()
  end
end)

H.SideTabs.Register({
  key = "disenchant",
  bar = "bag",
  icon = ICON,
  secure = { type = "spell", spell = Disenchant.SPELL_ID },
  isOn = Disenchant.IsOn, -- lit while the spell waits for its item
  shown = function()
    local wanted = not ForeverSpeechDB or ForeverSpeechDB.disenchantTab ~= false
    return wanted and Disenchant.Known()
  end,
  locked = Disenchant.InCombat,
  onClick = Disenchant.Armed,
  tooltip = function(tooltip)
    tooltip:SetText(Disenchant.SpellName() or L.DISENCHANT)
    tooltip:AddLine(L.DISENCHANT_CLICK_ON, 1, 1, 1, true)
  end,
})
