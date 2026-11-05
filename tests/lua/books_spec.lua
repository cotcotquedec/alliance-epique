local wow = require("tests.lua.helpers.wow")
local fx = require("tests.lua.fixtures.index_v9")

describe("books read by Elise", function()
  local page, Player, Books, spoken

  local function show(title, number, text, creator)
    page = { title = title, number = number, text = text, creator = creator }
    wow.fire("ITEM_TEXT_READY")
  end

  before_each(function()
    wow.reset()
    page = {}
    _G.ItemTextGetItem = function() return page.title end
    _G.ItemTextGetPage = function() return page.number end
    _G.ItemTextGetText = function() return page.text end
    _G.ItemTextGetCreator = function() return page.creator end
    _G.GetZoneText = function() return "Hinterlands" end
    spoken = nil
    _G.C_VoiceChat = {
      GetTtsVoices = function() return { { voiceID = 1, name = "Thomas [fr-FR]" } } end,
      SpeakText = function(_, text) spoken = text end,
    }
    wow.index = fx.build()
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    ForeverSpeechDB.gap = 0
    Player, Books = ForeverSpeech.Player, ForeverSpeech.Books
  end)

  it("finds a page by its fingerprint when two books share a title", function()
    local a = Books.Lookup(fx.BOOK_TITLE, 1, fx.PAGE1_A)
    local b = Books.Lookup("LE LIVRE DE TIRION", 1, fx.PAGE1_B)
    assert.equals(fx.FILE_A, a.intro.file)
    assert.equals(fx.FILE_B, b.intro.file)
    assert.is_nil(Books.Lookup(fx.BOOK_TITLE, 1, "Un troisième texte."))
    assert.is_nil(Books.Lookup("Un autre titre", 1, fx.PAGE1_A))
  end)

  it("takes the only entry of a page whose text changed", function()
    assert.equals(fx.FILE_2, Books.Lookup(fx.BOOK_TITLE, 2, fx.PAGE2).intro.file)
  end)

  it("reads a page as it opens, with her voice and the book's title", function()
    show(fx.BOOK_TITLE, 1, fx.PAGE1_A)
    assert.equals(fx.FILE_A, wow.sounds[1].path)
    local cur = Player.Current()
    assert.equals("book", cur.line)
    local entry = ForeverSpeech.Index.Line("book", cur.lineID)
    assert.equals("Le Livre de Tirion — page 1", entry.name)
    assert.equals("book", Player.List()[1].line)
    local PlayerFrame = ForeverSpeech.PlayerFrame
    assert.equals("portrait", (PlayerFrame.Visual())) -- Elise's
    assert.equals(fx.PAGE1_A, PlayerFrame.QuestText())
    assert.matches("INV_Misc_Book_09$", PlayerFrame.ListPanel().rows[1].icon:GetTexture())
  end)

  it("turning the page stops it and reads the next one; closing the book stops it", function()
    show(fx.BOOK_TITLE, 1, fx.PAGE1_A)
    show(fx.BOOK_TITLE, 2, fx.PAGE2)
    assert.same({ 1 }, wow.stopped)
    assert.equals(fx.FILE_2, wow.sounds[2].path)
    show(fx.BOOK_TITLE, 2, fx.PAGE2) -- the same page again: nothing new
    assert.equals(2, #wow.sounds)
    wow.fire("ITEM_TEXT_CLOSED")
    assert.same({ 1, 2 }, wow.stopped)
    assert.is_nil(Player.Current())
  end)

  it("a page without audio is read by the speech synthesis (fallback tts), nothing with fallback none", function()
    show(fx.BOOK_TITLE, 3, fx.PAGE3)
    assert.equals(fx.PAGE3, spoken)
    wow.fire("ITEM_TEXT_CLOSED")
    spoken = nil
    ForeverSpeechDB.fallback = "none"
    show("Plaque commémorative", 1, "Ici repose un héros.")
    assert.is_nil(spoken)
    assert.equals(0, #wow.sounds)
  end)

  it("waits behind a quest; a page turned meanwhile replaces the waiting one", function()
    Player.PlayQuest(5) -- the test sound
    show(fx.BOOK_TITLE, 1, fx.PAGE1_A)
    show(fx.BOOK_TITLE, 2, fx.PAGE2)
    local queue = Player.Queue()
    assert.equals(1, #queue)
    assert.equals("Le Livre de Tirion — page 2", ForeverSpeech.Index.Line("book", queue[1].lineID).name)
  end)

  it("speaks and shows a page written in HTML without its tags", function()
    show("Introduction", 1,
      '<HTML><BODY><H1 align="center">Introduction</H1><P>Le Brasier &amp; la Lame.</P></BODY></HTML>')
    assert.equals("Introduction\n\nLe Brasier & la Lame.", spoken)
  end)

  it("ignores letters: from a player, or read at the mailbox", function()
    show("Une lettre", 1, "Salut !", "Bob")
    _G.MailFrame = { IsShown = function() return true end }
    show(fx.BOOK_TITLE, 1, fx.PAGE1_A)
    assert.equals(0, #wow.sounds)
    assert.is_nil(next(ForeverSpeechCaptures.books or {}))
  end)

  it("captures every page shown, once per text, even when reading is off", function()
    ForeverSpeechDB.readBooks = false
    show(fx.BOOK_TITLE, 1, fx.PAGE1_A)
    show(fx.BOOK_TITLE, 1, fx.PAGE1_A)
    show(fx.BOOK_TITLE, 2, fx.PAGE2)
    assert.equals(0, #wow.sounds)
    local book = ForeverSpeechCaptures.books.lelivredetirion
    assert.equals(fx.BOOK_TITLE, book.title)
    assert.equals(2, book.pages[1][1].seen)
    assert.equals(fx.PAGE1_A, book.pages[1][1].text)
    assert.equals("Hinterlands", book.pages[1][1].zone)
    assert.equals(fx.PAGE2, book.pages[2][1].text)
    wow.slash("books")
    assert.matches("1 book%(s%), 2 page%(s%) captured; 1 book%(s%) in the index", wow.chatText())
  end)
end)
