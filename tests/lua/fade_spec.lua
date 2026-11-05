local wow = require("tests.lua.helpers.wow")

-- The interface fades while the character moves (2026-11-05): to 20 % (never the minimap) in 3 seconds of moving,
-- back to 100 % in half a second once stopped; the element under the mouse at full alpha; never while it is needed.
local moving

local function setup()
  wow.reset()
  moving = false
  wow.loadAddon()
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  wow.fire("PLAYER_LOGIN")
  _G.IsPlayerMoving = function() return moving end
end

local function near(expected, actual)
  assert.is_true(math.abs(expected - actual) < 0.001, ("expected %s, got %s"):format(expected, actual))
end

after_each(function()
  _G.IsPlayerMoving, _G.GetMouseFoci, _G.InCombatLockdown, _G.WorldMapFrame = nil, nil, nil, nil
end)

describe("the interface faded while moving", function()
  it("fades to 20 % in 3 seconds of moving, and comes back in half a second once stopped", function()
    setup()
    local Fade = ForeverSpeech.Fade
    local set
    _G.UIParent.SetAlpha = function(_, value) set = value end
    moving = true
    wow.tick(0.5, 3)
    near(0.6, Fade.Alpha()) -- half way after 1.5 s
    wow.tick(0.5, 4)
    near(0.2, Fade.Alpha()) -- 20 %, and no lower
    near(0.2, set)
    moving = false
    wow.tick(0.25)
    near(0.6, Fade.Alpha()) -- from where it was to 100 % in 0.5 s
    wow.tick(0.25)
    near(1, Fade.Alpha())
  end)

  it("fades on a flight path too", function()
    setup()
    _G.UnitOnTaxi = function(unit) return unit == "player" end
    wow.tick(0.5, 3)
    near(0.6, ForeverSpeech.Fade.Alpha())
    _G.UnitOnTaxi = nil
  end)

  it("comes back at once in combat, and never fades while the world map is open or when turned off", function()
    setup()
    local Fade = ForeverSpeech.Fade
    moving = true
    wow.tick(0.5, 3)
    wow.fire("PLAYER_REGEN_DISABLED")
    near(1, Fade.Alpha())
    _G.InCombatLockdown = function() return true end
    wow.tick(0.5, 3)
    near(1, Fade.Alpha()) -- moving in combat: nothing fades
    _G.InCombatLockdown = nil
    _G.WorldMapFrame = wow.newRegion("Frame")
    _G.WorldMapFrame:Show()
    wow.tick(0.5, 3)
    near(1, Fade.Alpha())
    _G.WorldMapFrame = nil
    Fade.SetEnabled(false)
    wow.tick(0.5, 3)
    near(1, Fade.Alpha())
    Fade.SetEnabled(true)
    wow.tick(0.5, 3)
    near(0.6, Fade.Alpha())
  end)

  it("never fades the minimap, nor touches its alpha", function()
    setup()
    local cluster = CreateFrame("Frame", nil, _G.UIParent)
    _G.Minimap = CreateFrame("Frame", nil, cluster)
    local own, ignoring = 1, {}
    cluster.GetAlpha = function() return own end
    cluster.SetAlpha = function() error("the minimap's alpha is not the fade's") end
    cluster.IsIgnoringParentAlpha = function() return false end
    cluster.SetIgnoreParentAlpha = function(_, value) ignoring[#ignoring + 1] = value end
    moving = true
    wow.tick(0.5, 6)
    near(0.2, ForeverSpeech.Fade.Alpha()) -- the interface at 20 %
    near(1, own) -- the minimap out of the fade, at its own alpha
    assert.same({ true }, ignoring)
    moving = false
    wow.tick(0.25, 3)
    assert.same({ true, false }, ignoring) -- its own setting back
    _G.Minimap = nil
  end)

  it("shows the element under the mouse at full alpha, and gives it back its own setting after", function()
    setup()
    local bar = CreateFrame("Frame", nil, _G.UIParent)
    local button = CreateFrame("Button", nil, bar)
    local ignoring = {}
    bar.IsIgnoringParentAlpha = function() return false end
    bar.SetIgnoreParentAlpha = function(_, value) ignoring[#ignoring + 1] = value end
    _G.GetMouseFoci = function() return { button } end
    moving = true
    wow.tick(0.5)
    assert.same({ true }, ignoring) -- lifted over the faded interface
    _G.GetMouseFoci = function() return { _G.WorldFrame } end
    wow.tick(0.5)
    assert.same({ true, false }, ignoring) -- the mouse gone: its own setting back
  end)
end)
