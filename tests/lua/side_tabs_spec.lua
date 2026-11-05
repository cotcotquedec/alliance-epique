local wow = require("tests.lua.helpers.wow")

-- A character who knows Fishing (Classic Apprentice rank), a sword and a shield equipped, a pole in the second bag.
local POLE, SWORD, SHIELD = "item:6256 Canne", "item:2488 Épée", "item:2129 Bouclier"
local inventory, bags, equips, combat

local function setup()
  wow.reset()
  combat = false
  inventory = { [16] = SWORD, [17] = SHIELD }
  bags = { [0] = {}, [1] = { [3] = POLE } }
  equips = {}
  _G.InCombatLockdown = function() return combat end
  _G.IsPlayerSpell = function(id) return id == 7620 end
  _G.C_Spell = { GetSpellInfo = function(id) return { name = "Pêche", iconID = 136245, spellID = id } end }
  _G.C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and 4 or 0 end,
    GetContainerItemLink = function(bag, slot) return bags[bag] and bags[bag][slot] end,
  }
  _G.C_Item = {
    GetItemInfoInstant = function(item)
      if item == POLE then return 6256, "Arme", "Canne à pêche", "INVTYPE_2HWEAPON", 132932, 2, 20 end
      if item == SWORD then return 2488, "Arme", "Épée", "INVTYPE_WEAPON", 135274, 2, 7 end
      return 2129, "Armure", "Bouclier", "INVTYPE_SHIELD", 134955, 4, 6
    end,
    EquipItemByName = function(item, slot)
      equips[#equips + 1] = item
      inventory[slot or 16] = item
      if item == POLE then inventory[17] = nil end -- a two-handed pole frees the off hand
    end,
  }
  _G.GetInventoryItemLink = function(_, slot) return inventory[slot] end
  _G.emotes = {}
  _G.DoEmote = function(token) _G.emotes[#_G.emotes + 1] = token end
  _G.ContainerFrameCombinedBags = wow.newRegion("Frame") -- the backpack, the fishing tab's frame
  wow.loadAddon()
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  wow.fire("PLAYER_LOGIN")
  wow.fire("PLAYER_ENTERING_WORLD")
end

local function openWindow()
  local PlayerFrame = ForeverSpeech.PlayerFrame
  PlayerFrame.Open()
  ForeverSpeech.SideTabs.Update() -- the stubs do not run OnShow
end

-- The fishing tab is on the backpack's bar (2026-10-20).
local function openBag()
  local f = _G.ContainerFrameCombinedBags
  f:Show()
  f:GetScript("OnShow")(f)
  return ForeverSpeech.SideTabs.Tab("fishing")
end

describe("fishing mode", function()
  before_each(setup)

  it("equips the pole of the bags and remembers the weapons; again, the weapons come back", function()
    local Fishing = ForeverSpeech.Fishing
    assert.is_true((Fishing.Start()))
    assert.same({ POLE }, equips)
    assert.is_true(Fishing.IsOn())
    assert.is_true(Fishing.Stop())
    wow.advance(1)
    assert.same({ POLE, SWORD, SHIELD }, equips)
    assert.is_false(Fishing.IsOn())
  end)

  it("never in combat", function()
    local Fishing = ForeverSpeech.Fishing
    combat = true
    assert.same({ false, "combat" }, { Fishing.Start() })
    assert.same({}, equips)
    combat = false
    Fishing.Start()
    combat = true
    assert.same({ false, "combat" }, { Fishing.Stop() })
    assert.is_true(Fishing.IsOn())
  end)

  it("not without a pole, and says so", function()
    bags[1][3] = nil
    wow.slash("fish")
    assert.is_false(ForeverSpeech.Fishing.IsOn())
    assert.same({}, equips)
    assert.matches("pas de canne", wow.chatText())
  end)

  it("a pole already equipped stays, nothing to restore", function()
    inventory[16], inventory[17] = POLE, nil
    local Fishing = ForeverSpeech.Fishing
    Fishing.Start()
    Fishing.Stop()
    wow.advance(1)
    assert.same({}, equips)
  end)

  it("kept per character across a reload", function()
    ForeverSpeech.Fishing.Start()
    local saved = ForeverSpeechDB.fishing
    local key = next(saved)
    assert.same({ on = true, main = SWORD, off = SHIELD }, saved[key])
  end)
end)

describe("fishing tab", function()
  before_each(setup)

  it("hidden to a character who does not know Fishing", function()
    _G.IsPlayerSpell = function() return false end
    assert.is_false(openBag():IsShown())
  end)

  it("hidden without a pole in the bags or the hand; shown once one comes", function()
    bags[1][3] = nil
    local tab = openBag()
    assert.is_false(tab:IsShown())
    bags[1][3] = POLE
    wow.fire("BAG_UPDATE_DELAYED")
    assert.is_true(tab:IsShown())
  end)

  it("click: fishing mode on, lit; again: off, greyed", function()
    local tab = openBag()
    assert.is_true(tab:IsShown())
    assert.equal(ForeverSpeech.SideTabs.Bar("bag"), tab:GetParent()) -- on the backpack, not the main window
    tab:Click()
    assert.is_true(ForeverSpeech.Fishing.IsOn())
    assert.is_true(tab.checked:IsShown())
    tab:Click()
    assert.is_false(ForeverSpeech.Fishing.IsOn())
    assert.is_false(tab.checked:IsShown())
  end)

  it("stays while fishing mode is on, even if the pole is gone (to get the weapons back)", function()
    local tab = openBag()
    tab:Click()
    inventory[16] = nil
    wow.fire("PLAYER_EQUIPMENT_CHANGED")
    assert.is_true(tab:IsShown())
  end)

  it("locked in combat: a click does nothing", function()
    local tab = openBag()
    tab:Click()
    combat = true
    wow.fire("PLAYER_REGEN_DISABLED")
    tab:Click()
    assert.is_true(ForeverSpeech.Fishing.IsOn())
    combat = false
    wow.fire("PLAYER_REGEN_ENABLED")
    tab:Click()
    assert.is_false(ForeverSpeech.Fishing.IsOn())
  end)
end)

describe("quick emotes", function()
  before_each(setup)

  it("are gone from the window's edge (2026-10-21: the emote wheel)", function()
    openWindow()
    assert.is_nil(ForeverSpeech.SideTabs.Tab("hello"))
  end)
end)
