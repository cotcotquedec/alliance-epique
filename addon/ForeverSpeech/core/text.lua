-- ForeverSpeech: the text normalisation shared with the pipeline (index contract v9, 2026-10-21). Byte level, and
-- byte-identical to the Python side (pipeline/match.py: fs_norm, fs_key, fs_fp): a book page or an NPC dialogue shown
-- in game is matched against the index by these keys. In the order of pipeline/match.py:
--   0. the French typographic characters ’ « » … – — and the non-breaking spaces U+00A0, U+202F become a space;
--   1. $B / $b and |n -> a space; colour codes |cAARRGGBB and |r dropped;
--   2. the variables of the base text dropped: the gender construct $g<male>:<female>; ($G too), then $N $C $R (any
--      case); in game the client has already replaced them (the dialogue matching removes the player's words instead);
--   3. ASCII A-Z lowercased, bytes >= 128 (UTF-8 accents) untouched;
--   4. every ASCII whitespace or punctuation byte (Python string.whitespace + string.punctuation, Lua %s %p in the C
--      locale, written out as byte ranges here so that no locale can change them) separates the tokens.
local H = ForeverSpeech

local Text = {}
H.Text = Text

local FP_BYTES = 48

-- ’ « » … – — U+00A0 U+202F, in UTF-8
local TYPOGRAPHIC = { "\226\128\153", "\194\171", "\194\187", "\226\128\166", "\226\128\147", "\226\128\148",
  "\194\160", "\226\128\175" }

-- A token: a run of bytes that are neither ASCII whitespace (9-13, 32) nor ASCII punctuation (33-47, 58-64, 91-96,
-- 123-126).
local TOKEN = "[^\9-\13\32-\47\58-\64\91-\96\123-\126]+"

local function plain(s)
  return (s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"))
end

local function lowerASCII(c)
  return string.char(c:byte() + 32)
end

-- The tokens of a text, in order (an empty list for anything but a string).
function Text.Tokens(s)
  if type(s) ~= "string" then
    return {}
  end
  for _, mark in ipairs(TYPOGRAPHIC) do
    s = s:gsub(plain(mark), " ")
  end
  s = s:gsub("%$[Bb]", " "):gsub("|n", " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  s = s:gsub("%$[gG][^:;]*:[^;]*;", ""):gsub("%$[NnCcRr]", "")
  s = s:gsub("[A-Z]", lowerASCII)
  local tokens = {}
  for token in s:gmatch(TOKEN) do
    tokens[#tokens + 1] = token
  end
  return tokens
end

-- fs_norm joined by single spaces: the `words` of a dialogue page.
function Text.Words(s)
  return table.concat(Text.Tokens(s), " ")
end

-- fs_key: the tokens joined with no separator (a book's title).
function Text.Key(s)
  return table.concat(Text.Tokens(s))
end

-- fs_fp: the first 48 bytes of fs_key, cut at a UTF-8 character boundary (a page's fingerprint).
function Text.Fp(s)
  local key = Text.Key(s)
  if #key <= FP_BYTES then
    return key
  end
  local cut = FP_BYTES
  while cut > 0 do
    local nextByte = key:byte(cut + 1)
    if nextByte < 128 or nextByte >= 192 then -- the next byte starts a character: the cut is at a boundary
      break
    end
    cut = cut - 1
  end
  return key:sub(1, cut)
end
