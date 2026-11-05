-- ForeverSpeech: lookup in the generated index (data/index.lua, contract in CLAUDE.md section 8).
local H = ForeverSpeech

local Index = {}
H.Index = Index

local SUPPORTED_VERSION = 9 -- v3 (2026-10-06): part "complete" and the ender; v4 (2026-10-10): the narrator;
-- v5 (2026-10-11): zones, the zone introductions of Elise; v6 (2026-10-11): levels, her level-up lines;
-- v7 (2026-10-14): the level of each quest; v8 (2026-10-15): companions, the friendship tiers and Elise's lines;
-- v9 (2026-10-21): books (pages read by Elise, D19) and dialogues (the NPCs' gossip pages, D14)
-- v9 only adds sections: a v8 index still works, without books and dialogues.
local OLDEST_VERSION = 8

function Index.IsValid()
  local idx = ForeverSpeechIndex
  return type(idx) == "table" and type(idx.version) == "number" and idx.version >= OLDEST_VERSION
    and idx.version <= SUPPORTED_VERSION and type(idx.quests) == "table"
end

-- Returns the entry for (questID, kind) or nil. kind: "detail" (acceptance, default) or "complete" (turn-in).
function Index.Lookup(questID, kind)
  if not Index.IsValid() then
    return nil
  end
  local quest = ForeverSpeechIndex.quests[tonumber(questID) or -1]
  return quest and quest[kind or "detail"] or nil
end

-- Giver NPC id of a quest (from the Wowhead registries), or nil.
function Index.Giver(questID)
  if not Index.IsValid() then
    return nil
  end
  local quest = ForeverSpeechIndex.quests[tonumber(questID) or -1]
  return quest and quest.giver or nil
end

-- Ender NPC id of a quest (the NPC it is turned in to, from the Wowhead registries), or nil.
function Index.Ender(questID)
  if not Index.IsValid() then
    return nil
  end
  local quest = ForeverSpeechIndex.quests[tonumber(questID) or -1]
  return quest and quest.ender or nil
end

-- Level of a quest (v7, from the registries: the Forever Database), or nil.
function Index.QuestLevel(questID)
  if not Index.IsValid() then
    return nil
  end
  local quest = ForeverSpeechIndex.quests[tonumber(questID) or -1]
  return quest and tonumber(quest.level) or nil
end

-- { display, name } of an NPC, or nil. display feeds SetDisplayInfo, which works for any NPC (S8).
function Index.NPC(npcID)
  if not Index.IsValid() or type(ForeverSpeechIndex.npcs) ~= "table" then
    return nil
  end
  return ForeverSpeechIndex.npcs[tonumber(npcID) or -1]
end

-- fileF when the player is female (UnitSex 3) and a feminine variant exists (D8), else file.
-- The voices (2026-11-05): shipped apart from the addon, in their own folder next to it, AllianceEpique_Voix (a TOC
-- and audio\): an update of the addon replaces its folder (CurseForge's app does), the voices stay. The index names
-- files in the addon's folder; with the voices' folder installed, the same files are read there; without it, in the
-- addon's own folder (the developer's setup, audio generated in place). Asked once (the client lists its addons at
-- startup: a folder added while the game runs counts after a restart). Unverified on Forever: T69 (H43).
local VOICES = "AllianceEpique_Voix"
local OWN_AUDIO = "Interface\\AddOns\\ForeverSpeech\\audio\\"
local VOICES_AUDIO = "Interface\\AddOns\\" .. VOICES .. "\\audio\\"
local voicesInstalled -- nil until asked

-- True when the voices' folder is installed (C_AddOns.DoesAddOnExist, else the addon's info).
function Index.VoicesInstalled()
  if voicesInstalled == nil then
    local addons = _G.C_AddOns
    local exists = type(addons) == "table" and addons.DoesAddOnExist
    if type(exists) == "function" then
      voicesInstalled = H.Safe(exists, VOICES) == true
    else
      local info = type(addons) == "table" and addons.GetAddOnInfo or _G.GetAddOnInfo
      local name, _, _, _, reason = H.Safe(info, VOICES)
      voicesInstalled = name ~= nil and reason ~= "MISSING"
    end
    H.Trace("index: voices folder %s", voicesInstalled and "installed" or "absent")
  end
  return voicesInstalled
end

-- The file of an audio entry for this character (the feminine one for a female character), in the voices' folder
-- when it is installed.
function Index.FileFor(entry)
  local file = entry.file
  if entry.fileF and UnitSex("player") == 3 then
    file = entry.fileF
  end
  if type(file) == "string" and file:sub(1, #OWN_AUDIO) == OWN_AUDIO and Index.VoicesInstalled() then
    return VOICES_AUDIO .. file:sub(#OWN_AUDIO + 1)
  end
  return file
end

-- Zone introductions (v5, 2026-10-11) -----------------------------------------------------------------------------

-- { area, name, nameEn, text, intro = audio entry or nil } of a zone by the client's map ID, or nil.
function Index.Zone(mapID)
  if not Index.IsValid() or type(ForeverSpeechIndex.zones) ~= "table" then
    return nil
  end
  return ForeverSpeechIndex.zones[tonumber(mapID) or -1]
end

local function normalize(name)
  return type(name) == "string" and name:lower():gsub("[%s'’%-]", "") or nil
end

-- Map ID and entry of a zone by its name (French or English, as GetZoneText gives it), or nil. The fallback when
-- the client gives no map ID (C_Map unverified on Forever: spike S12).
function Index.ZoneByName(name)
  local wanted = normalize(name)
  if not wanted or wanted == "" or not Index.IsValid() or type(ForeverSpeechIndex.zones) ~= "table" then
    return nil
  end
  for mapID, zone in pairs(ForeverSpeechIndex.zones) do
    if normalize(zone.name) == wanted or normalize(zone.nameEn) == wanted then
      return mapID, zone
    end
  end
  return nil
end

-- { text, intro = audio entry or nil } of her line for a level gained (v6), with name "Niveau <n>", or nil.
function Index.Level(level)
  if not Index.IsValid() or type(ForeverSpeechIndex.levels) ~= "table" then
    return nil
  end
  local entry = ForeverSpeechIndex.levels[tonumber(level) or -1]
  if entry and not entry.name then
    entry.name = string.format(H.L.LEVEL_TITLE, tonumber(level))
  end
  return entry
end

-- Companions (v8, 2026-10-15, D18) -------------------------------------------------------------------------------

-- The friendship tiers in order: { {key, name, nameF, from, rank}, ... } (from: seconds together; rank 1: the best
-- friend, the first of the table), or an empty list.
function Index.CompanionTiers()
  if not Index.IsValid() or type(ForeverSpeechIndex.companions) ~= "table" then
    return {}
  end
  return ForeverSpeechIndex.companions.tiers or {}
end

-- { tier, text, intro = audio entry or nil } of Elise's companion line by its ID (tier place x 100 + variant), with
-- name: the companion and the tier it reached when one was announced (H.Companions), else the tier's name.
function Index.Companion(id)
  if not Index.IsValid() or type(ForeverSpeechIndex.companions) ~= "table" then
    return nil
  end
  local entry = (ForeverSpeechIndex.companions.lines or {})[tonumber(id) or -1]
  if entry then
    local tier = Index.CompanionTiers()[math.floor((tonumber(id) or 0) / 100)]
    entry.name = H.Companions and H.Companions.Announced(id) or (tier and tier.name) or entry.tier
  end
  return entry
end

-- Books and dialogues (v9, 2026-10-21) --------------------------------------------------------------------------

-- { title, pages = { [page] = { {fp, intro}, ... } } } of a book by its key (H.Text.Key of its title), or nil.
function Index.Book(key)
  if not Index.IsValid() or type(ForeverSpeechIndex.books) ~= "table" or type(key) ~= "string" then
    return nil
  end
  return ForeverSpeechIndex.books[key]
end

-- { {page, words, intro}, ... } of an NPC's gossip pages that have audio, or nil.
function Index.Dialogues(npcID)
  if not Index.IsValid() or type(ForeverSpeechIndex.dialogues) ~= "table" then
    return nil
  end
  return ForeverSpeechIndex.dialogues[tonumber(npcID) or -1]
end

-- A line by kind: Elise's "zone" (map ID), "level" or "companion" (line ID); a "book" page or a "gossip" page (the
-- session's line IDs of core/books.lua and core/dialogues.lua).
function Index.Line(kind, id)
  if kind == "zone" then
    return Index.Zone(id)
  elseif kind == "level" then
    return Index.Level(id)
  elseif kind == "companion" then
    return Index.Companion(id)
  elseif kind == "book" then
    return H.Books and H.Books.Line(id)
  elseif kind == "gossip" then
    return H.Dialogues and H.Dialogues.Line(id)
  end
  return nil
end
