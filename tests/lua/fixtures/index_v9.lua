-- A small index of contract v9 (books and dialogues), as pipeline/build_index.py writes it: the keys, fingerprints
-- and words are written out by hand from the contract's rules, so that the specs check H.Text against them.
local M = {}

local AUDIO = "Interface\\AddOns\\ForeverSpeech\\audio\\"

M.BOOK_TITLE = "Le Livre de Tirion"
M.PAGE1_A = "Il était une fois un paladin nommé Tirion Fordring, qui vivait près de Hearthglen."
M.PAGE1_B = "Un autre livre porte ce titre, mais son histoire est différente."
M.PAGE2 = "Le texte de la page deux a changé depuis la base."
M.PAGE3 = "Une page sans audio."
M.FILE_A = AUDIO .. "1000000\\book_101.ogg"
M.FILE_B = AUDIO .. "1000000\\book_201.ogg"
M.FILE_2 = AUDIO .. "1000000\\book_102.ogg"

M.NPC = 233
M.FILE_HELLO = AUDIO .. "233\\dialogue_4710.ogg"
M.FILE_HELLO_F = AUDIO .. "233\\dialogue_4710_f.ogg"
M.FILE_WOLVES = AUDIO .. "233\\dialogue_4711.ogg"
M.FILE_NIGHT = AUDIO .. "233\\dialogue_4712.ogg"

local function elise(file)
  return { npc = 1000000, voice = "npc1000000@G6INpmIs", file = file, dur = 12.5, src = "elise" }
end

function M.build()
  return {
    version = 9,
    quests = {},
    npcs = {
      [1000000] = { name = "Elise" },
      [233] = { display = 3258, name = "Fermier Saldean" },
    },
    books = {
      lelivredetirion = {
        title = "Le Livre de Tirion",
        pages = {
          [1] = {
            { fp = "ilétaitunefoisunpaladinnommétirionfordringquiv", intro = elise(M.FILE_A) },
            { fp = "unautrelivreportecetitremaissonhistoireestdiffé", intro = elise(M.FILE_B) },
          },
          [2] = { { fp = "letextedelapagedeuxtelquilestdanslabase", intro = elise(M.FILE_2) } },
          [3] = { { fp = "unepagesansaudio" } },
        },
      },
    },
    dialogues = {
      [233] = {
        { page = "4710", words = "bonjour que puis je faire pour vous",
          intro = { npc = 233, voice = "npc233@v1", file = M.FILE_HELLO, fileF = M.FILE_HELLO_F, dur = 3.1,
                    src = "qwen" } },
        { page = "4711", words = "les loups rôdent près de la ferme restez sur vos gardes",
          intro = { npc = 233, voice = "npc233@v1", file = M.FILE_WOLVES, dur = 5.2, src = "qwen" } },
        { page = "4712", words = "salut la nuit tombe",
          intro = { npc = 233, voice = "npc233@v1", file = M.FILE_NIGHT, dur = 2.0, src = "qwen" } },
      },
    },
  }
end

return M
