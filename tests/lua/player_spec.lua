local wow = require("tests.lua.helpers.wow")

local function setup()
  wow.reset()
  wow.loadAddon()
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  ForeverSpeechDB.gap = 0 -- no silence between quests, except in the gap tests
end

local function events()
  local log = {}
  ForeverSpeech.Player.OnChange(function(event, info)
    log[#log + 1] = event .. ":" .. tostring(info.reason or info.source)
  end)
  return log
end

describe("Player", function()
  local Player
  before_each(function()
    setup()
    Player = ForeverSpeech.Player
  end)

  it("plays a file on the configured channel", function()
    ForeverSpeechDB.channel = "Master"
    assert.is_true(Player.PlayFile("a.ogg", { questID = 7 }))
    assert.same({ path = "a.ogg", channel = "Master" }, wow.sounds[1])
    assert.is_true(Player.IsPlaying())
    assert.is_true(Player.IsPlaying(7))
    assert.is_false(Player.IsPlaying(8))
  end)

  it("returns false for a missing file and plays nothing", function()
    wow.missingFiles = { ["missing.ogg"] = true }
    assert.is_false(Player.PlayFile("missing.ogg"))
    assert.is_false(Player.IsPlaying())
  end)

  it("stops the previous sound when a new one starts (one sound at a time)", function()
    local log = events()
    Player.PlayFile("a.ogg", { source = "a" })
    Player.PlayFile("b.ogg", { source = "b" })
    assert.same({ 1 }, wow.stopped)
    assert.same({ "start:a", "stop:replaced", "start:b" }, log)
  end)

  it("detects the natural end by polling C_Sound.IsPlaying", function()
    local log = events()
    Player.PlayFile("a.ogg", { source = "a" })
    wow.tick(0.1, 5)
    assert.is_true(Player.IsPlaying())
    wow.playing[1] = nil -- the sound ends
    wow.tick(0.1, 3)
    assert.is_false(Player.IsPlaying())
    assert.same({ "start:a", "stop:finished", "idle:nil" }, log) -- nothing queued: the list is done
  end)

  it("falls back to dur when C_Sound.IsPlaying is missing", function()
    _G.C_Sound = nil
    Player.PlayFile("a.ogg", { dur = 1.0 })
    wow.tick(0.25, 3)
    assert.is_true(Player.IsPlaying())
    wow.tick(0.25, 2)
    assert.is_false(Player.IsPlaying())
  end)

  it("Stop calls StopSound and reports 'stopped'", function()
    local log = events()
    Player.PlayFile("a.ogg", { source = "a" })
    assert.is_true(Player.Stop())
    assert.same({ 1 }, wow.stopped)
    assert.same({ "start:a", "stop:stopped" }, log)
    assert.is_false(Player.Stop())
  end)

  describe("TTS", function()
    local spoken, stopCalls
    before_each(function()
      spoken, stopCalls = {}, 0
      _G.C_VoiceChat = {
        GetTtsVoices = function()
          return { { voiceID = 0, name = "Amélie [fr-CA]" }, { voiceID = 9, name = "Jacques [fr-FR]" },
            { voiceID = 17, name = "Thomas [fr-FR]" } }
        end,
        SpeakText = function(...) spoken[#spoken + 1] = { ... } end,
        StopSpeakingText = function() stopCalls = stopCalls + 1 end,
      }
    end)

    it("speaks with Thomas fr-FR using the verified signature", function()
      assert.is_true(Player.Speak("Bonjour", { questID = 1 }))
      assert.same({ 17, "Bonjour", 0, 100, false }, spoken[1])
      assert.equals("tts", Player.Current().kind)
    end)

    it("refuses when no French voice exists", function()
      _G.C_VoiceChat.GetTtsVoices = function() return { { voiceID = 1, name = "Fred [en-US]" } } end
      assert.is_false(Player.Speak("Bonjour"))
    end)

    it("ends on FINISHED for its own utterance only", function()
      Player.Speak("un")
      wow.fire("VOICE_CHAT_TTS_PLAYBACK_STARTED", 4)
      wow.fire("VOICE_CHAT_TTS_PLAYBACK_FINISHED", 3) -- a replaced utterance
      assert.is_true(Player.IsPlaying())
      wow.fire("VOICE_CHAT_TTS_PLAYBACK_FINISHED", 4)
      assert.is_false(Player.IsPlaying())
    end)

    it("Stop calls StopSpeakingText", function()
      Player.Speak("un")
      Player.Next()
      assert.equals(1, stopCalls)
    end)
  end)
end)

describe("Player.PlayQuest", function()
  local Player
  before_each(function()
    setup()
    Player = ForeverSpeech.Player
    ForeverSpeechIndex.quests[783] = {
      detail = { file = "m.ogg", fileF = "f.ogg", src = "wowhead_fr", dur = 3 },
    }
  end)

  it("plays the index file, male variant for a male player", function()
    assert.same({ "playing", "index" }, { Player.PlayQuest(783) })
    assert.equals("m.ogg", wow.sounds[1].path)
  end)

  it("plays fileF for a female player (UnitSex 3)", function()
    _G.UnitSex = function() return 3 end
    Player.PlayQuest("783")
    assert.equals("f.ogg", wow.sounds[1].path)
  end)

  it("falls back to the test sound by default", function()
    assert.same({ "playing", "test" }, { Player.PlayQuest(18) })
    assert.equals(Player.TEST_FILE, wow.sounds[1].path)
  end)

  it("falls back to the test sound when the index file is missing", function()
    wow.missingFiles = { ["m.ogg"] = true }
    assert.same({ "playing", "test" }, { Player.PlayQuest(783) })
  end)

  it("uses TTS on the captured text when fallback is tts", function()
    local said
    _G.C_VoiceChat = {
      GetTtsVoices = function() return { { voiceID = 17, name = "Thomas [fr-FR]" } } end,
      SpeakText = function(_, text) said = text end,
    }
    ForeverSpeechDB.fallback = "tts"
    ForeverSpeech.Capture.Record({ questID = 18, text = "Texte capturé" })
    assert.same({ "playing", "tts" }, { Player.PlayQuest(18) })
    assert.equals("Texte capturé", said)
  end)

  it("plays nothing with fallback none", function()
    ForeverSpeechDB.fallback = "none"
    assert.same({ "failed", "no audio" }, { Player.PlayQuest(18) })
    assert.equals(0, #wow.sounds)
  end)

  it("rejects an invalid questID", function()
    assert.same({ "failed", "invalid questID" }, { Player.PlayQuest("abc") })
  end)
end)

describe("play queue", function()
  local Player
  before_each(function()
    setup()
    Player = ForeverSpeech.Player
  end)

  local function finishCurrent()
    wow.playing[Player.Current().handle] = nil
    wow.tick(0.3)
  end

  it("queues a second quest and plays it when the first ends", function()
    assert.equals("playing", (Player.PlayQuest(1)))
    assert.same({ "queued", 1 }, { Player.PlayQuest(2) })
    assert.equals(1, #wow.sounds)
    assert.is_true(Player.IsQueued(2))
    finishCurrent()
    assert.equals(2, #wow.sounds)
    assert.equals(2, Player.Current().questID)
    assert.is_false(Player.IsQueued(2))
  end)

  it("Next skips to the next queued quest right away", function()
    ForeverSpeechDB.gap = 2
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    Player.Next()
    assert.same({ 1 }, wow.stopped)
    assert.equals(2, Player.Current().questID)
    assert.is_false(Player.Next())
    assert.is_nil(Player.Current())
  end)

  it("Stop halts the list, the quests not played yet stay", function()
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    Player.Stop()
    assert.is_nil(Player.Current())
    assert.is_false(Player.IsBusy())
    assert.is_true(Player.IsQueued(2))
    assert.is_true(Player.Next()) -- Next resumes with it
    assert.equals(2, Player.Current().questID)
  end)

  it("Stop during the gap cancels the next quest", function()
    ForeverSpeechDB.gap = 2
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    finishCurrent()
    assert.is_true(Player.Stop())
    wow.advance(3)
    assert.is_nil(Player.Current())
    assert.is_true(Player.IsQueued(2))
  end)

  it("Clear stops everything and empties the queue", function()
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    Player.Clear()
    assert.is_nil(Player.Current())
    assert.equals(0, #Player.Queue())
    assert.equals(1, #wow.sounds)
  end)

  it("tells when the list has nothing left to play (idle), not when Stop halts it", function()
    local idle = 0
    Player.OnChange(function(event)
      if event == "idle" then
        idle = idle + 1
      end
    end)
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    finishCurrent() -- 2 starts
    Player.Stop()
    assert.equals(0, idle)
    Player.PlayNow(2)
    finishCurrent()
    assert.equals(1, idle)
    Player.PlayQuest(3)
    Player.Next() -- past the last quest
    assert.equals(2, idle)
    Player.PlayQuest(4)
    Player.Clear()
    assert.equals(3, idle)
  end)

  it("ignores a quest already playing or queued", function()
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    assert.same({ "duplicate", "playing" }, { Player.PlayQuest(1) })
    assert.same({ "duplicate", "queued" }, { Player.PlayQuest("2") })
    assert.equals(1, #Player.Queue())
  end)

  it("skips queued items that have no audio", function()
    ForeverSpeechDB.fallback = "none"
    ForeverSpeechIndex.quests[1] = { detail = { file = "one.ogg", src = "test" } }
    ForeverSpeechIndex.quests[3] = { detail = { file = "three.ogg", src = "test" } }
    Player.PlayQuest(1)
    Player.PlayQuest(2) -- no index entry, no fallback
    Player.PlayQuest(3)
    finishCurrent()
    assert.equals("three.ogg", wow.sounds[2].path)
  end)

  it("waits the gap between two quests, and counts as playing meanwhile", function()
    ForeverSpeechDB.gap = 2
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    finishCurrent()
    assert.is_nil(Player.Current())
    assert.is_true(Player.IsBusy())
    assert.same({ "queued", 2 }, { Player.PlayQuest(3) }) -- the list is playing: 3 waits
    wow.advance(1.9)
    assert.is_nil(Player.Current())
    wow.advance(0.2)
    assert.equals(2, Player.Current().questID)
  end)

  it("a quest started during the gap cancels the scheduled one", function()
    ForeverSpeechDB.gap = 2
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    Player.PlayQuest(3)
    finishCurrent()
    Player.PlayNow(3)
    wow.advance(3)
    assert.equals(3, Player.Current().questID)
    Player.Reset()
    assert.is_false(Player.IsBusy())
  end)

  it("plays the page sound louder, on the Master channel", function()
    local calls = {}
    _G.PlaySound = function(kit, channel) calls[#calls + 1] = tostring(kit) .. ":" .. tostring(channel) end
    Player.PlayQuest(1)
    assert.same({ "875:Master", "875:Master" }, calls)
  end)

  it("the test sound goes through the queue too", function()
    Player.PlayQuest(1)
    wow.slash("test")
    assert.matches("the test sound queued (position 1)", wow.chatText(), 1, true)
  end)
end)

describe("player commands", function()
  before_each(setup)

  it("/fs test plays the test sound and /fs stop stops it", function()
    wow.slash("test")
    assert.equals(ForeverSpeech.Player.TEST_FILE, wow.sounds[1].path)
    wow.slash("stop")
    assert.same({ 1 }, wow.stopped)
    wow.slash("stop")
    assert.matches("nothing is playing", wow.chatText(), 1, true)
  end)

  it("/fs queue and /fs clear", function()
    wow.slash("play 1")
    wow.slash("play 2")
    wow.slash("queue")
    assert.matches("now: quest 1", wow.chatText(), 1, true)
    assert.matches("1. quest 2", wow.chatText(), 1, true)
    wow.slash("clear")
    assert.is_nil(ForeverSpeech.Player.Current())
  end)

  it("/fs channel only accepts known channels", function()
    wow.slash("channel master")
    assert.equals("Master", ForeverSpeechDB.channel)
    wow.slash("channel bogus")
    assert.equals("Master", ForeverSpeechDB.channel)
  end)

  it("/fs fallback switches mode", function()
    wow.slash("fallback tts")
    assert.equals("tts", ForeverSpeechDB.fallback)
    wow.slash("fallback nope")
    assert.equals("tts", ForeverSpeechDB.fallback)
  end)
end)
