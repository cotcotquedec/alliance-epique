local wow = require("tests.lua.helpers.wow")

describe("ducking", function()
  local cvars, Player, Ducking

  local function setup(saved, channel)
    wow.reset()
    cvars = { Sound_MusicVolume = "0.8", Sound_AmbienceVolume = "0.5", Sound_SFXVolume = "1",
              Sound_DialogVolume = "1" }
    _G.GetCVar = function(name) return cvars[name] end
    _G.SetCVar = function(name, value) cvars[name] = tostring(value) end
    _G.ForeverSpeechDB = saved
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    ForeverSpeechDB.gap = 0
    ForeverSpeechDB.pageSound = false
    ForeverSpeechDB.channel = channel or "Dialog"
    Player, Ducking = ForeverSpeech.Player, ForeverSpeech.Ducking
  end

  local function num(name)
    return tonumber(cvars[name])
  end

  local function finish(handle)
    wow.playing[handle] = nil
    wow.tick(0.25)
  end

  it("fades music, ambience and effects down while a line plays, never the addon's own channel", function()
    setup()
    Player.PlayQuest(5) -- the test sound
    wow.advance(0.4)
    assert.is_true(num("Sound_MusicVolume") < 0.8 and num("Sound_MusicVolume") > 0.24) -- half way
    wow.advance(0.5)
    assert.equals(0.24, num("Sound_MusicVolume"))
    assert.equals(0.2, num("Sound_AmbienceVolume"))
    assert.equals(0.6, num("Sound_SFXVolume"))
    assert.equals("1", cvars.Sound_DialogVolume)
    assert.is_true(Ducking.IsLowered())
  end)

  it("leaves the effects alone when the addon plays on the SFX channel", function()
    setup(nil, "SFX")
    Player.PlayQuest(5)
    wow.advance(1)
    assert.equals("1", cvars.Sound_SFXVolume)
    assert.equals(0.24, num("Sound_MusicVolume"))
  end)

  it("comes back 1.2 s after the list goes quiet, to the player's exact values", function()
    setup()
    Player.PlayQuest(5)
    wow.advance(1)
    finish(1)
    wow.advance(1.1)
    assert.equals(0.24, num("Sound_MusicVolume")) -- still down during the hold
    wow.advance(0.2 + 0.85)
    assert.same({ "0.8", "0.5", "1" }, { cvars.Sound_MusicVolume, cvars.Sound_AmbienceVolume, cvars.Sound_SFXVolume })
    assert.is_nil(next(ForeverSpeechDB.duckState))
    assert.is_false(Ducking.IsLowered())
  end)

  it("stays down between two quests of the list", function()
    setup()
    ForeverSpeechDB.gap = 2
    Player.PlayQuest(5)
    Player.PlayQuest(6)
    wow.advance(1)
    finish(1)
    wow.advance(1.5) -- in the gap
    assert.equals(0.24, num("Sound_MusicVolume"))
    wow.advance(1) -- quest 6 started
    assert.is_true(Player.IsPlaying(6))
    assert.equals(0.24, num("Sound_MusicVolume"))
  end)

  it("a slider the player moved is left as the player put it", function()
    setup()
    Player.PlayQuest(5)
    wow.advance(1)
    cvars.Sound_MusicVolume = "0.9"
    Player.Stop()
    wow.advance(3)
    assert.equals("0.9", cvars.Sound_MusicVolume)
    assert.equals("0.5", cvars.Sound_AmbienceVolume)
  end)

  it("restores at once on logout (/reload)", function()
    setup()
    Player.PlayQuest(5)
    wow.advance(1)
    wow.fire("PLAYER_LOGOUT")
    assert.same({ "0.8", "0.5", "1" }, { cvars.Sound_MusicVolume, cvars.Sound_AmbienceVolume, cvars.Sound_SFXVolume })
    assert.is_nil(next(ForeverSpeechDB.duckState))
  end)

  it("puts back at login what a crash left lowered, not what the player changed since", function()
    setup({ duckState = {
      Sound_MusicVolume = { orig = 0.8, origText = "0.8", set = 0.24, share = 0.3 },
      Sound_AmbienceVolume = { orig = 0.5, origText = "0.5", set = 0.2, share = 0.4 },
    } })
    cvars.Sound_MusicVolume, cvars.Sound_AmbienceVolume = "0.240", "0.7"
    wow.fire("PLAYER_LOGIN")
    assert.equals("0.8", cvars.Sound_MusicVolume)
    assert.equals("0.7", cvars.Sound_AmbienceVolume)
    assert.is_nil(next(ForeverSpeechDB.duckState))
  end)

  it("does nothing when off, and turning it off mid-line brings the volumes back", function()
    setup()
    ForeverSpeechDB.duck = false
    Player.PlayQuest(5)
    wow.advance(1)
    assert.equals("0.8", cvars.Sound_MusicVolume)
    Player.Stop()
    ForeverSpeechDB.duck = true
    Player.PlayQuest(6)
    wow.advance(1)
    assert.equals(0.24, num("Sound_MusicVolume"))
    wow.slash("duck off")
    wow.advance(1)
    assert.equals("0.8", cvars.Sound_MusicVolume)
  end)
end)
