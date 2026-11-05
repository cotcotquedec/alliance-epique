local wow = require("tests.lua.helpers.wow")

describe("emote wheel", function()
  local Wheel, emotes, cursor

  before_each(function()
    wow.reset()
    emotes, cursor = {}, { 500, 400 }
    _G.DoEmote = function(token) emotes[#emotes + 1] = token end
    _G.GetCursorPosition = function() return cursor[1], cursor[2] end
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    Wheel = ForeverSpeech.EmoteWheel
  end)

  -- The wheel centered at (500, 400), scale 1; the cursor moved by (dx, dy).
  local function aim(dx, dy)
    local _, wheel = Wheel.Parts()
    wheel.GetCenter = function() return 500, 400 end
    wheel.GetEffectiveScale = function() return 1 end
    cursor = { 500 + dx, 400 + dy }
    Wheel.Update()
  end

  it("finds the wedge under an offset: first at the top, then counterclockwise, nothing in the center", function()
    assert.equals(1, Wheel.WedgeAt(0, 100, 8))
    assert.equals(3, Wheel.WedgeAt(-100, 0, 8))   -- left
    assert.equals(5, Wheel.WedgeAt(0, -100, 8))   -- bottom
    assert.equals(7, Wheel.WedgeAt(100, 0, 8))    -- right
    assert.equals(2, Wheel.WedgeAt(-70, 70, 8))   -- top left
    assert.equals(8, Wheel.WedgeAt(70, 70, 8))    -- top right
    assert.is_nil(Wheel.WedgeAt(5, 5, 8))
    assert.equals(1, Wheel.WedgeAt(10, 100, 4))
  end)

  it("held: opens at the cursor; released on a wedge: its emote", function()
    Wheel.OnKey(true)
    assert.is_true(Wheel.IsShown())
    aim(0, 100) -- top: Saluer
    wow.advance(0.3)
    Wheel.OnKey(false)
    assert.is_false(Wheel.IsShown())
    assert.same({ "HELLO" }, emotes)
    Wheel.OnKey(true)
    aim(-100, 0) -- left: Féliciter
    wow.advance(0.3)
    Wheel.OnKey(false)
    assert.same({ "HELLO", "CONGRATULATE" }, emotes)
  end)

  it("the pointer, centered and turned to the aimed direction; the gold cone on the wedge aimed", function()
    local rotations = {}
    _G.C_Texture = { GetAtlasInfo = function(name)
      if name == "Radial_Wheel_Select_Pointer" then return { width = 64, height = 64 } end
    end }
    Wheel.OnKey(true)
    local _, wheel, art = Wheel.Parts()
    art.pointer.SetRotation = function(_, r) rotations[#rotations + 1] = r end
    local points, turns = {}, {}
    art.glow.SetPoint = function(_, ...) points[#points + 1] = { ... } end
    art.glow.SetRotation = function(_, r) turns[#turns + 1] = r end
    aim(0, 100) -- straight up
    assert.is_true(art.pointer:IsShown())
    assert.is_true(math.abs(rotations[#rotations] - math.pi / 2) < 1e-6)
    assert.is_false(art.atlasGlow) -- no 8-wedge highlight: the addon's cone
    assert.equals("Interface\\AddOns\\ForeverSpeech\\media\\ui\\wheel_wedge", art.glow:GetTexture())
    assert.is_true(art.glow:IsShown())
    assert.same({ "CENTER", wheel, "CENTER", 0, 0 }, { unpack(points[#points]) }) -- centered
    assert.is_true(math.abs(turns[#turns] - math.pi / 2) < 1e-6) -- turned to Saluer's wedge
    aim(-70, 75) -- still in the top left wedge: the pointer follows the mouse
    assert.is_true(math.abs(rotations[#rotations] - math.atan2(75, -70)) < 1e-6)
    aim(3, 3) -- the center: no pointer, no highlight
    assert.is_false(art.pointer:IsShown())
    assert.is_false(art.glow:IsShown())
    assert.is_not_nil(wheel)
  end)

  it("does nothing released in the center, after a short press, or with the setting off", function()
    Wheel.OnKey(true)
    aim(2, 3)
    wow.advance(0.3)
    Wheel.OnKey(false)
    Wheel.OnKey(true)
    aim(0, 100)
    wow.advance(0.05)
    Wheel.OnKey(false)
    ForeverSpeechDB.emoteWheel = false
    Wheel.OnKey(true)
    assert.is_false(Wheel.IsShown())
    assert.same({}, emotes)
  end)

  it("a left click plays at once, a right click cancels", function()
    Wheel.OnKey(true)
    aim(0, -100) -- bottom: Rire
    local catcher = Wheel.Parts()
    catcher._scripts.OnMouseDown(catcher, "LeftButton")
    assert.same({ "LAUGH" }, emotes)
    Wheel.OnKey(false) -- the key's release afterwards: nothing more
    Wheel.OnKey(true)
    aim(0, 100)
    catcher._scripts.OnMouseDown(catcher, "RightButton")
    wow.advance(0.3)
    Wheel.OnKey(false)
    assert.same({ "LAUGH" }, emotes)
  end)

  it("aims with the mouse even in the game's gamepad mode (T60: a gamepad connected)", function()
    _G.C_GamePad = {
      IsEnabled = function() return true end,
      GetActiveDeviceID = function() return 1 end,
      GetDeviceMappedState = function() return { sticks = { { x = 0, y = 0 }, { x = 0, y = 0 } } } end,
    }
    Wheel.OnKey(true)
    aim(100, 0) -- right: S'incliner
    wow.advance(0.3)
    Wheel.OnKey(false)
    assert.same({ "BOW" }, emotes)
  end)

  it("aims with the right stick, keeping the last direction", function()
    local sticks = { { x = 0, y = 0 }, { x = 0, y = 0 } }
    _G.C_GamePad = {
      IsEnabled = function() return true end,
      GetActiveDeviceID = function() return 1 end,
      GetDeviceMappedState = function() return { sticks = sticks } end,
    }
    Wheel.OnKey(true)
    sticks[2] = { x = 1, y = 0 } -- right: S'incliner
    Wheel.Update()
    sticks[2] = { x = 0, y = 0 } -- stick back to the center
    Wheel.Update()
    wow.advance(0.3)
    Wheel.OnKey(false)
    assert.same({ "BOW" }, emotes)
  end)

  it("is a key binding of its own", function()
    assert.equals("Roue d'émotes (maintenir)", _G.BINDING_NAME_FOREVERSPEECH_EMOTEWHEEL)
  end)
end)

describe("options: the emote wheel's key", function()
  local bindings, saved, combat

  before_each(function()
    wow.reset()
    bindings, saved, combat = { F = "TOGGLEPINGLISTENER" }, 0, false
    _G.InCombatLockdown = function() return combat end
    _G.SetBinding = function(key, command)
      bindings[key] = command
      return true
    end
    _G.GetBindingKey = function(command)
      for key, c in pairs(bindings) do
        if c == command then
          return key
        end
      end
    end
    _G.GetBindingAction = function(key) return bindings[key] or "" end
    _G.SaveBindings = function() saved = saved + 1 end
    _G.GetCurrentBindingSet = function() return 1 end
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
  end)

  it("binds a key alone to the wheel, says what it replaced, removes it, never in combat", function()
    local Options = ForeverSpeech.Options
    assert.is_true(Options.Bind("FOREVERSPEECH_EMOTEWHEEL", "G"))
    assert.equals("FOREVERSPEECH_EMOTEWHEEL", bindings.G)
    assert.is_true(Options.Bind("FOREVERSPEECH_EMOTEWHEEL", "F"))
    assert.is_nil(bindings.G) -- its old key freed
    assert.equals("FOREVERSPEECH_EMOTEWHEEL", bindings.F)
    assert.matches("TOGGLEPINGLISTENER", wow.chat[#wow.chat], 1, true)
    assert.equals(2, saved)
    combat = true
    assert.is_false(Options.Bind("FOREVERSPEECH_EMOTEWHEEL", "H"))
    assert.matches("en combat", wow.chat[#wow.chat], 1, true)
    combat = false
    assert.is_true(Options.Unbind("FOREVERSPEECH_EMOTEWHEEL"))
    assert.is_nil(bindings.F)
  end)
end)
