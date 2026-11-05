-- ForeverSpeech: namespace, logging and /fs command dispatch.
-- The only global owned by the addon is the `ForeverSpeech` table (plus the slash command
-- registration globals that the WoW API requires).
local ADDON_NAME = ...

ForeverSpeech = ForeverSpeech or {}
local H = ForeverSpeech

H.name = ADDON_NAME or "ForeverSpeech"
-- The name the player sees (2026-11-05, the public name); the folder, the globals and /fs keep ForeverSpeech.
H.TITLE = "Alliance Épique"
H.version = "0.3.0"

local PREFIX = "|cff4fa3e0" .. H.TITLE .. "|r: "

H.MEDIA = "Interface\\AddOns\\ForeverSpeech\\media\\"

-- UI strings (the addon targets frFR; commands and logs stay in English).
H.L = {
  SPEECH_OBJECTIVE = "Objectif : ",
  OBJECTIVES = "Objectifs",
  PARTY_PROGRESS = "Le groupe",
  REWARDS = "Récompenses",
  CHOICES = "Au choix",
  XP = "%d XP",
  STATUS_PLAYING = "En lecture",
  STATUS_IDLE = "À l'arrêt",
  STATUS_QUEUE = "%d en attente",
  STATUS_QUEUED = "En attente (position %d)",
  NO_TEXT = "Texte indisponible : ouvrez la quête auprès du PNJ pour la capturer.",
  TOOLTIP_PLAY = "Écouter la quête",
  TOOLTIP_STOP = "Arrêter la lecture",
  TOOLTIP_PLAY_FROM_START = "Lecture (depuis le début)",
  TOOLTIP_NEXT = "Avancer : quête suivante de la liste",
  TOOLTIP_HINT = "Clic droit : ouvrir le lecteur",
  SIDE_TAB_COMBAT = "Indisponible en combat",
  FISHING = "Pêche",
  FISHING_ON = "Mode pêche activé",
  FISHING_CLICK_ON = "Clic : équiper la canne à pêche.",
  FISHING_CLICK_OFF = "Clic : remettre vos armes et ranger la canne.",
  FISHING_COMBAT = "Mode pêche : indisponible en combat.",
  FISHING_UNKNOWN = "Mode pêche : votre personnage ne connaît pas la pêche.",
  FISHING_NO_POLE = "Mode pêche : pas de canne à pêche dans vos sacs.",
  -- disenchant mode (2026-10-18, ui/bag_tabs.lua)
  DISENCHANT = "Désenchantement",
  DISENCHANT_CLICK_ON = "Clic : lancer le sort, puis cliquer l'objet. Les objets à désenchanter ressortent en doré.",
  DISENCHANT_COUNT = "%d objet(s) à désenchanter dans vos sacs.",
  PROFESSION_CLICK = "Clic : ouvrir la fenêtre du métier.",
  -- a profession's place not nearby, as the game says (2026-11-05): the tab is greyed, the click still opens it
  PLACE_FIRE = "Pas de feu de cuisine à proximité : les recettes en demandent un.",
  PLACE_FORGE = "Pas de forge à proximité : la fonte en demande une.",
  PLACE_ANVIL = "Pas d'enclume à proximité : la plupart des recettes en demandent une.",
  DISENCHANT_UNKNOWN = "Désenchantement : votre personnage ne connaît pas le désenchantement.",
  -- the backpack's frame moved (2026-10-20, ui/bag_frame.lua)
  BAG_MOVED = "Sac à dos : à la place où vous l'avez posé (/fs bag reset pour le remettre à sa place).",
  BAG_DEFAULT = "Sac à dos : à la place du jeu. Faites-le glisser par son bord ou son titre pour le déplacer.",
  BAG_RESET_DONE = "Sac à dos remis à la place du jeu.",
  BAG_BACKPACK = "Sac à dos",
  BAG_N = "Sac %d",
  BAG_HEADER = "%s · %d cases",
  BAG_FREE = "%d libre(s)",
  EMOTE_HELLO = "Saluer",
  EMOTE_THANKS = "Remercier",
  EMOTE_SIT = "S'asseoir",
  EMOTE_CONGRATS = "Féliciter",
  EMOTE_APPLAUD = "Applaudir",
  EMOTE_LAUGH = "Rire",
  EMOTE_DANCE = "Danser",
  EMOTE_BOW = "S'incliner",
  COMPANION_TIER = "%s devient votre %s.",
  COMPANION_ENCOUNTERS = "Rencontre : %s.",
  OPT_COMPANION_LINES = "Elise salue chaque palier d'amitié de vos compagnons",
  PART_COMPANION = "Palier d'amitié",
  COMPANIONS = "Compagnons",
  COMPANION_SUMMARY = "Un lien de plus sur votre route : Elise le salue.",
  COMPANIONS_HINT = "Les joueurs avec qui vous groupez le plus.",
  COMPANIONS_CLOSE = "Clic : fermer la fenêtre des compagnons.",
  COMPANIONS_EMPTY = "Personne pour l'instant. Groupez-vous : le temps passé ensemble s'affiche ici.",
  COMPANIONS_GROUP_TIME = "En groupe : %s",
  COMPANIONS_COUNT = "%d compagnon(s)",
  COMPANION_TOGETHER = "%s ensemble",
  COMPANION_SHARE_PLAYED = "%d %% de votre temps de jeu",
  COMPANION_SHARE_GROUP = "%d %% de votre temps en groupe",
  COMPANION_GROUPS = "%d groupe(s)",
  COMPANION_LONGEST = "plus longue session : %s",
  COMPANION_MET = "Rencontre : le %s, %s, à votre niveau %d",
  COMPANION_LAST = "Dernière fois ensemble : le %s",
  COMPANION_DONE = "Ensemble : %d donjon(s), %d quête(s) rendue(s), %d niveau(x) gagné(s)",
  COMPANION_PICK = "Cliquez sur un nom pour voir vos statistiques ensemble.",
  COMPANION_TIME = "Temps ensemble : %s",
  COMPANION_PLAYED_SHARE = "Part de votre temps de jeu : %d %%",
  COMPANION_GROUP_SHARE = "Part de votre temps en groupe : %d %%",
  COMPANION_GROUP_COUNT = "Groupes : %d",
  COMPANION_LONGEST_SESSION = "Plus longue session : %s",
  OPTIONS_OPEN = "Options",
  OPTIONS_CLOSE = "Fermer les options",
  OPTIONS_IN_COMBAT = "Les options du jeu s'ouvriront après le combat : réessayez à ce moment-là.",
  OPT_PAGE_GENERAL = "Général",
  OPT_PAGE_READING = "Lecture des quêtes",
  OPT_PAGE_WINDOW = "Fenêtre de quête",
  OPT_PAGE_ELISE = "Elise",
  OPT_PAGE_COMPANIONS = "Compagnons",
  OPT_PAGE_COMFORT = "Confort",
  OPT_PAGE_ADVANCED = "Avancé",
  OPT_SHOW_QUEST_LEVEL = "Niveau de la quête dans le titre, en couleur",
  OPT_DOCK_FLARE = "Accrocher la fenêtre au suivi des quêtes de FlareUI",
  HOME_DOCK = "Remettre la fenêtre contre le suivi des quêtes",
  HOME_RESET = "Remettre la fenêtre à sa place",
  HOME_HINT = "La fenêtre se déplace en la faisant glisser.",
  OPT_ZOOM = "Cadrage du modèle du PNJ",
  ZOOM_BODY = "Corps entier",
  ZOOM_BUST = "Buste",
  ZOOM_HEAD = "Tête et épaules",
  ZOOM_FACE = "Visage",
  OPT_COMPANIONS_TRACK = "Compter le temps passé en groupe",
  OPT_COMPANIONS_TOOLTIP = "Lignes dans l'infobulle des joueurs",
  OPT_COMPANIONS_CHAT = "Annoncer les paliers dans le chat",
  OPT_FISHING_TAB = "Onglet de la pêche, sur le côté du sac à dos",
  OPT_DISENCHANT_TAB = "Onglet du désenchantement, sur le côté du sac à dos",
  OPT_PROFESSION_TABS = "Onglets des métiers appris, sur le côté du sac à dos (un clic ouvre leur fenêtre)",
  OPT_BAG_ROWS = "Sac à dos : une ligne par sac, pour voir la taille de chacun",
  OPT_BAG_RESET = "Remettre le sac à dos à sa place",
  OPT_MAP_BUTTON = "Bouton de la carte du monde, pour réécouter une zone",
  OPT_MAP_PANEL = "Récit du lieu à côté de la carte du monde (texte et peinture de la zone)",
  OPT_ANNOUNCE = "En groupe, annoncer les quêtes terminées et leurs objectifs",
  OPT_ANNOUNCE_CHANNEL = "Canal de l'annonce",
  OPT_QUEST_AREA = "Mettre en avant les quêtes dont je suis dans la zone (suivi et journal)",
  OPT_SORT_BY_LEVEL = "Trier les quêtes par niveau (suivi et journal)",
  OPT_EMOTE_WHEEL = "Roue d'émotes (maintenir sa touche, viser, relâcher)",
  OPT_EMOTE_WHEEL_KEY = "Touche de la roue d'émotes",
  BIND_NONE = "Aucune",
  BIND_PRESS = "Appuie sur une touche…",
  BIND_HINT = "Clic : choisir une touche (Échap : annuler) ; clic droit : retirer. Bouton de manette : "
    .. "Options > Raccourcis > AddOns.",
  BIND_COMBAT = "impossible de changer un raccourci en combat.",
  BIND_SET = "roue d'émotes : touche %s.",
  BIND_REPLACED = "roue d'émotes : touche %s (elle servait à « %s »).",
  BIND_CLEARED = "roue d'émotes : plus de touche.",
  BIND_FAILED = "le jeu a refusé la touche %s.",
  SORT_BUTTON = "Trier les quêtes par niveau (suivi et journal)",
  SORT_FLAREUI = "Journal de quêtes trié. Le suivi de FlareUI se trie lui-même : choisissez « Par niveau » pour son"
    .. " tri, dans les options de FlareUI (suivi des quêtes).",
  SORT_ASC = "Ordre : niveau croissant (le plus bas en haut)",
  SORT_DESC = "Ordre : niveau décroissant (le plus haut en haut)",
  SORT_HINT = "Clic droit : inverser l'ordre",
  SORT_ORDER_ASC = "tri par niveau croissant.",
  SORT_ORDER_DESC = "tri par niveau décroissant.",
  OPT_SORT_ORDER = "Ordre du tri",
  SORT_ASC_SHORT = "Croissant",
  SORT_DESC_SHORT = "Décroissant",
  SORT_DONE = "quêtes triées par niveau.",
  SORT_KEPT = "le jeu garde son ordre de suivi : tri impossible.",
  SORT_AFTER_COMBAT = "tri des quêtes à la fin du combat.",
  SORT_UNAVAILABLE = "le client ne permet pas de réordonner le suivi.",
  ANNOUNCE_PARTY = "Groupe",
  ANNOUNCE_SAY = "Dire (/s)",
  ANNOUNCE_DONE = "J'ai terminé « %s »",
  ANNOUNCE_BLOCKED = "annonce en /s bloquée par le jeu : choisissez le canal Groupe dans les options.",
  OPT_FORGET_ZONES = "Réentendre toutes les zones",
  OPT_FORGET_DONE = "Elise présentera de nouveau chaque zone à la prochaine visite.",
  OPT_RESET = "Réinitialiser les options",
  OPT_RESET_CONFIRM = "Confirmer ?",
  OPT_RESET_DONE = "Options réinitialisées.",
  LIST_OPEN = "Ouvrir la liste de lecture",
  LIST_CLOSE = "Fermer la liste de lecture",
  PLAYLIST = "Liste de lecture",
  LOADED = "chargé. /fs pour les commandes.",
  PLAYLIST_RESET = "Vider",
  PLAYLIST_HINT = "Double-clic : relire depuis le début",
  PLAYLIST_EMPTY = "Rien en lecture. Les quêtes lues et à venir s'affichent ici.",
  TEST_SOUND = "Son de test",
  NO_QUEST_TITLE = "Aucune quête",
  NO_QUEST = "Ouvrez une quête auprès d'un PNJ, ou cliquez sur le bouton lecture dans le suivi d'objectifs"
    .. " ou le journal.",
  OPTIONS = "Options",
  OPT_ENABLED = "Audio activé",
  OPT_ENABLED_OFF = "Désactivé : aucune lecture, pas de bouton dans le jeu.",
  OPT_OPEN_ON_PLAY = "Ouvrir cette fenêtre à chaque lecture",
  OPT_FOLLOW_TRACKED = "Hors lecture, afficher la quête suivie",
  OPT_PAGE_SOUND = "Son de page au début d'une quête",
  OPT_MUTE_GAME_VOICES = "Couper les voix du jeu des PNJ à quête",
  OPT_AUTOPLAY = "Lecture automatique des quêtes acceptées et rendues",
  OPT_ZONE_INTROS = "Elise présente chaque zone à la première visite",
  PART_ZONE = "Présentation de la zone (exploration)",
  EXPLORATION = "Exploration",
  MAP_PLAY_ZONE = "Réécouter la présentation de la zone par Elise",
  MAP_UNDISCOVERED = "Explorez d'abord cette zone pour entendre sa présentation.",
  MAP_PANEL_TITLE = "Récit du lieu",
  MAP_PANEL_BY = "Raconté par Elise",
  MAP_PANEL_UNDISCOVERED = "Elise vous racontera ce lieu quand vous y aurez posé le pied.",
  MAP_PANEL_SHOW = "Afficher le récit du lieu",
  MAP_PANEL_HIDE = "Masquer le récit du lieu",
  ZONE_SUMMARY = "Première visite : Elise vous présente la zone.",
  OPT_LEVEL_LINES = "Elise vous parle à chaque niveau gagné",
  PART_LEVEL = "Niveau gagné",
  LEVEL_TITLE = "Niveau %d",
  LEVEL_HEADER = "Votre voyage",
  LEVEL_SUMMARY = "Un niveau de plus : Elise poursuit son histoire.",
  PART_COMPLETE = "Fin de quête",
  PART_DETAIL = "Début de quête",
  OPT_SHOW_LIST = "Afficher la liste de lecture",
  OPT_SHOW_TEXT = "Afficher le texte de la quête",
  COMPACT_ON = "Fenêtre compacte : sans la description de la quête.",
  COMPACT_OFF = "Fenêtre complète : avec la description de la quête.",
  OPT_MINIMAP = "Icône sur la minimap",
  OPT_GAP = "Pause entre deux quêtes",
  GAP_SECONDS = "%d s",
  GAP_NONE = "Aucune",
  OPT_DEBUG = "Mode debug (messages dans le chat)",
  OPT_FALLBACK = "Sans fichier audio :",
  OPT_CHANNEL = "Canal audio :",
  FALLBACK_TTS = "Synthèse vocale",
  FALLBACK_TEST = "Son de test",
  FALLBACK_NONE = "Rien",
  OPT_INFO = H.TITLE .. " v%s · %d quête(s) capturée(s)",
  MINIMAP_TOOLTIP = "Clic : ouvrir / fermer · Clic droit : options · Glisser : déplacer",
  DEBUG_BAR = "Debug",
  DEBUG_MARK = "Repère n°%d",
  DEBUG_SHOT = "Capture",
  DEBUG_RELOAD = "Recharger",
  -- ducking, battlegrounds, books and NPC dialogues (2026-10-21)
  OPT_FADE_MOVE = "Estomper l'interface pendant les déplacements (la souris sur un élément le réaffiche)",
  OPT_DUCK = "Pendant une lecture, baisser la musique, l'ambiance et les effets",
  OPT_READ_IN_BG = "Lire en champ de bataille et en arène",
  OPT_READ_BOOKS = "Lire les livres et les plaques",
  OPT_READ_GOSSIP = "Lire les dialogues des PNJ",
  PART_BOOK = "Livre ou plaque (lu par Elise)",
  PART_GOSSIP = "Dialogue du PNJ",
  BOOK_PAGE = "%s — page %d",
  BOOK_HEADER = "Lecture",
  BOOK_SUMMARY = "Un livre, une plaque : Elise vous le lit.",
  GOSSIP_HEADER = "Dialogue",
  GOSSIP_SUMMARY = "Ce que le PNJ vous dit.",
  BINDING_HEADER = H.TITLE,
  BINDING_PLAY = "Lecture / Stop (quête affichée)",
  BINDING_NEXT = "Avancer (quête suivante)",
  BINDING_STOP = "Stop",
  BINDING_EMOTE_WHEEL = "Roue d'émotes (maintenir)",
}

-- Secret values (Forever, like Retail 12): in instances, battlegrounds and combat the client hands addons some values
-- (an NPC's name and GUID, chat text, GetTitleText, GetQuestID...) that error when indexed or compared. A secret value
-- counts as unknown: nil. issecretvalue is the client's own test (unverified on Forever: absent, nothing is secret).
function H.NotSecret(value)
  local test = _G.issecretvalue
  if value ~= nil and type(test) == "function" then
    local ok, secret = pcall(test, value)
    if not ok or secret then
      return nil
    end
  end
  return value
end

local function notSecretAll(n, ...)
  if n == 0 then
    return
  end
  return H.NotSecret((...)), notSecretAll(n - 1, select(2, ...))
end

-- Calls fn safely: nil when it is not a function or raises; every secret result becomes nil.
function H.Safe(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local result = { pcall(fn, ...) }
  if not result[1] then
    return nil
  end
  return notSecretAll(table.maxn(result) - 1, unpack(result, 2, table.maxn(result)))
end

local function format(fmt, ...)
  if select("#", ...) > 0 then
    return string.format(fmt, ...)
  end
  return tostring(fmt)
end

-- The chat frame treats "|" as an escape character (|c, |r, |h...): double it for literal text.
function H.Escape(text)
  return (tostring(text):gsub("|", "||"))
end

function H.Print(fmt, ...)
  local msg = PREFIX .. format(fmt, ...)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(msg)
  else
    print(msg)
  end
end

function H.Debug(fmt, ...)
  if ForeverSpeechDB and ForeverSpeechDB.debug then
    H.Print("|cff999999[debug]|r " .. format(fmt, ...))
  end
end

-- Diagnostic trace kept in ForeverSpeechDB.trace (last TRACE_MAX lines, read offline after a
-- /reload), also printed with /fs debug on. Every argument goes through tostring: use %s only.
local TRACE_MAX = 400

function H.Trace(fmt, ...)
  local args = { n = select("#", ...), ... }
  for i = 1, args.n do
    args[i] = tostring(args[i])
  end
  local msg = args.n > 0 and string.format(fmt, unpack(args, 1, args.n)) or fmt
  local line = (date and date("%H:%M:%S") or "") .. " " .. msg
  if not H.initialized then
    -- before ADDON_LOADED the SavedVariables are not loaded yet: buffer, flushed by FlushTrace
    H.pendingTrace = H.pendingTrace or {}
    table.insert(H.pendingTrace, line)
    return
  end
  local trace = ForeverSpeechDB.trace or {}
  ForeverSpeechDB.trace = trace
  if #trace >= TRACE_MAX then
    table.remove(trace, 1)
  end
  trace[#trace + 1] = line
  H.Debug("%s", H.Escape(msg))
end

function H.FlushTrace()
  local pending = H.pendingTrace or {}
  H.pendingTrace = nil
  for _, line in ipairs(pending) do
    local trace = ForeverSpeechDB.trace or {}
    ForeverSpeechDB.trace = trace
    if #trace >= TRACE_MAX then
      table.remove(trace, 1)
    end
    trace[#trace + 1] = line
  end
end

-- Slash commands -------------------------------------------------------------

H.commands = {}
local commandOrder = {}

-- Registers `/fs <name> <args>`; handler receives the rest of the line.
function H.RegisterCommand(name, handler, help)
  if not H.commands[name] then
    commandOrder[#commandOrder + 1] = name
  end
  H.commands[name] = { handler = handler, help = help }
end

function H.HandleSlash(msg)
  msg = msg or ""
  local name, rest = msg:match("^%s*(%S+)%s*(.-)%s*$")
  if not name then
    if H.PlayerFrame then
      H.PlayerFrame.Toggle()
      return
    end
    name, rest = "help", ""
  end
  local cmd = H.commands[name:lower()]
  if not cmd then
    H.Print("unknown command '%s'. Type /fs help.", H.Escape(name))
    return
  end
  cmd.handler(rest)
end

H.RegisterCommand("help", function()
  H.Print("v%s commands:", H.version)
  for _, name in ipairs(commandOrder) do
    local help = H.commands[name].help
    if help then
      H.Print("  /fs %s", H.Escape(help))
    end
  end
end, "help - this list")

H.RegisterCommand("debug", function(arg)
  arg = arg:lower()
  if arg == "on" then
    ForeverSpeechDB.debug = true
  elseif arg == "off" then
    ForeverSpeechDB.debug = false
  end
  H.Print("debug is %s", ForeverSpeechDB.debug and "on" or "off")
  if H.PlayerFrame then
    H.PlayerFrame.UpdateDebugBar()
  end
end, "debug on|off")

H.RegisterCommand("mark", function(arg)
  H.Trace("=== MARK %s ===", arg)
  H.Print("mark: %s", H.Escape(arg))
end, "mark <text> - add a marker line to the diagnostic trace")

SLASH_FOREVERSPEECH1 = "/fs"
SlashCmdList["FOREVERSPEECH"] = H.HandleSlash
