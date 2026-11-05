local wow = require("tests.lua.helpers.wow")

-- An enchanter's bags: a green that can be disenchanted, a white, a Forever green needing more skill, and in the
-- second bag the first green again. Their tooltip lines, as the game writes them.
local DE_ITEM, WHITE, SKILL = 821, 25, 263402
local LINES = {
  [DE_ITEM] = { "Gilet en cuir", "Peut être désenchanté" },
  [WHITE] = { "Épée courte usée" },
  [SKILL] = { "Écharpe de chagrin", "|cffff2020Désenchantement : Enchantement (25) requis|r" },
}
local bags, combat, known, targeting

local function itemButton(bag, slot)
  local b = wow.newRegion("Button")
  b.GetBagID = function() return bag end
  b.GetID = function() return slot end
  b:Show()
  return b
end

local function retailBag()
  local f = wow.newRegion("Frame")
  f.items = { itemButton(0, 1), itemButton(0, 2), itemButton(0, 3), itemButton(1, 1) }
  f.EnumerateValidItems = function(self) return ipairs(self.items) end
  f.UpdateItems = function() end
  _G.ContainerFrameCombinedBags = f
  return f
end

local function classicBag()
  local f = wow.newRegion("Frame")
  f._name = "ContainerFrame1"
  f.GetID = function() return 0 end
  rawset(f, "EnumerateValidItems", false) -- not a Retail frame
  f.items = {}
  for i = 1, 3 do
    local b = wow.newRegion("Button")
    b._parent = f
    b.GetID = function() return i end
    rawset(b, "GetBagID", false)
    b:Show()
    _G["ContainerFrame1Item" .. i] = b
    f.items[i] = b
  end
  _G.ContainerFrame1 = f
  _G.ContainerFrame_Update = function() end
  return f
end

local function setup(opts)
  opts = opts or {}
  wow.reset()
  combat, known, targeting = false, opts.known ~= false, false
  _G.SpellIsTargeting = function() return targeting end
  bags = { [0] = { DE_ITEM, WHITE, SKILL }, [1] = { DE_ITEM } }
  wow.layout = true
  _G.ITEM_DISENCHANT_ANY_SKILL = "Peut être désenchanté"
  _G.ITEM_DISENCHANT_NOT_DISENCHANTABLE = "Ne peut pas être désenchanté"
  _G.ITEM_DISENCHANT_MIN_SKILL = "Désenchantement : %s (%d) requis"
  if opts.tooltip ~= false then
    _G.C_TooltipInfo = {
      GetBagItem = function(bag, slot)
        local id = bags[bag] and bags[bag][slot]
        local lines = {}
        for i, text in ipairs(id and LINES[id] or {}) do
          lines[i] = { leftText = text }
        end
        return { lines = lines }
      end,
    }
  end
  _G.InCombatLockdown = function() return combat end
  _G.IsPlayerSpell = function(id) return known and id == 13262 end
  _G.C_Spell = { GetSpellName = function() return "Désenchantement" end }
  _G.C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemID = function(bag, slot) return bags[bag] and bags[bag][slot] end,
  }
  local f = opts.classic and classicBag() or retailBag()
  wow.loadAddon()
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  wow.fire("PLAYER_LOGIN")
  wow.fire("PLAYER_ENTERING_WORLD")
  f:Show()
  f:GetScript("OnShow")(f)
  wow.advance(0)
  return f
end

local function lit(f)
  local out = {}
  for i, b in ipairs(f.items) do
    out[i] = ForeverSpeech.BagTabs.IsLit(b)
  end
  return out
end

-- A click on the tab: the game casts Disenchant (the cursor targets), then the tab's PostClick runs.
local function clickTab()
  local tab = ForeverSpeech.SideTabs.Tab("disenchant")
  targeting = true
  tab:GetScript("PostClick")(tab, "LeftButton", false)
  wow.advance(0)
end

-- The tooltip lines a hover on a tab writes.
local function tooltipOf(tab)
  local lines = {}
  _G.GameTooltip = {
    SetOwner = function() end,
    IsOwned = function() return false end,
    SetText = function(_, text) lines[#lines + 1] = text end,
    AddLine = function(_, text) lines[#lines + 1] = text end,
    Show = function() end,
    Hide = function() end,
  }
  tab:GetScript("OnEnter")(tab)
  _G.GameTooltip = nil
  return table.concat(lines, "\n")
end

describe("profession tabs", function()
  local KEYS = { "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking", "tailoring", "smelting",
    "cooking", "firstaid" }

  local function shownTabs()
    local out = {}
    for _, key in ipairs(KEYS) do
      if ForeverSpeech.SideTabs.Tab(key):IsShown() then
        out[#out + 1] = key
      end
    end
    return out
  end

  it("one tab per crafting profession on the backpack's bar, only once learned", function()
    setup()
    local SideTabs = ForeverSpeech.SideTabs
    assert.same({}, shownTabs()) -- nothing learned
    -- Journeyman Cooking, Mining's Smelting, Apprentice Blacksmithing, Artisan First Aid
    _G.IsPlayerSpell = function(id) return id == 3102 or id == 2656 or id == 2018 or id == 10846 or id == 13262 end
    SideTabs.Update()
    assert.same({ "blacksmithing", "smelting", "cooking", "firstaid" }, shownTabs())
    -- cast by its name (the spell stub names every spell alike): the rank the character knows
    local cooking = SideTabs.Tab("cooking")
    assert.same({ "spell", "Désenchantement" }, { cooking:GetAttribute("type"), cooking:GetAttribute("spell") })
    assert.matches("Clic : ouvrir la fenêtre du métier", tooltipOf(cooking))
    ForeverSpeechDB.professionTabs = false
    SideTabs.Update()
    assert.same({}, shownTabs())
  end)

  it("greys a profession whose place the game says is not nearby; the click still casts its spell", function()
    setup()
    local SideTabs, L = ForeverSpeech.SideTabs, ForeverSpeech.L
    _G.IsPlayerSpell = function(id) return id == 2550 or id == 3908 or id == 13262 end -- Cooking, Tailoring
    local near, asked = false, {}
    _G.Enum = { Profession = { Blacksmithing = 1, Cooking = 5, Mining = 6 } }
    _G.C_TradeSkillUI = {
      IsNearProfessionSpellFocus = function(profession)
        asked[profession] = true
        return near
      end,
    }
    local cooking, tailoring = SideTabs.Tab("cooking"), SideTabs.Tab("tailoring")
    wow.tick(0.5) -- asked twice a second while the backpack is shown
    assert.is_true(cooking:IsShown())
    assert.is_true(cooking.icon:IsDesaturated())
    assert.is_false(tailoring.icon:IsDesaturated()) -- no place needed: never asked
    assert.same({ [5] = true }, asked)
    assert.is_false(cooking.def.locked()) -- greyed, not locked: the click still acts
    assert.equals("spell", cooking:GetAttribute("type"))
    assert.truthy(tooltipOf(cooking):find(L.PLACE_FIRE, 1, true))
    assert.truthy(table.concat(ForeverSpeechDB.trace, "\n"):find("bag: cooking near=false", 1, true))

    near = true -- the player walked up to a fire
    wow.tick(0.5)
    assert.is_false(cooking.icon:IsDesaturated())
    assert.is_nil(tooltipOf(cooking):find(L.PLACE_FIRE, 1, true))
  end)

  it("never greys without an answer from the game", function()
    setup()
    local SideTabs = ForeverSpeech.SideTabs
    local cooking = SideTabs.Tab("cooking")
    _G.IsPlayerSpell = function(id) return id == 2550 end
    local function greyed()
      SideTabs.Update()
      assert.is_true(cooking:IsShown())
      return cooking.icon:IsDesaturated()
    end
    assert.is_false(greyed()) -- no C_TradeSkillUI
    _G.Enum = { Profession = { Cooking = 5 } }
    _G.C_TradeSkillUI = { IsNearProfessionSpellFocus = function() error("bad argument") end }
    assert.is_false(greyed())
    _G.C_TradeSkillUI = { IsNearProfessionSpellFocus = function() return nil end }
    assert.is_false(greyed())
    _G.Enum = {} -- no Enum.Profession
    _G.C_TradeSkillUI = { IsNearProfessionSpellFocus = function() return false end }
    assert.is_false(greyed())
    _G.Enum = { Profession = { Cooking = 5 } } -- the same answer, with the profession: greyed
    assert.is_true(greyed())
  end)
end)

describe("disenchant tab", function()
  it("puts a secure Disenchant tab on the backpack's bar, only for an enchanter", function()
    local f = setup()
    assert.equal(f, ForeverSpeech.SideTabs.Owner("bag"))
    local tab = ForeverSpeech.SideTabs.Tab("disenchant")
    assert.is_true(tab:IsShown())
    assert.same({ "spell", 13262 }, { tab:GetAttribute("type"), tab:GetAttribute("spell") })

    setup({ known = false })
    assert.is_false(ForeverSpeech.SideTabs.Tab("disenchant"):IsShown())
    wow.slash("disenchant")
    assert.matches("ne connaît pas le désenchantement", wow.chatText())
  end)

  it("knows what can be disenchanted from the item's tooltip", function()
    setup()
    local D = ForeverSpeech.Disenchant
    assert.is_true(D.CanSlot(0, 1))
    assert.is_false(D.CanSlot(0, 2)) -- no line: a white
    assert.is_true(D.CanSlot(0, 3)) -- a skill requirement: the skill is not counted
    assert.is_false(D.CanSlot(0, 4)) -- empty slot
    assert.is_false(D.CanSlot(-1, 1)) -- the bank
    assert.equal(3, D.Count())
    LINES[DE_ITEM][2] = "Ne peut pas être désenchanté"
    assert.is_false(D.CanSlot(0, 1))
    LINES[DE_ITEM][2] = "Peut être désenchanté"
    wow.slash("disenchant")
    assert.matches("3 objet%(s%) à désenchanter", wow.chatText())
  end)

  it("without C_TooltipInfo, reads a hidden tooltip and lights nothing it cannot read", function()
    setup({ tooltip = false })
    assert.is_false(ForeverSpeech.Disenchant.CanSlot(0, 1))
  end)

  it("lights the slots that can be disenchanted while the spell waits for its item", function()
    local f = setup()
    assert.same({ false, false, false, false }, lit(f))
    clickTab()
    assert.is_true(ForeverSpeech.Disenchant.IsOn())
    assert.same({ true, false, true, true }, lit(f))
    assert.matches("0/1 id=821 quality=%? tooltip=true", ForeverSpeechDB.disenchantCheck[1])
    targeting = false -- the item was clicked, or Escape
    wow.tick(0.1)
    wow.advance(0)
    assert.is_false(ForeverSpeech.Disenchant.IsOn())
    assert.same({ false, false, false, false }, lit(f))
  end)

  it("lights nothing when the click cast nothing", function()
    local f = setup()
    local tab = ForeverSpeech.SideTabs.Tab("disenchant")
    tab:GetScript("PostClick")(tab, "LeftButton", true) -- the template acted on the other half of the click
    wow.advance(0)
    assert.is_false(ForeverSpeech.Disenchant.IsOn())
    assert.same({ false, false, false, false }, lit(f))
  end)

  it("takes the secure tab away when combat starts, back after", function()
    setup()
    local tab = ForeverSpeech.SideTabs.Tab("disenchant")
    assert.is_true(tab:IsShown())
    wow.fire("PLAYER_REGEN_DISABLED") -- runs before the lockdown
    assert.is_false(tab:IsShown())
    combat = true
    ForeverSpeech.SideTabs.Update()
    assert.is_false(tab:IsShown())
    combat = false
    wow.fire("PLAYER_REGEN_ENABLED")
    assert.is_true(tab:IsShown())
  end)

  it("the secure tab follows the bag wherever it moves, whoever moves it", function()
    setup()
    local SideTabs = ForeverSpeech.SideTabs
    local tab, bar = SideTabs.Tab("disenchant"), SideTabs.Bar("bag")
    local at
    tab.SetPoint = function(_, point, relativeTo, relativePoint, x, y)
      at = { point, relativeTo, relativePoint, x, y }
    end
    wow.tick(0.02) -- not moved: left alone
    assert.is_nil(at)
    bar.GetRight = function() return 450 end -- another addon dragged the bag
    wow.tick(0.02)
    assert.same({ "TOPRIGHT", UIParent, "BOTTOMLEFT", 450, 600 }, at)
    at = nil
    wow.tick(0.02)
    assert.is_nil(at) -- placed once per move
    combat = true
    bar.GetRight = function() return 500 end
    wow.tick(0.02)
    assert.is_nil(at) -- in combat the secure tab is away: never moved
    combat = false
    wow.tick(0.02)
    assert.equals(500, at[4])
  end)

  it("works with Classic's separate bag frames", function()
    local f = setup({ classic = true })
    assert.equal(f, ForeverSpeech.SideTabs.Owner("bag"))
    clickTab()
    assert.same({ true, false, true }, lit(f))
  end)
end)
