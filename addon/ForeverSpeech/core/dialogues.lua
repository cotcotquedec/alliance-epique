-- ForeverSpeech: NPC dialogues read in their voice (D14, read in game since 2026-10-21). When an NPC's gossip window
-- opens (GOSSIP_SHOW, then GOSSIP_DELAY s for the text to settle), its text is matched against the NPC's pages of the
-- index (v9, dialogues[npcID]): the shown text's tokens (H.Text) minus the player's name, class and race, then the
-- page whose `words` are the same, else the page with the best share of its tokens found in the shown text, at least
-- MIN_SCORE (Spoken's threshold, idea from Spoken (MIT)); a tie goes to the page closest in length, then the first.
-- The page plays as a line of kind "gossip" (Player.PlayPage: the next page replaces it); closing the window stops it.
-- Only pages with audio: no speech synthesis for a dialogue (too many NPCs talk). The capture (core/capture.lua) goes
-- on. Setting readGossip (on by default), /fs gossip on|off. The game's own greeting of an NPC that has a dialogue
-- with audio is muted like a quest NPC's (core/game_voices.lua).
-- C_GossipInfo.GetText: verified on Forever (318 captures). Unverified: the matching on real NPCs (docs/ingame).
local H = ForeverSpeech

local Dialogues = {}
H.Dialogues = Dialogues

local GOSSIP_DELAY = 0.1
local MIN_SCORE = 0.7
-- A page's `words` keeps its first MAX_WORDS tokens (pipeline/match.py, index size): a page cut there is the same as
-- the shown text's first MAX_WORDS tokens.
local MAX_WORDS = 40

local lines = {} -- line ID -> { name, text, intro, npcID, page, noTTS }
local ids = {}   -- "<npcID>#<page>" -> line ID
local lastID = 0
local token = 0  -- cancels a pending check when the window closes or opens again

local function split(words)
  local tokens = {}
  for token_ in tostring(words or ""):gmatch("[^ ]+") do
    tokens[#tokens + 1] = token_
  end
  return tokens
end

-- The player's words the client put in the text ($N, $C, $R): their token sequences.
local function playerPhrases()
  local phrases = {}
  local function add(text)
    local tokens = H.Text.Tokens(H.NotSecret(text))
    if #tokens > 0 then
      phrases[#phrases + 1] = tokens
    end
  end
  add(H.Safe(UnitName, "player"))
  local className, classFile = H.Safe(UnitClass, "player")
  add(className)
  local female = _G.LOCALIZED_CLASS_NAMES_FEMALE
  if type(female) == "table" and classFile then
    add(female[classFile])
  end
  add(H.Safe(UnitRace, "player"))
  return phrases
end

-- Tokens minus every occurrence of the phrases (a race of three words leaves as a whole, not word by word).
local function without(tokens, phrases)
  local out, i = {}, 1
  while i <= #tokens do
    local skip = 0
    for _, phrase in ipairs(phrases) do
      local match = true
      for j = 1, #phrase do
        if tokens[i + j - 1] ~= phrase[j] then
          match = false
          break
        end
      end
      if match and #phrase > skip then
        skip = #phrase
      end
    end
    if skip > 0 then
      i = i + skip
    else
      out[#out + 1] = tokens[i]
      i = i + 1
    end
  end
  return out
end

-- The shown text's tokens, the player's words removed.
function Dialogues.ShownTokens(text)
  return without(H.Text.Tokens(text), playerPhrases())
end

-- The index page of an NPC that the shown text is, and its score (1 for the same words), or nil.
function Dialogues.Match(npcID, text)
  local pages = H.Index.Dialogues(npcID)
  if type(pages) ~= "table" or type(text) ~= "string" then
    return nil
  end
  local shown = Dialogues.ShownTokens(text)
  local words = table.concat(shown, " ")
  local prefix = table.concat(shown, " ", 1, math.min(#shown, MAX_WORDS))
  for _, page in ipairs(pages) do
    local cut = #split(page.words) >= MAX_WORDS
    if page.words == (cut and prefix or words) then
      return page, 1
    end
  end
  local present = {}
  for _, t in ipairs(shown) do
    present[t] = true
  end
  local best, bestScore, bestGap
  for _, page in ipairs(pages) do
    local base = split(page.words)
    if #base > 0 then
      local found = 0
      for _, t in ipairs(base) do
        if present[t] then
          found = found + 1
        end
      end
      local score, gap = found / #base, math.abs(#base - #shown)
      if not best or score > bestScore or (score == bestScore and gap < bestGap) then
        best, bestScore, bestGap = page, score, gap
      end
    end
  end
  if best and bestScore >= MIN_SCORE then
    return best, bestScore
  end
  return nil, bestScore
end

-- True when the NPC has a dialogue page with audio and the dialogues are read: its greeting is muted.
function Dialogues.HasAudio(npcID)
  if not ForeverSpeechDB.readGossip or not H.IsEnabled() or not npcID then
    return false
  end
  for _, page in ipairs(H.Index.Dialogues(npcID) or {}) do
    if page.intro then
      return true
    end
  end
  return false
end

-- The line of an NPC's page, kept for the session: the same page gets the same ID.
function Dialogues.Register(npcID, page, text, name)
  local idKey = npcID .. "#" .. tostring(page.page)
  local id = ids[idKey]
  if not id then
    lastID = lastID + 1
    id = lastID
    ids[idKey] = id
  end
  local npc = H.Index.NPC(npcID)
  lines[id] = {
    name = (npc and npc.name) or name or ("#" .. npcID),
    text = text,
    intro = page.intro,
    npcID = npcID,
    page = page.page,
    noTTS = true,
  }
  return id, lines[id]
end

-- { name, text, intro } of a dialogue's line (Index.Line("gossip", id)).
function Dialogues.Line(id)
  return lines[tonumber(id) or -1]
end

local function gossipText()
  local G = C_GossipInfo
  local text = G and H.Safe(G.GetText)
  if type(text) ~= "string" or text == "" then
    text = H.Safe(GetGossipText)
  end
  return type(text) == "string" and text ~= "" and text or nil
end

-- The gossip window shows a page: read it in the NPC's voice if it is in the index with audio. Returns a status for the
-- trace and the tests: "off", "no npc", "no text", "unknown" (no page matches) or the Player.PlayPage status.
function Dialogues.Check()
  if not ForeverSpeechDB.readGossip or not H.IsEnabled() then
    return "off"
  end
  local unitType, npcID = H.Capture.ParseGUID(H.Safe(UnitGUID, "npc"))
  if unitType ~= "Creature" or not npcID then
    return "no npc"
  end
  local text = gossipText()
  if not text then
    return "no text"
  end
  local page, score = Dialogues.Match(npcID, text)
  if not (page and page.intro) then
    H.Trace("dialogues: npc %s, no page (best score %s)", npcID, score)
    return "unknown"
  end
  local id = Dialogues.Register(npcID, page, text, H.Safe(UnitName, "npc"))
  local status, detail = H.Player.PlayPage("gossip", id, H.Player.AUTO)
  H.Trace("dialogues: npc %s page %s score %s: %s %s", npcID, page.page, score, status, detail)
  return status, detail
end

H.TryRegisterEvent("GOSSIP_SHOW", function()
  token = token + 1
  local mine = token
  C_Timer.After(GOSSIP_DELAY, function()
    if mine == token then
      Dialogues.Check()
    end
  end)
end)

H.TryRegisterEvent("GOSSIP_CLOSED", function()
  token = token + 1
  H.Player.StopPages("gossip")
end)

-- Index pages, NPCs with audio.
function Dialogues.Counts()
  local npcs, pages = 0, 0
  if H.Index.IsValid() and type(ForeverSpeechIndex.dialogues) == "table" then
    for _, list in pairs(ForeverSpeechIndex.dialogues) do
      npcs = npcs + 1
      pages = pages + #list
    end
  end
  return npcs, pages
end
