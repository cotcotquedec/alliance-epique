-- ForeverSpeech: books and plaques read by Elise (D19, 2026-10-21). Each page shown (ITEM_TEXT_READY, on opening and
-- on every page turned) is captured, then read: her audio from the index (v9, books[H.Text.Key(title)].pages[page],
-- the entry whose fp is H.Text.Fp(text), else the only one), else the fallback of the quests (/fs fallback tts: the
-- client's speech synthesis on the page text). A page goes in the play list as a line of kind "book"; turning the
-- page stops it and reads the next one; closing the book stops it (Player.PlayPage, Player.StopPages). Setting
-- readBooks (on by default), /fs books. A letter (from a player, the mail) is neither read nor captured.
-- Unverified on Forever: ITEM_TEXT_BEGIN, ITEM_TEXT_READY, ITEM_TEXT_CLOSED, ItemTextGetItem (the title),
-- ItemTextGetPage, ItemTextGetText, ItemTextGetCreator (non-nil for a letter), MailFrame (seen in Spoken, MIT).
local H = ForeverSpeech

local Books = {}
H.Books = Books

local lines = {} -- line ID -> { name, text, intro, title, page, key }
local ids = {}   -- "<book key>#<page>#<fp>" -> line ID
local lastID = 0

local function capturesStore()
  ForeverSpeechCaptures.books = ForeverSpeechCaptures.books or {}
  return ForeverSpeechCaptures.books
end

-- A letter: written by a player (ItemTextGetCreator) or read from the mailbox.
local function isLetter(creator)
  if creator ~= nil and creator ~= "" then
    return true
  end
  local mail = _G.MailFrame
  return type(mail) == "table" and H.Safe(mail.IsShown, mail) and true or false
end

-- The page shown: { title, page, text, letter }, or nil when there is no text.
function Books.Read()
  local text = H.Safe(ItemTextGetText)
  if type(text) ~= "string" or text == "" then
    return nil
  end
  return {
    title = H.Safe(ItemTextGetItem),
    page = tonumber(H.Safe(ItemTextGetPage)) or 1,
    text = text,
    letter = isLetter(H.Safe(ItemTextGetCreator)),
  }
end

-- The index entry of a page ({fp, intro}) and its book, per contract v9.
function Books.Lookup(title, page, text)
  local book = H.Index.Book(H.Text.Key(title))
  if not book then
    return nil
  end
  local list = type(book.pages) == "table" and book.pages[tonumber(page) or -1]
  if type(list) ~= "table" then
    return nil, book
  end
  local fp = H.Text.Fp(text)
  for _, entry in ipairs(list) do
    if entry.fp == fp then
      return entry, book
    end
  end
  if #list == 1 then
    return list[1], book
  end
  return nil, book
end

-- Keeps every page shown, for the Forever-only books to be generated later: ForeverSpeechCaptures.books[<key of the
-- title>] = { title, pages = { [page] = { {text, hash, zone, subZone, mapID, locale, client, firstSeen, lastSeen,
-- seen}, ... } } }, deduplicated by text hash. Returns true when the text was new.
function Books.Capture(page)
  local key = H.Text.Key(page.title)
  local store = capturesStore()
  local book = store[key] or { title = page.title, pages = {} }
  store[key] = book
  book.pages[page.page] = book.pages[page.page] or {}
  local list = book.pages[page.page]
  local hash = H.Capture.Hash(page.text)
  local now = time()
  for _, rec in ipairs(list) do
    if rec.hash == hash then
      rec.seen = (rec.seen or 1) + 1
      rec.lastSeen = now
      return false
    end
  end
  local version, build = GetBuildInfo()
  list[#list + 1] = {
    text = page.text,
    hash = hash,
    zone = H.Safe(GetZoneText),
    subZone = H.Safe(GetSubZoneText),
    mapID = C_Map and H.Safe(C_Map.GetBestMapForUnit, "player"),
    locale = H.Safe(GetLocale),
    client = tostring(version) .. "." .. tostring(build),
    firstSeen = now,
    lastSeen = now,
    seen = 1,
  }
  return true
end

-- The text to show and to speak: some pages are written in HTML (<HTML><BODY><H1>...): the tags go, the matching
-- keeps the raw text (as the pipeline does).
function Books.PlainText(text)
  local plain = tostring(text or ""):gsub("<[^<>]*>", "\n"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
  return (plain:gsub("\n%s*\n[%s\n]*", "\n\n"):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The line of a page shown, kept for the session: the same page gets the same ID.
function Books.Register(page)
  local entry, book = Books.Lookup(page.title, page.page, page.text)
  local key = H.Text.Key(page.title)
  local fp = entry and entry.fp or H.Text.Fp(page.text)
  local idKey = key .. "#" .. page.page .. "#" .. fp
  local id = ids[idKey]
  if not id then
    lastID = lastID + 1
    id = lastID
    ids[idKey] = id
  end
  local title = (book and book.title) or page.title or "?"
  lines[id] = {
    name = string.format(H.L.BOOK_PAGE, title, page.page),
    title = title,
    page = page.page,
    key = key,
    text = Books.PlainText(page.text),
    intro = entry and entry.intro or nil,
  }
  return id, lines[id]
end

-- { name, text, intro } of a page's line (Index.Line("book", id)).
function Books.Line(id)
  return lines[tonumber(id) or -1]
end

-- A page is shown: captured, then read (setting readBooks). Returns a status for the trace and the tests: "none",
-- "letter", "off" or the Player.PlayPage status.
function Books.Shown()
  local page = Books.Read()
  if not page then
    return "none"
  end
  if page.letter then
    H.Trace("books: a letter, ignored")
    return "letter"
  end
  local new = Books.Capture(page)
  if not ForeverSpeechDB.readBooks or not H.IsEnabled() then
    return "off"
  end
  local id, line = Books.Register(page)
  local status, detail = H.Player.PlayPage("book", id, H.Player.AUTO)
  H.Trace("books: %s p%s new=%s audio=%s: %s %s", line.title, page.page, new, line.intro ~= nil, status, detail)
  return status, detail
end

function Books.Closed()
  return H.Player.StopPages("book")
end

H.TryRegisterEvent("ITEM_TEXT_READY", function()
  Books.Shown()
end)
H.TryRegisterEvent("ITEM_TEXT_CLOSED", Books.Closed)

-- Captured books and pages, and how many books the index knows.
function Books.Counts()
  local books, pages = 0, 0
  for _, book in pairs(ForeverSpeechCaptures.books or {}) do
    books = books + 1
    for _ in pairs(book.pages or {}) do
      pages = pages + 1
    end
  end
  local indexed = 0
  if H.Index.IsValid() and type(ForeverSpeechIndex.books) == "table" then
    for _ in pairs(ForeverSpeechIndex.books) do
      indexed = indexed + 1
    end
  end
  return books, pages, indexed
end

H.RegisterCommand("books", function(arg)
  arg = (arg or ""):lower()
  if arg == "on" or arg == "off" then
    ForeverSpeechDB.readBooks = arg == "on"
  end
  local books, pages, indexed = Books.Counts()
  H.Print("books read by Elise: %s. %d book(s), %d page(s) captured; %d book(s) in the index.",
    ForeverSpeechDB.readBooks and "on" or "off", books, pages, indexed)
end, "books [on|off] - books and plaques read by Elise, and the captured pages")
