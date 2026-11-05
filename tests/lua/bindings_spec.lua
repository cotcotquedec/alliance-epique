local wow = require("tests.lua.helpers.wow")

describe("key bindings", function()
  local Player, Bindings

  before_each(function()
    wow.reset()
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    ForeverSpeechDB.gap = 0
    Player, Bindings = ForeverSpeech.Player, ForeverSpeech.Bindings
  end)

  it("names its actions in French, under the addon's title", function()
    assert.equals("Alliance Épique", _G.BINDING_HEADER_FOREVERSPEECH)
    assert.equals("Lecture / Stop (quête affichée)", _G.BINDING_NAME_FOREVERSPEECH_PLAY)
  end)

  it("Bindings.xml calls the functions the addon has", function()
    local xml = assert(io.open("addon/ForeverSpeech/Bindings.xml")):read("*a")
    local found = 0
    for name, fn in xml:gmatch('<Binding name="(FOREVERSPEECH_%u+)".->%s*ForeverSpeech%.Bindings%.(%a+)%(%)') do
      assert.is_function(Bindings[fn], name)
      assert.is_string(_G["BINDING_NAME_" .. name])
      found = found + 1
    end
    assert.equals(3, found)
    -- the emote wheel, held (2026-10-21): down and up
    assert.matches('<Binding name="FOREVERSPEECH_EMOTEWHEEL" category="ADDONS" runOnUp="true">%s*'
      .. 'ForeverSpeech%.EmoteWheel%.OnKey%(keystate == "down"%)', xml)
    assert.is_function(ForeverSpeech.EmoteWheel.OnKey)
    assert.equals(4, select(2, xml:gsub("<Binding ", "")))
  end)

  it("Lecture / Stop plays the window's quest, then stops; Avancer and Stop act on the list", function()
    ForeverSpeech.PlayerFrame.ShowQuest(5)
    Bindings.TogglePlay()
    assert.is_true(Player.IsPlaying(5))
    Player.PlayQuest(6)
    Bindings.Next()
    assert.is_true(Player.IsPlaying(6))
    Bindings.Stop()
    assert.is_nil(Player.Current())
    Bindings.TogglePlay() -- the window shows quest 5 or 6: it plays again
    assert.is_not_nil(Player.Current())
    Bindings.TogglePlay()
    assert.is_nil(Player.Current())
  end)
end)
