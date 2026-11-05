local wow = require("tests.lua.helpers.wow")

describe("addon loading", function()
  before_each(function()
    wow.reset()
    wow.loadAddon()
  end)

  it("loads every TOC file and exposes a single namespace", function()
    assert.is_table(ForeverSpeech)
    assert.equals("ForeverSpeech", ForeverSpeech.name)
    assert.equals(9, ForeverSpeechIndex.version)
    assert.is_table(ForeverSpeechIndex.quests)
    assert.is_table(ForeverSpeechIndex.npcs)
    assert.is_true(ForeverSpeech.Index.IsValid())
  end)

  it("the generated index file loads and follows contract v9", function()
    _G.ForeverSpeechIndex = nil
    assert(loadfile("addon/ForeverSpeech/data/index.lua"))()
    assert.equals(9, ForeverSpeechIndex.version)
    assert.is_table(ForeverSpeechIndex.quests)
    assert.is_table(ForeverSpeechIndex.npcs)
    for questID, quest in pairs(ForeverSpeechIndex.quests) do
      assert.is_number(questID)
      for _, part in ipairs({ "detail", "complete" }) do
        if quest[part] then
          assert.matches("^Interface\\AddOns\\ForeverSpeech\\audio\\", quest[part].file)
        end
      end
    end
    -- v9 (2026-10-21): books by the key of their title, dialogues by NPC (H.Text, contract-v9)
    local Text = ForeverSpeech.Text
    for key, book in pairs(ForeverSpeechIndex.books or {}) do
      assert.equals(Text.Key(book.title), key)
      for page, list in pairs(book.pages) do
        assert.is_number(page)
        for _, entry in ipairs(list) do
          assert.is_string(entry.fp)
          assert.is_true(#entry.fp <= 48)
        end
      end
    end
    for npcID, pages in pairs(ForeverSpeechIndex.dialogues or {}) do
      assert.is_number(npcID)
      for _, page in ipairs(pages) do
        assert.equals(table.concat(Text.Tokens(page.words), " "), page.words)
        assert.matches("^Interface\\AddOns\\ForeverSpeech\\audio\\", page.intro.file)
      end
    end
  end)

  it("initialises SavedVariables with defaults on ADDON_LOADED", function()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    assert.is_true(ForeverSpeech.initialized)
    assert.equals("Dialog", ForeverSpeechDB.channel)
    assert.is_false(ForeverSpeechDB.debug)
    assert.is_table(ForeverSpeechCaptures)
    assert.is_true(ForeverSpeech.svState.dbWasNil)
  end)

  it("turns the first compact setting into the quest text setting (2026-10-21)", function()
    wow.reset()
    _G.ForeverSpeechDB = { compact = true, showText = true }
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    assert.is_false(ForeverSpeechDB.showText)
    assert.is_nil(ForeverSpeechDB.compact)
  end)

  it("keeps restored SavedVariables", function()
    wow.reset()
    _G.ForeverSpeechDB = { channel = "Master", debug = true }
    _G.ForeverSpeechCaptures = { x = 1 }
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    assert.equals("Master", ForeverSpeechDB.channel)
    assert.equals(1, ForeverSpeechCaptures.x)
    assert.is_false(ForeverSpeech.svState.dbWasNil)
  end)

  it("turns debug off once for settings saved before v2, then keeps the choice", function()
    wow.reset()
    _G.ForeverSpeechDB = { debug = true }
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    assert.is_false(ForeverSpeechDB.debug)
    assert.equals(4, ForeverSpeechDB.settingsVersion)

    wow.reset()
    _G.ForeverSpeechDB = { debug = true, settingsVersion = 2 }
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    assert.is_true(ForeverSpeechDB.debug)
  end)

  it("turns the automatic reading on once and drops the reward panel reading (v4: buttons removed)", function()
    wow.reset()
    _G.ForeverSpeechDB = { autoplay = false, readOnTurnIn = true, settingsVersion = 3 }
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    assert.is_true(ForeverSpeechDB.autoplay)
    assert.is_nil(ForeverSpeechDB.readOnTurnIn)

    wow.reset()
    _G.ForeverSpeechDB = { autoplay = false, settingsVersion = 4 }
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    assert.is_false(ForeverSpeechDB.autoplay)
  end)

  it("says it is loaded in one short chat line, nothing else", function()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    wow.fire("PLAYER_LOGIN")
    wow.fire("PLAYER_ENTERING_WORLD")
    assert.same({ "|cff4fa3e0Alliance Épique|r: chargé. /fs pour les commandes." }, wow.chat)
  end)

  it("ignores ADDON_LOADED for other addons", function()
    wow.fire("ADDON_LOADED", "SomethingElse")
    assert.is_nil(ForeverSpeech.initialized)
  end)

  it("keeps a diagnostic trace, including lines logged before ADDON_LOADED", function()
    wow.reset()
    wow.loadAddon()
    ForeverSpeech.Trace("early %s", nil)
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    ForeverSpeech.Trace("late %s", 1)
    local trace = table.concat(ForeverSpeechDB.trace, "\n")
    assert.matches("early nil", trace, 1, true)
    assert.matches("late 1", trace, 1, true)
    assert.matches("=== load", trace, 1, true)
  end)

  it("runs OnInit callbacks registered after initialisation immediately", function()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    local called = false
    ForeverSpeech.OnInit(function() called = true end)
    assert.is_true(called)
  end)
end)

describe("/fs", function()
  before_each(function()
    wow.reset()
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
  end)

  it("/fs alone toggles the main window", function()
    wow.slash("")
    assert.is_true(ForeverSpeech.PlayerFrame.IsShown())
    wow.slash("")
    assert.is_false(ForeverSpeech.PlayerFrame.IsShown())
  end)

  it("prints help with /fs help", function()
    wow.slash("help")
    assert.matches("/fs debug on||off", wow.chatText(), 1, true)
    assert.matches("/fs api [show]", wow.chatText(), 1, true)
  end)

  it("toggles debug", function()
    wow.slash("debug on")
    assert.is_true(ForeverSpeechDB.debug)
    wow.slash("DEBUG off")
    assert.is_false(ForeverSpeechDB.debug)
  end)

  it("reports unknown commands", function()
    wow.slash("nope")
    assert.matches("unknown command 'nope'", wow.chatText(), 1, true)
  end)
end)

describe("TryRegisterEvent", function()
  it("returns false instead of raising for unknown events", function()
    wow.reset({ knownEvents = {
      ADDON_LOADED = true, QUEST_DETAIL = true, PLAYER_LOGIN = true, PLAYER_ENTERING_WORLD = true,
    } })
    wow.loadAddon()
    local ok, err = ForeverSpeech.TryRegisterEvent("SOUNDKIT_FINISHED", function() end)
    assert.is_false(ok)
    assert.matches("unknown event", err)
  end)

  it("adds a handler to an event already registered (RegisterEvent then returns false)", function()
    wow.reset()
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    local calls = 0
    assert.is_true(ForeverSpeech.TryRegisterEvent("QUEST_COMPLETE", function() calls = calls + 1 end))
    assert.is_true(ForeverSpeech.TryRegisterEvent("QUEST_COMPLETE", function() calls = calls + 1 end))
    wow.fire("QUEST_COMPLETE")
    assert.equals(2, calls)
  end)
end)
