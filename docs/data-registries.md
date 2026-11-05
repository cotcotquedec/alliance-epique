# Registres de données (phase 2)

Les données sont récupérées **zone par zone**, selon les catégories de quêtes de Wowhead, qui sont la source de vérité.
Le Comté du Nord, par exemple, fait partie de la Forêt d'Elwynn. Seul le **français** est gardé (D5) : un texte
absent, non traduit ou resté en anglais est listé dans `missing`, et une capture en jeu le fournira.

## Commandes

`tools/zone.sh` est un raccourci pour `python -m pipeline.zones`. `<zone>` accepte :
- une clé : `eastern-kingdoms/elwynn-forest` ;
- un slug : `elwynn-forest` ;
- un ID Wowhead : `12` ;
- le nom français : `"Forêt d'Elwynn"`.

| Commande | Effet | Réseau |
|---|---|---|
| `catalog [--refresh]` | (Re)construit `data/zones.json` à partir du menu des quêtes de Wowhead | 1 requête si le menu n'est pas en cache |
| `list [--group eastern-kingdoms]` | Liste les zones avec leur état (`todo`, `partial`, `fetched`) et leurs compteurs | aucun |
| `plan <zone>` | Estime le nombre de requêtes que demanderait `fetch` | aucun (cache seul) |
| `fetch <zone> [--max-requests 300]` | Récupère les quêtes et les PNJ donneurs, écrit les deux registres et met à jour le catalogue | ce qui manque au cache |
| `show <zone>` | Affiche les compteurs d'une zone récupérée | aucun |
| `missing <zone>` | Liste les quêtes à compléter, c'est-à-dire à ouvrir en jeu pour capturer leur texte | aucun |
| `quest <id>`, `npc <id>` | Affiche l'enregistrement d'une quête ou d'un PNJ, tel que le registre le stocke | 1 à 2 requêtes au plus |

- **Reprise** : toutes les pages passent par le cache disque (`data/cache/wowhead/`). Si un `fetch` est interrompu (403/429, budget atteint, incident), le registre partiel est écrit et la zone passe à l'état `partial`. Relancer la même commande ne redemande que ce qui manque.
- **Pages téléchargées** :
  - la page de catégorie (`/forever/fr/quests/<groupe>/<zone>`) ;
  - chaque quête (`/forever/fr/quest=<id>`) ;
  - chaque PNJ donneur (`/forever/fr/npc=<id>`) ;
  - sa fiche Classic (`/classic/fr/npc=<id>`), qui donne la voix. Elle n'est **pas** demandée pour un PNJ marqué `new` dans Forever, car il n'existe pas dans Classic.

## `data/zones.json`

```json
{ "schema": 1, "source": "nether.wowhead.com/forever/fr/menus (menu.def.quests)", "updated_at": "…",
  "zones": { "eastern-kingdoms/elwynn-forest": {
    "id": 12, "name": "Forêt d'Elwynn", "group": "eastern-kingdoms", "group_name": "Royaumes de l'Est",
    "path": "/forever/fr/quests/eastern-kingdoms/elwynn-forest",
    "state": "fetched", "fetched_at": "…",
    "summary": { "quests": { "quests": 76, "complete": 65, "…": 0 }, "npcs": { "npcs": 32, "…": 0 }, "complete_fetch": true }
}}}
```

Le menu de Wowhead colle parfois le nom anglais au nom français (« Bois de la Pénombre Duskwood »).
Après le premier `fetch`, `name` est remplacé par le titre de la page de catégorie (« Forêt d'Elwynn »).

## `data/zones/<groupe>/<zone>/quests.json`

En-tête : `schema`, `zone`, `zone_id`, `zone_name`, `updated_at`, `summary`, puis `quests` indexé par ID.

| Champ | Contenu |
|---|---|
| `name`, `objectives`, `description`, `progress`, `completion` | Texte français, ou `null` |
| `starters`, `enders` | `[{type: npc\|object\|item, id, name}]` |
| `zone_id`, `level`, `reqlevel`, `side` (`alliance`, `horde`, `both`), `xp`, `money` | Métadonnées Wowhead |
| `forever` | `{status: new\|updated\|unchanged, patch}` : la quête par rapport à Classic |
| `placeholders` | Variables Wowhead de la description et des objectifs (`classe`, `costaud/costaude`, `un/une:c`) |
| `not_french` | Champs écartés parce qu'ils étaient non traduits ou en anglais |
| `missing` | Ce qui manque pour la narration : `name`, `objectives`, `description`, `giver` |
| `status` | `complete`, `incomplete` (quelque chose manque), `unavailable` (page absente), `capture_only` (vue en jeu, inconnue de Wowhead : ajoutée par le compagnon) |
| `wowhead` | `{http, fetched_at}` |
| `capture` | Rempli par le compagnon (incrément 4). Une nouvelle récupération le conserve, ainsi que les quêtes `capture_only`. |
| `source` | `foreverdb` : versions des sources de la base ; `texts` : par texte, le canal qui l'a apporté (`wowhead`, notre crawl ; `foreverdb` ; `capture`) ; `origins` (2026-10-21) : par texte, sa provenance réelle : `wowhead`, `capture`, ou dans la base `foreverdb:questie`, `foreverdb:vmangos` (texte de Classic), `foreverdb:client_cache`, `foreverdb:wowhead`, `foreverdb:azerothcore`, `foreverdb:unknown` (`pipeline/foreverdb/origins.py`, aussi par l'import ; `python -m pipeline.foreverdb.origins [--dry-run]`). |

`giver` manquant : la quête est démarrée par un objet d'inventaire, ou Wowhead ne connaît pas son donneur. C'est alors la voix
narrateur (D9), sauf si une capture fournit un PNJ.

## `data/zones/<groupe>/<zone>/npcs.json`

Ce fichier contient les PNJ **donneurs** des quêtes de la zone (D6). Un PNJ qui donne des quêtes dans plusieurs zones apparaît dans
chacune d'elles.

| Champ | Contenu |
|---|---|
| `name`, `title` | Nom et titre français (`title` = « Bibliothécaire »…) |
| `type`, `classification`, `react` (`{alliance, horde}`), `zones`, `levels` | Métadonnées Wowhead |
| `coords` | `{zoneID: [[x, y], …]}`, en pourcentage de la carte de la zone |
| `display_id` | Modèle 3D (`SetDisplayInfo`, S8) |
| `quests_started`, `quests_ended` | Toutes les quêtes du PNJ, toutes zones confondues |
| `forever.status` | `new`, `updated` ou `unchanged` |
| `voice` | Voir ci-dessous |
| `missing` | `name`, `display_id`, `voice` |

Le champ `voice` est déduit des noms des jeux de sons, sans télécharger d'audio. Voir `docs/reference/npc-voices.md`.

| `kind` | Sens | Champs |
|---|---|---|
| `archetype` | Voix partagée race × sexe × personnalité | `set` (`HumanMaleStandard`), `race`, `sex`, `personality`, `vendor`, `soundkits` (`greeting`, `farewell`, `pissed`), `combat_set` |
| `unique` | Voix propre (Thrall, Peasant…) | `set` (`Thrall`), et `race` et `sex` d'après les sons de combat (`OrcMale`) |
| `none` | Fiche Classic sans salutation (enfant, créature) | `race` et `sex` si des sons de combat existent |
| `unknown` | Pas de fiche Classic | `reason` : `new_in_forever`, `no_classic_page` ou `no_page` |

## Bilan de la Forêt d'Elwynn (2026-10-05)

| Mesure | Valeur |
|---|---|
| Requêtes | 58, dont aucune bloquée (le reste venait du cache S6) |
| Quêtes | 76 : 65 complètes, 11 à compléter |
| Description manquante | 5 (16, 7961, 91736, 91738, 95771) |
| Donneur manquant | 8 |
| Nouvelles quêtes Forever | 27 |
| PNJ donneurs | 32, tous avec un displayID ; 8 avec un titre |
| Voix | 25 archétypes ; 1 sans voix (Billy Maclure, un enfant) ; 6 PNJ nouveaux dans Forever, voix inconnue |

## `data/zones/<groupe>/<zone>/scripts.json` : scripts de jeu des quêtes

Le texte à jouer, **dirigé une fois pour toutes** et stocké :

```bash
tools/zone.sh scripts <zone> [--dry-run] [--quest ID] [--force] [--jobs 6]
tools/zone.sh script <questID>
```

Il y a un script par quête qui a un texte français et un PNJ donneur doté d'une fiche (`data/voices.json`). Les quêtes démarrées par
un objet ou un item (`no_npc_giver`) attendent la voix du narrateur (D9).

| Champ | Contenu |
|---|---|
| `text` | Texte d'acceptation (D6) **dépersonnalisé** : nom et classe retirés en apostrophe, « camarade » après un mot, indications de jeu retirées. Seuls les accords restent, sous forme de marqueurs `<prudent/prudente>`. |
| `gendered` | `true` si le texte contient des marqueurs, donc deux audios (`file`, `fileF`) |
| `stage_directions` | Indications de jeu retirées du texte (`grand sourire`…) |
| `source` | Provenance du texte lu (2026-10-21 ; avant : `wowhead_fr` partout) : celle de la description, sinon des objectifs (début), de la fin (fin), reprise de `source.origins` de la quête : `wowhead`, `capture`, `foreverdb:vmangos`… |
| `origins` | Provenance de chaque texte lu : `{description, objectives}` ou `{completion}`. `python -m pipeline.foreverdb.origins` récrit `source` et `origins` des scripts existants, jamais leur texte (un script dont le texte n'est plus celui de sa quête est laissé tel quel). |
| `generator` | `{"version": "narration-1", "at": …}` : script calculé sans Claude (`pipeline/scripts.py`, 2026-10-07) |

Les scripts écrits avant le 2026-10-07 ont en plus une direction d'acteur de Claude (`segments`, `overall`,
`render`, `plain`, `target_cps`), inutilisée : Qwen3 ne lit que `text`. Un script existant n'est jamais réécrit,
même si son texte ou la fiche du PNJ change ; `--force` le réécrit (et son audio sera à refaire).

## `data/zones/<groupe>/<zone>/dialogues.json` : dialogues des PNJ (D14, 2026-10-10)

Le texte de la fenêtre de discussion de chaque PNJ de la catégorie, page après page, importé de VMaNGOS
(`pipeline/foreverdb/dialogues.py`, `tools/zone.sh dialogues`, refait à chaque import) :

```json
{"schema": 1, "zone": "eastern-kingdoms/elwynn-forest", "npcs": {"197": {"name": "Maréchal McBride", "pages": [
  {"id": "7590", "menu": 4048, "text_id": 4938, "first": true, "quests": [],
   "text": "Hé ! Vous m'avez l'air d'être costaud…"}]}}}
```

- `id` : l'identifiant du texte dans la base (`broadcast_text`) ; `first` : la première page (sinon une sous-page,
  ouverte par une ligne de discussion) ; `quests` : les quêtes qui conditionnent la page ou le chemin qui y mène ;
  `text_female` : le texte quand le PNJ est une femme, s'il diffère.
- Seulement le texte du PNJ : les lignes que le joueur clique ne sont pas gardées.
- Un PNJ reste dans sa catégorie d'une importation à l'autre ; un PNJ qui n'a que des dialogues est ajouté au
  `npcs.json` de la catégorie (`dialogue_only: true`), seulement si la catégorie a des quêtes Alliance.
- Scripts : section `dialogues` de `scripts.json`, clé `<pnj>_<page>`. Audio : `dialogue_audio.json`, état des
  essais : `dialogue_readings.json` (boucle dialogues, `tools/dialogues/`).


## `data/zones/@books/` : les livres lus par Elise (D19, 2026-10-21)

Tout texte qu'on lit dans le monde (livres, lettres, plaques, stèles : le « texte d'objet » du jeu), lu page par page
par Elise avec sa voix ElevenLabs ; **jamais le courrier**. Un dossier à part, dans aucun groupe (couvert par
`--all`), comme `@elise/levels` : registre, scripts et audio ensemble, comme une catégorie.

```bash
tools/zone.sh books                    # les deux étapes : extraction puis scripts
.venv/bin/python -m pipeline.books extract | scripts | cost [--json] | show [livre]
```

**`books.json`** (schéma 1, `pipeline/books/extract.py`) : la base (VMaNGOS : `page_text` et `next_page`, français
dans `locales_page_text`) ; un livre part d'un objet de type TEXTE (`gameobject_template` type 9, `data0`) ou d'un
objet qu'on utilise (type 10, `data7`), ou d'un item (`item_template.page_text`) ; la dernière version (`patch`)
l'emporte.

```json
{"schema": 1, "summary": {…}, "books": {"object:37": {"kind": "object", "id": 37, "title": "Tombe d'Eliza",
  "title_en": "Eliza's Tombstone", "key": "tombedeliza", "side": "both", "side_source": "zone",
  "where": {"zone": 10, "zone_name": "Bois de la Pénombre", "zone_source": "nearest_npc", "map": 0, "spawns": 1},
  "quests": {}, "first_page": 731,
  "pages": [{"page": 731, "n": 1, "text": "<HTML>…", "fp": "htmlbodyh1aligncentereliza…", "chars": 182}],
  "missing": [{"page": 732, "n": 2, "why": "no_french"}]}},
 "missing": [{"book": "item:6280", "why": "no_french_title"}], "excluded": [{"book": "item:13158", "why": "mail"}]}
```

- `title` : le nom français (`locales_gameobject` / `locales_item`, sinon la Forever Database), celui que le jeu
  affiche au-dessus du texte ; `key` = `fs_key(title)`, la clé de l'index (`pipeline/match.py`).
- `pages` : les pages en français seulement (D5), `n` = le numéro de la page en jeu (sa place dans la chaîne),
  `text` = texte de la base en balisage de narration (`<nom>`, `<il/elle>`), `fp` = `fs_fp` du texte brut.
- `side` : `horde` (races, quêtes ou territoire de la Horde), `alliance`, `both` (neutre), `unknown` (gardé dans le
  périmètre, signalé). `where.zone_source` : `foreverdb` (QuestieDB), `quest` (zone de la quête liée) ou
  `nearest_npc` (zone des 5 créatures les plus proches de l'objet sur la même carte, hors événements : une
  estimation).
- `excluded` : courrier (`mail_loot_template`) et objets périmés ou de test (jamais en jeu).

**`scripts.json`** (`pipeline/books/scripts.py`), section `pages`, clé = identifiant de page (une page partagée par
plusieurs livres est lue une fois) : `{page, n, title, books, npc_id: 1000000, side, text, gendered, chars,
generator}`. Le texte est **lu tel qu'il est écrit** : le HTML de certaines pages devient des paragraphes, `$B` un
saut de ligne, `$N` en apostrophe retiré, `$N` dans la phrase « l'aventurier / l'aventurière », `$C`/`$R` comme
ailleurs (D8), `$g` en marqueurs `<m/f>` (deux audios), une note entre chevrons (« <texte illisible> ») lue sans ses
chevrons. Section `cost` : caractères facturés par ElevenLabs, pour tous les livres et pour le périmètre.

**`audio.json`**, section `book`, clé = page : `{npc: 1000000, m: {...}, f: {...}}`, entrée comme celles d'Elise
(fichier `audio/1000000/book_<page>[_f].ogg`, `engine: elevenlabs`, `voice_id`, `text_hash`, scores), écrite par la
boucle livres (`tools/books/`), état des essais dans `data/books/state.json`.

**Bilan (2026-10-21)** : 396 livres (106 objets, 290 items) après 13 exclus (7 courriers, 6 périmés) ; 314 dans le
périmètre de l'Alliance (104 Alliance, 168 neutres, 42 inconnus), 289 lisibles (titre et au moins une page en
français). 1 182 pages, **1 140 en français (96,4 %)**. Scripts : **945 pages, 950 lectures (5 pages accordées),
368 140 caractères** pour le périmètre (440 452 pour tous les livres). ElevenLabs, à un crédit par caractère :
368 140 crédits pour une lecture de chaque page, **environ 519 000** avec les essais refusés par le juge (×1,41, le
rapport mesuré sur la boucle Elise).
