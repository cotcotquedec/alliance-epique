# La fabrication de l'audio

Comment l'audio d'Alliance Épique est produit, de la base de données aux fichiers du jeu. Présentation de l'addon :
[README](../README.md).

Tout l'audio est produit **en local** (Qwen3-TTS) : sur un Mac Apple Silicon (MLX) ou sur une machine avec un GPU
NVIDIA, par exemple Windows avec WSL2 (PyTorch, CUDA). La même commande choisit toute seule. Les données viennent de
la Forever Database ; l'audio est embarqué dans le dossier de l'addon. Les règles de travail et les décisions sont
dans [CLAUDE.md](../CLAUDE.md).

## La chaîne en cinq étapes

```
 1. Données          2. PNJ               3. Texte des quêtes   4. Voix des PNJ       5. Voix des quêtes
 Forever Database →  fiche de chaque   →  script de chaque   →  voix modèle de     →  lecture de chaque
 (clone + Lua)       PNJ qui parle        début et fin         chaque PNJ            script, voix clonée
 tools/prepare_db.sh tools/text/run.sh    tools/text/run.sh    tools/voices/run.sh   tools/readings/run.sh
 tools/base/run.sh   (Claude)             (sans Claude)        (Qwen3 VoiceDesign)   (Qwen3 Base)
        │                  │                    │                     │                     │
 data/zones/<g>/<c>/ data/voices.json    data/zones/<g>/<c>/   data/voices.json      addon/ForeverSpeech/audio/
 quests.json         (persona)           scripts.json          (qwen) + ref.wav      + audio.json + index.lua
 npcs.json
```

Chaque étape ne travaille que sur ce que la précédente a produit : un PNJ sans fiche n'a pas de script, un PNJ sans
voix modèle n'a pas de lecture. Les étapes 2 et 3 sont faites par la même boucle (texte), qui écrit les fiches avant
les scripts. Chaque étape est une **boucle** qui avance catégorie par catégorie, dans l'ordre des niveaux, et reprend
où elle s'était arrêtée (voir [Les boucles](#les-boucles)).

## Groupes et catégories

Les quêtes sont rangées comme sur Wowhead, sur deux niveaux : un **groupe** (un continent ou un thème) contient des
**catégories** de quêtes. Dossier : `data/zones/<groupe>/<catégorie>/`.

| Groupe | Catégories (exemples) |
|---|---|
| `eastern-kingdoms` | `elwynn-forest`, `dun-morogh`, `westfall`, `stormwind-city`, `duskwood`… (33) |
| `kalimdor` | `teldrassil`, `darkshore`, `darnassus`… (24) |
| `classes` | `warrior`, `mage`, `priest`, `rogue`, `paladin`, `hunter`, `druid`, `warlock`, `shaman` |
| `professions` | `alchemy`, `blacksmithing`, `cooking`… (9) |
| `dungeons`, `raids`, `battlegrounds`, `world-events`, `miscellaneous` | les donjons, les raids… |
| `uncategorized` | les quêtes sans catégorie Wowhead (un groupe sans catégorie) |

Une quête n'appartient qu'à **une** catégorie : une quête de classe reçue à Northshire est dans `classes/warrior`,
pas dans `eastern-kingdoms/elwynn-forest`. Pour préparer ce qu'on rencontre en jouant dans une région, il faut donc
traiter sa catégorie et les quêtes de classe, de Stormwind, etc.

**Toute commande dit ce qu'elle couvre** (boucles et rapport) :

```bash
tools/voices/run.sh --all                                                    # tous les groupes
tools/voices/run.sh --group classes                                          # toutes les catégories d'un groupe
tools/voices/run.sh --group eastern-kingdoms --category elwynn-forest        # une catégorie, toujours avec son groupe
tools/voices/run.sh --group eastern-kingdoms --category elwynn-forest --category westfall
```

Sans `--all` ni `--group`, la commande refuse de démarrer ; une catégorie sans son groupe aussi. Le même nom peut
exister dans deux groupes (`alterac-valley` : la région et le champ de bataille), le groupe dit lequel.

## 0. Installer

Une commande installe tout, sur un Mac ou sous Linux / WSL2 (elle dit quels outils système manquent et comment les
installer) :

```bash
tools/setup.sh
```

**Où tournent les modèles** ([tools/qwen_voices/backend.py](../tools/qwen_voices/backend.py)), choisi selon la machine
(`FS_TTS_BACKEND=mlx|cuda|cpu` pour forcer) :

| Machine | Qwen3-TTS | Juge (Whisper, ECAPA) | Paquets |
|---|---|---|---|
| Mac Apple Silicon | MLX-Audio, GPU | processeur | `tools/voices/requirements-mlx.txt` |
| Linux / WSL2 avec GPU NVIDIA | PyTorch `qwen-tts` (modèles officiels `Qwen/…`), bf16 | GPU | `tools/voices/requirements-cuda.txt` (CUDA 12.6) |
| autre | PyTorch, processeur (lent) | processeur | idem |

Une voix ou une lecture déjà validée reste valable sur l'autre machine ; une même graine ne donne pas le même essai
sur les deux. Avant une longue nuit, vérifier l'environnement (une voix, un clonage, le juge ; écouter
`data/cache/doctor/*.wav`) :

```bash
.venv-voices/bin/python -m tools.qwen_voices.doctor
```

### Windows avec WSL2 (GPU NVIDIA)

Le guide complet est dans [docs/machines.md](machines.md) : mise en route du PC, différences avec le Mac,
copie des données d'une machine à l'autre, sceaux, pannes connues et leurs corrections. En bref :

```bash
sudo apt update && sudo apt install -y python3.12 python3.12-venv build-essential curl git ffmpeg vorbis-tools sox luajit luarocks liblua5.1-0-dev
bash tools/setup.sh
.venv-voices/bin/python -m tools.qwen_voices.doctor
```

Le projet doit être dans le disque Linux de WSL (`~/alliance-epique`, pas `/mnt/c`). Désactiver la veille de Windows
pour la nuit.

### À la main, sur Mac

Avec [Homebrew](https://brew.sh) :

```bash
brew install python@3.12 luajit luarocks ffmpeg vorbis-tools
```

- **Python** (pipeline, sans dépendance externe) :
  ```bash
  python3.12 -m venv .venv && .venv/bin/pip install 'pytest>=8'
  ```
- **Lua** (tests de l'addon : LuaJIT fournit le Lua 5.1 du jeu, luacheck et busted dans un arbre local) :
  ```bash
  luarocks --tree .luarocks --lua-version 5.1 install busted && luarocks --tree .luarocks --lua-version 5.1 install luacheck
  ```
- **Voix** (Qwen3-TTS, Whisper, speechbrain, selon la machine ; les poids des modèles se téléchargent au premier
  usage) :
  ```bash
  tools/voices/setup.sh
  ```
- **Claude Code** (étape 2, les fiches) : la commande `claude` installée et connectée sur la machine ; le pipeline
  l'appelle en mode non interactif (`claude -p`, [pipeline/llm.py](../pipeline/llm.py)), sans clé dans le dépôt.
- **Le jeu** : lier l'addon au dossier AddOns de Forever (par défaut `_forever_` ; la bêta, `_classic_beta_`, est finie) :
  ```bash
  tools/link_addon.sh
  ```

Vérifier que tout est en place (luacheck, tests Lua, tests Python) :

```bash
tools/check.sh
```

## 1. Récupérer les données

**But** : la liste des quêtes et des PNJ de chaque catégorie, avec leurs textes français.

La source est la **Forever Database** ([Stein-N/WoW-Quest-Database](https://github.com/Stein-N/WoW-Quest-Database),
GPL-3.0), qui assemble QuestieDB (Forever), VMaNGOS et les traductions d'AzerothCore. `prepare_db.sh` clone le
dépôt, compile un **Lua 5.1** local (l'export de QuestieDB est du Lua, trop gros pour LuaJIT), lit ces données
Lua, puis fusionne le tout en JSON dans `.data/` (jamais versionné, jamais redistribué). La boucle base importe
ensuite chaque catégorie dans ses registres.

```bash
tools/prepare_db.sh              # une fois : la dernière release (tag) du dépôt
tools/base/run.sh --all          # importe les registres de toutes les catégories
```

**Mettre à jour** (2026-10-08). On suit les **releases** du dépôt (ses tags), pas sa branche principale. Une quête
n'existe qu'à un endroit et se reconnaît à son ID, jamais à sa catégorie : si la base la range ailleurs, elle part
avec son script, son audio validé et l'état de ses lectures, rien n'est regénéré. Aucune boucle ne doit tourner.

```bash
tools/db_check.sh                # une release plus récente que notre build ? (code 10 : oui ; lecture seule)
tools/prepare_db.sh --update     # passe à cette release et reconstruit la base
tools/zone.sh sync --dry-run     # ce qui changerait : quêtes déplacées, retirées, revenues, nouvelles, textes changés
tools/zone.sh sync               # applique, puis importe toutes les catégories
```

Une quête qui n'est plus dans la base est **rangée** dans `data/archive/quests.json` (avec ses scripts, son audio et
ses lectures ; les fichiers audio restent sur le disque) et revient telle quelle si la base la remet. Jamais retirée :
une quête capturée en jeu, ou venue d'une autre source (l'ancien crawl Wowhead). Un texte changé dans la base est
seulement listé : refaire son script ou son audio est une décision humaine. Des quêtes retirées font baisser les
compteurs : relancer chaque boucle une fois avec `--reset-ratchet`. `tools/zone.sh import` (la boucle base) refuse
de tourner tant qu'un déplacement, un retrait ou un retour attend la synchronisation.

**Produit** : `data/zones/<groupe>/<catégorie>/quests.json` et `npcs.json`, `data/zones.json` (le catalogue).
Détail : [docs/data-registries.md](data-registries.md). Seules les quêtes de l'Alliance (ou des deux factions)
sont traitées, sans filtre de niveau.

## 2. Générer les PNJ

**But** : une **fiche de personnalité** pour chaque PNJ qui dit un texte (le donneur d'une quête, le PNJ de rendu
d'un texte de fin) : race, sexe, âge, caractère, façon de parler, description de sa voix et une phrase d'exemple.

Claude écrit chaque fiche à partir des quêtes du PNJ et de la voix que le jeu lui donne. **Produit** :
`data/voices.json`, clé `persona` de chaque PNJ. Commande : celle de l'étape 3.

## 3. Générer le texte des quêtes

**But** : le **script** de chaque texte à lire : le début de quête (description puis objectifs, dit par le donneur)
et la fin de quête (texte de rendu, dit par le PNJ de rendu). La progression n'est jamais lue. Le texte est
dépersonnalisé (`<nom>`, `<classe>`… neutralisés), et un texte accordé au sexe du joueur garde ses deux formes.

```bash
tools/text/run.sh --group eastern-kingdoms --category elwynn-forest   # étapes 2 puis 3 (ou --all, --group G)
```

**Produit** : `data/zones/<groupe>/<catégorie>/scripts.json`. Depuis le 2026-10-07, un script se calcule **sans
Claude** (`pipeline/scripts.py`) : plus de mise en scène, Qwen3 ne lit que le texte. Les scripts écrits avant gardent
la leur, inutilisée. Seules les fiches (étape 2) passent par Claude. Règles du texte :
[docs/voices-and-text.md](voices-and-text.md).

## 4. Générer les voix des PNJ

**But** : une **voix modèle** par PNJ, un enregistrement de 15 à 20 secondes de sa phrase d'exemple qui fixe son
timbre pour toutes ses quêtes.

**Qwen3-TTS VoiceDesign** invente la voix à partir d'une description en français, construite depuis la fiche du
PNJ : comédien de doublage français natif, contexte World of Warcraft côté Alliance, identité (race, sexe, âge),
rôle, caractère, voix, et l'**accent de sa race** ([data/accents.json](../data/accents.json) : nains aux r roulés,
trolls à l'accent créole…). Le **juge** (Whisper large-v3) vérifie chaque essai : anglais ≤ 0,15 %, mots mal lus
≤ 15 %, débit de 7 à 22 caractères par seconde.

```bash
tools/voices/run.sh --group eastern-kingdoms --category elwynn-forest [--npc 823]
```

**Produit** : `data/voices/samples/qwen/voices/<pnj>/ref.wav` et `ref.txt` (le texte exact, pour le clonage), et
la clé `qwen` du PNJ dans `data/voices.json` (graine, scores, description). Le texte lu est le `voice_text` du PNJ
dans `voices.json` : sa phrase d'exemple, ou un texte choisi à la main dans ses quêtes. Règles :
[tools/voices/constitution.md](../tools/voices/constitution.md).

## 5. Générer les voix des quêtes

**But** : l'**audio de chaque script**, lu par son PNJ.

**Qwen3-TTS Base** clone la voix modèle du PNJ et lit le script, paragraphe par paragraphe. Le juge ajoute aux
critères de l'étape 4 la **ressemblance avec la voix modèle** (ECAPA, au moins 0,75) : le PNJ garde la même voix
d'une quête à l'autre. Une lecture acceptée devient le fichier du jeu.

```bash
tools/readings/run.sh --group eastern-kingdoms --category elwynn-forest [--npc 823]
```

**Produit** : `addon/ForeverSpeech/audio/<pnj>/<quête>_detail[_f].ogg` et `_complete.ogg`, le master FLAC dans
`data/audio/<groupe>/<catégorie>/`, l'entrée dans `data/zones/<groupe>/<catégorie>/audio.json`, puis l'index de l'addon
(`addon/ForeverSpeech/data/index.lua`, généré, contrat décrit dans CLAUDE.md §8). Règles :
[tools/readings/constitution.md](../tools/readings/constitution.md).

## 6. Elise, la narratrice

**But** : la voix d'**Elise** (elfe de la nuit, narratrice de l'Alliance, voix ElevenLabs fixe) pour ce qu'aucun PNJ
ne dit : les textes de quête donnés ou rendus par un objet, sa **présentation de chaque zone**, dite la première
fois que le joueur y pose le pied (48 zones, du point de vue de l'Alliance), et **une réplique à chaque niveau
gagné** (2 à 60, une seule histoire jusqu'à la fin du jeu). Ces textes sont écrits par Claude au lancement de la
boucle, s'ils manquent (`pipeline/zone_intros`, `pipeline/level_lines`).

```bash
tools/elise/start.sh --all                       # tout, dans une session tmux (fs-elise)
tools/elise/run.sh --all --kind zone             # seulement les présentations de zone
tools/elise/run.sh --group kalimdor --kind zone  # celles d'un continent
tools/elise/run.sh --all --kind level            # seulement les répliques de niveau
tools/elise/run.sh --all --kind quest            # seulement les textes de quête
.venv/bin/python -m pipeline.zone_intros show    # relire les textes de zone
.venv/bin/python -m pipeline.level_lines show    # relire l'histoire des niveaux (again <niveau> : en refaire une)
```

**Produit** : `addon/ForeverSpeech/audio/1000000/<quête>_detail|complete.ogg`, `<zone>_zone.ogg` et
`<niveau>_level.ogg`, l'entrée dans `audio.json` (catégories ; présentations : `data/zones/<groupe>/@intros/` ;
niveaux : `data/zones/@elise/levels/`), puis l'index. Règles :
[tools/elise/constitution.md](../tools/elise/constitution.md).

## Repasse globale

Toutes les boucles une fois de plus, l'une après l'autre, sur tout le jeu : texte, voix, lectures, dialogues, Elise.
Chacune rouvre ce qu'elle n'a pas trouvé à sa dernière exécution (5 essais de plus) et fait ce qui est nouveau ; la
base n'est pas touchée (une synchronisation reste une décision humaine). Puis l'index et le rapport.

```bash
tools/loop/repass.sh                   # dans la session tmux fs-repass, tableau de bord à droite
tools/loop/repass.sh --from readings   # reprendre à une boucle
tools/loop/repass.sh --kill            # tout arrêter
```

## Essayer en jeu

- Un fichier audio **nouveau** est entendu après `/reload` ; un fichier **remplacé** (même nom) seulement après un
  **redémarrage complet** du jeu.
- Une quête acceptée est lue 2 s après, une quête rendue a sa fin lue 2 s après, avec le jeu comme avec Dialogue UI
  (option « Lecture automatique », activée par défaut). Sans audio, l'addon lit le texte avec la
  synthèse vocale du client. Hors lecture, le lecteur affiche la quête suivie.
- Les salutations et adieux d'origine des PNJ sont coupés (option) : la liste de leurs fichiers est générée depuis le
  cache Wowhead, `.venv/bin/python -m pipeline.game_voices` → `addon/ForeverSpeech/data/game_voices.lua` (non
  versionné ; à refaire sur une copie neuve du dépôt).
- `/fs` liste les commandes (lecture, liste de lecture, réglages). Procédures de test : [docs/ingame-tests.md](ingame-tests.md).

## Suivre et contrôler

| Pour… | Commande |
|---|---|
| Le tableau d'avancement par catégorie (PNJ, fiches, voix, scripts, audio) ; `--todo` : le détail de ce qui reste | `tools/report.sh --all`, `--group G [--category C]` |
| **Écouter et vérifier** : une catégorie à la fois, lectures ou voix modèles, filtre « À vérifier », verdict du juge, voix modèle à comparer | `.venv/bin/python -m tools.voices.bench`, puis http://127.0.0.1:8765 |
| Le dernier tour d'une boucle et son backlog | `tools/loop/status.sh <boucle>` |
| Où en est une boucle, sans rien lancer | `.venv/bin/python -m tools.loop oracle <boucle> [--group G [--category C]]` |

Les boucles s'appellent `base`, `text`, `voices` et `readings`. Le banc relit les données à chaque rafraîchissement
(relancer le banc après un changement des seuils du juge).

## Les boucles

Les cinq étapes reposent sur le même moteur ([tools/loop/README.md](../tools/loop/README.md)) : à chaque tour, un
**acteur** traite une catégorie, un **juge** garde ou rejette ce qui a été produit, un **oracle** en lecture seule mesure
où on en est, un **cliquet** garde le niveau le plus haut atteint (il ne peut que monter) et un **critique** note
dans un backlog ce qui manque.

- **Sceau** : la constitution, le juge, l'oracle et le cadre d'une boucle sont scellés après relecture humaine
  (`tools/loop/seal.sh <boucle>`) ; la boucle refuse de tourner si l'un d'eux a changé.
- **Voix et lectures** : un essai par tour, graine au hasard jamais réutilisée ; 5 essais par exécution, puis
  « pas trouvé » jusqu'à l'exécution suivante, qui redonne 5 essais. Rien n'est jamais abandonné, et rien de déjà
  validé n'est refait.
- **Ce qui est couvert** : `--all`, ou `--group` avec éventuellement `--category` (toutes les boucles et le
  rapport) ; `--npc` en plus pour les voix et les lectures.
- **`--reset-ratchet`** : le cliquet repart du niveau du lancement, après une baisse voulue (une voix refaite, des
  compteurs changés).

**Refaire la voix d'un PNJ** dont les lectures échouent sur la ressemblance (sa voix modèle se clone mal) :

```bash
.venv/bin/python -m tools.voices.redo 197                # archive sa voix, supprime ses lectures et ses essais
tools/voices/run.sh --all --npc 197 --reset-ratchet      # nouvelle voix modèle
tools/readings/run.sh --all --npc 197 --reset-ratchet    # nouvelles lectures
```

Pour changer le texte de sa voix modèle (par exemple sans nom anglais ni interjection), modifier son `voice_text`
dans `data/voices.json` avant de relancer.

## Structure du dépôt

```
addon/ForeverSpeech/   l'addon (Lua 5.1) ; data/index.lua et data/game_voices.lua générés, audio/ produit par l'étape 5
pipeline/              Python : import de la base, fiches, scripts, rapport, index de l'addon
tools/                 boucles (base, text, voices, readings, loop), banc des voix, scripts de dev
data/                  registres, fiches, voix et masters audio (plus commités)
docs/                  spikes, tests en jeu, règles du texte et des voix, références
tests/                 busted (Lua) et pytest
```
