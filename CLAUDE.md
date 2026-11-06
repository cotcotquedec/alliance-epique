# CLAUDE.md — ForeverSpeech (narration vocale des quêtes, WoW Forever, FR)

> Nom public : **Alliance Épique** (2026-11-05 : « ton compagnon pour l'Alliance », le setup personnel du joueur mis à
> disposition, voir README), affiché dans le jeu (`H.TITLE` : titre du TOC, fenêtres, options, raccourcis, chat ;
> vérifié en jeu le 2026-11-05, T65). Le dossier, les globales, les SavedVariables et la commande gardent
> **ForeverSpeech** et `/fs`.
> L'audio n'est pas dans le dépôt ; sa fabrication : [docs/pipeline.md](docs/pipeline.md). **Releases** (2026-11-05) : deux
> archives (`tools/package_addon.ts`) : l'addon sans l'audio (18 Mo), à publier (GitHub, CurseForge ou Wago), et ses voix
> (3,2 Go), partagées à part par le joueur (Drive), refaites seulement quand des voix changent (`--no-audio` sinon), dans
> leur propre dossier `AllianceEpique_Voix` à côté de l'addon (une mise à jour remplace le dossier de l'addon, pas celui-là) ;
> FlareUI en dépendance optionnelle (`## OptionalDeps`, à déclarer aussi sur CurseForge ; le kit : [docs/curseforge.md](docs/curseforge.md)).
> **Le dépôt** (2026-11-06) : [alliance-epique](https://github.com/cotcotquedec/alliance-epique), public, le seul où l'on
> travaille (remote `origin`). Son historique part du 2026-11-05 ; avant, l'ancien dépôt privé ForeverSpeech, archivé en
> lecture seule sur GitHub (remote `archive`, 167 commits, PR #1 à #36 : le « `git log` » cité plus bas). Les données et
> l'audio, hors de git, restent dans le dossier du projet, que le jeu lit par son lien (`tools/link_addon.sh`).

## 1. Objectif

Addon WoW Forever qui lit à voix haute, en français, le texte d'une quête au moment où on l'accepte, avec **une voix propre à chaque PNJ donneur de quête** (cohérente avec sa race, son sexe, sa région, son rôle, son lore).

Usage cible :
1. J'accepte une quête (avec le jeu ou une autre interface, Dialogue UI…) → l'audio démarre et un lecteur s'ouvre.
2. Je peux relancer l'audio depuis le suivi d'objectifs (à droite de l'écran) et depuis le journal de quêtes.
3. Le lecteur affiche le PNJ (portrait/modèle, icône de quête en secours), le titre, le résumé (objectifs) et les récompenses, avec les boutons **Lecture / Avancer / Stop** en icônes, et en option le texte de la quête en petit.

## 2. Règles de travail pour Claude Code

- **Langue** : échanges avec moi en français. Code, identifiants, commentaires et messages de commit en anglais.
- **Tu ne peux pas lancer le jeu.** Toute modification testable en jeu est livrée avec une procédure courte : commandes (`/reload`, `/dump …`, `/fstack`), résultat attendu, ce que je dois te coller en retour. Les résultats sont consignés dans `docs/spikes/` ou `docs/ingame-tests.md`.
- **Hypothèse non vérifiée = signalée.** L'API du client Forever est récente et peu documentée : ne présume jamais qu'une API de Classic Era ou de Retail existe à l'identique. Vérifie (spike) ou fournis un fallback.
  **La vérification du jeu** (2026-11-03, `core/check.lua`, `/fs check`) contrôle seule, une fois par build du
  client, chaque nom du client que l'addon appelle (fonctions, cadres, événements, modèles de cadre, atlas, textures)
  et range le résultat dans `ForeverSpeechDB.check` : à lire dans les sauvegardes avant tout relevé en jeu. Un nom du
  client ajouté au code va dans ses listes (`tests/lua/check_spec.lua` échoue sinon).
- Petits incréments testables. Pas de refactor non demandé.
- Avant d'ajouter une dépendance (lib Lua, paquet Python), demande.
- **Deux agents, une file** (2026-10-10) : l'agent du PC génère (voix, lectures, Elise, page de contrôle), celui du
  Mac a le jeu. Toute hypothèse sur le client devient une demande de [docs/ingame/queue.md](docs/ingame/queue.md),
  vérifiée en jeu par l'agent du Mac (cycle : [docs/ingame/README.md](docs/ingame/README.md)). **Agent du Mac : au
  début de chaque session, lire la file et proposer les demandes ouvertes.**
- **Jamais de commit sur `main`** (protégée, 2026-10-10) : une branche par session (`session/<date>-<sujet>`), une
  pull request à la fin.
- **Sur le Mac, jamais de worktree** (2026-10-15) : une seule session active à la fois, qui travaille dans le
  dossier du projet lu par le jeu (`tools/link_addon.sh`), sur sa branche de session : un `/reload` en jeu montre
  aussitôt les changements (redémarrage complet pour un nouveau fichier). Les PR ouvertes sont fusionnées avant
  d'en commencer une autre.

## 3. Licences et code tiers — strict

- **ForeverDubbed : code sous copyright. Ne jamais ouvrir, lire, copier ni paraphraser son dépôt.** On ne reprend que l'idée générale (texte capté en jeu → audio). Implémentation clean-room.
- **VoiceOver (mrthinger/wow-voiceover)** : présenté comme Unlicense/MIT selon les sources. **Vérifier le fichier LICENSE du dépôt avant toute réutilisation**, puis citer la provenance en commentaire. Réutilisation pertinente : intégration du journal de quêtes, portrait, gestion du son.
- Données Wowhead : usage personnel, cache local, pas de redistribution des données brutes.
- **Forever Database** ([Stein-N/WoW-Quest-Database](https://github.com/Stein-N/WoW-Quest-Database), GPL-3.0 ;
  sources QuestieDB GPL-3.0, VMaNGOS GPL-2.0, AzerothCore) : **source principale des données depuis le 2026-10-06**.
  Clonée et construite en local dans `.data/` (jamais versionnée, jamais redistribuée), usage personnel.
- **Pas de contournement des protections** d'un site (proxys, rotation d'IP, UA imité, navigateur piloté ou
  Playwright, service de crawl comme Firecrawl). **Wowhead n'est plus crawlé** (2026-11-01) : son pare-feu CloudFront
  refuse les pages à tout client qui n'est pas un navigateur (403 pour notre robot, curl ou une requête anonyme,
  depuis l'adresse d'où un navigateur les ouvre) ; le crawler est retiré, le cache déjà téléchargé reste lu
  (`pipeline/wowhead/cache.py`).

## 4. Décisions d'architecture (validées)

| # | Décision | Raison |
|---|---|---|
| D1 | **Source de vérité du texte = le client frFR** (capture en jeu). Wowhead = anticipation (pré-génération avant d'avoir vu la quête). | Le texte des quêtes est envoyé par le serveur et absent des fichiers client exploitables ; le client affiche le texte exact. |
| D2 | **Audio embarqué dans le dossier de l'addon**, lu via `PlaySoundFile`. Pas de lecture hors jeu. | Je veux contrôler l'audio depuis l'interface du jeu. |
| D3 | Un **compagnon local** (Mac, ma machine uniquement) enrichit les données et l'audio entre les sessions. | Un addon ne peut ni accéder au réseau, ni écrire de fichiers hors SavedVariables. |
| D4 | **Stop uniquement, pas de pause. Un seul fichier audio par texte, pas de découpage.** | Simplicité. L'API son n'offre ni pause ni avance. |
| D5 | **Données structurées des fiches Wowhead, en français uniquement** (décidé le 2026-10-05, remplace le repli EN champ par champ). Un texte absent, non traduit ou resté en anglais n'est pas gardé : il est listé dans `missing` et sera fourni par une capture en jeu. | Un texte anglais ne sert à rien pour une narration française. Les champs structurés (ID, type, zone, modèle, quêtes données) ne dépendent pas de la langue. |
| D6 | Textes lus : **début de quête** (détail = description puis objectifs, annoncés « Objectif : … », dit par le donneur ; 2026-10-05) et **fin de quête** (texte de rendu, dit par le PNJ de rendu, lu une fois la quête rendue ; 2026-10-06, déclencheur changé le 2026-10-07 puis le 2026-10-21). La **progression n'est jamais lue**. S'applique aussi à la génération audio. | Les PNJ de rendu sont presque tous des donneurs d'autres quêtes : peu de voix en plus (8 % des fins à Elwynn, Dun Morogh, Teldrassil). |
| D7 | Recherche en jeu par `(questID, kind)`. **Pas de hash côté Lua.** La détection de divergence (quête réécrite dans Forever, texte Wowhead ≠ capture) se fait **côté pipeline** par comparaison approximative entre capture et source. | Le texte en jeu contient déjà le nom, la classe et le genre du joueur : un hash exact n'est pas comparable au texte Wowhead (`<nom>`, `<classe>`…). |
| D8 | Variables de texte : `$N`, `$C`, `$R` neutralisés à la génération (ex. « aventurier ») ; `$G` (accords) → **deux variantes audio (m/f)** quand le texte en contient. | Le français accorde beaucoup ; nom, classe et race donneraient une explosion combinatoire. |
| D9 | Texte qu'aucun PNJ ne dit (quête donnée par un objet ou un item, déclenchée par un lieu, rendue à un objet) → la **narratrice Elise** (2026-10-10) : elfe de la nuit adulte, timide, mystérieuse et sage, voix calme et douce. PNJ propre à l'addon, `NARRATOR_ID = 1000000` (`pipeline/narrator.py`), dans aucune catégorie. **Sa voix est ElevenLabs et définitive** (`FS Elise`, `G6INpmIspgFpsST79Psc`, `tools/elise/voice.py`) ; seules ses répliques changent, lues par **sa propre boucle** (`tools/elise/`, `eleven_v4`, budget de crédits ; un texte changé est refait). À terme, elle devient la compagne du joueur (répliques propres au jeu : entrée dans une zone…). **Son portrait** (2026-10-15) : une image peinte pour l'addon, pas un PNJ du jeu, à la place du modèle 3D dans la fenêtre de lecture (`media/elise.tga`, 256×256 ; original `data/icons/elise/portrait.png`, Gemini 3.1 Flash Image par OpenRouter, variante 3 choisie ; `tools/elise_portrait.sh` ; icônes de quête et de réplique en secours ; non vérifié : T31). Un PNJ donneur ou de rendu reste toujours prioritaire. | Pas de PNJ. 445 débuts et 274 fins de quête avec texte français étaient sans orateur. |
| D10 | **Source des données = la Forever Database** (QuestieDB Forever + VMaNGOS + traductions), construite en local (`tools/prepare_db.sh`), importée dans les registres de zones (`tools/zone.sh import`) ; décidé le 2026-10-06. Priorité des textes : **capture > Wowhead > base** (Wowhead montre le texte Forever, VMaNGOS celui de Classic ; les deux diffèrent sur certaines quêtes). Wowhead n'est plus crawlé (403 CloudFront ; crawler retiré le 2026-11-01) ; ses données déjà en cache restent. | 4 989 quêtes, 13 308 PNJ ; 3 447 quêtes Alliance, 1 284 PNJ qui parlent ; texte français de début pour 71 %, de fin pour 84 %. Le reste (quêtes nouvelles de Forever) viendra des captures. |
| D11 | **Voix et audio produits en local avec Qwen3-TTS** (2026-10-07), à la place d'ElevenLabs (code, voix et audio ElevenLabs supprimés le 2026-10-07). Deux boucles : **voix** (`tools/voices/`, VoiceDesign crée la voix modèle de chaque PNJ depuis sa fiche et l'accent de sa race, `data/accents.json`) puis **lectures** (`tools/readings/`, Base clone cette voix pour lire chaque script). Un **juge** scellé (Whisper large-v3 : anglais ≤ 0,15 %, mots mal lus ≤ 15 %, débit ; ECAPA pour les lectures : ressemblance ≥ 0,75) garde ou rejette chaque essai ; 5 essais par exécution, jamais d'abandon. Un PNJ dont les lectures échouent sur la ressemblance : on refait sa voix modèle (`tools/voices/redo.py`). **Exception : Elise** (D9) reste sur ElevenLabs. | Gratuit et sans limite (ElevenLabs : 95 créations de voix par mois) ; qualité validée à l'oreille (Elwynn : 41 voix, 129/129 lectures). |
| D12 | **Groupes et catégories** (2026-10-07) : les quêtes sont rangées comme sur Wowhead, un **groupe** (continent ou thème : `eastern-kingdoms`, `classes`, `professions`, `dungeons`…) contient des **catégories** (`elwynn-forest`, `warrior`…). Une quête n'est que dans une catégorie (une quête de classe reçue à Northshire est dans `classes/warrior`). Toute boucle et le rapport disent ce qu'ils couvrent : `--all`, ou `--group G [--category C]…` (une catégorie toujours avec son groupe ; `tools/loop/scope.py`). | La commande suit la structure des données ; pas d'ambiguïté (`alterac-valley` existe dans deux groupes). |
| D13 | **Mise à jour = synchronisation** (2026-10-08) : on suit les **releases** (tags) de la Forever Database (`tools/db_check.sh`, `tools/prepare_db.sh --update`), puis `tools/zone.sh sync [--dry-run]`. Une quête n'existe qu'à un endroit et se reconnaît à son **ID, jamais à sa catégorie** : déplacée, elle emporte script, audio et lectures ; retirée de la base, elle est archivée (`data/archive/quests.json`) et restaurée si elle revient. Jamais retirée : une quête capturée en jeu ou d'une autre source. Un texte changé est listé, le refaire est une décision humaine. | La sortie (4/11/2026) va déplacer et retirer des quêtes (l'île de Zephras est dans `uncategorized` sur la beta) : ne rien regénérer pour un simple rangement. |
| D14 | **Dialogues des PNJ** (2026-10-10) : le texte de la fenêtre de discussion d'un PNJ (icône de bulle), page après page, **seulement le texte du PNJ** (jamais les lignes que le joueur clique), lu par sa voix. Importés de VMaNGOS (`gossip_menu` → `npc_text` → `broadcast_text`, français ; `pipeline/foreverdb/dialogues.py`, `tools/zone.sh dialogues`, aussi par l'import) dans `data/zones/<groupe>/<catégorie>/dialogues.json`, avec les quêtes qui les conditionnent ; PNJ amicaux envers l'Alliance ; un PNJ qui n'a que des dialogues est ajouté au `npcs.json` (`dialogue_only`) pour avoir sa fiche (consigne v4) et sa voix. Scripts : section `dialogues` de `scripts.json`. **Boucle dialogues** (`tools/dialogues/`, Qwen comme les lectures, ses propres fichiers `dialogue_audio.json` et `dialogue_readings.json`). Texte de Classic ; S11 fait le 2026-10-21 : `C_GossipInfo.GetText` lit chaque page, 92 % des captures retrouvées dans la base, les PNJ de Forever n'y sont pas (captures). **Lus en jeu depuis le 2026-10-21** (§9.18, index v9). | 876 PNJ, 3 182 pages en français (Alliance) ; 359 PNJ ajoutés. Les paroles déjà sonores du jeu (cris, escortes) ne sont pas concernées. |
| D16 | **Elise présente chaque zone** (2026-10-11) : la première fois que le personnage pose le pied dans une zone, **au sol** (jamais en griffon : à l'atterrissage, la zone d'arrivée), **après 2 minutes passées dans la zone** (2026-10-15 : à la première connexion, la cinématique du jeu la couvrait ; une cinématique encore en cours la repousse à sa fin), sa présentation passe dans la liste de lecture, icône de carte (exploration). 48 zones des deux continents, villes et zones de la Horde comprises (`pipeline/zone_intros/zones.py` : zones de premier niveau de la Forever Database, nom français, **identifiant de carte** `uiMapId`, celui de `C_Map.GetBestMapForUnit`, non vérifié : S12). Textes écrits par Claude (`python -m pipeline.zone_intros generate`, consigne `prompt_v2.md`, Opus, 60 à 90 mots, lore + dossier des registres ; **toujours du point de vue de l'Alliance** : Elise est la narratrice de l'Alliance, une terre de la Horde est racontée par son lore et son danger, sans rien à y faire), dans `data/zones/<groupe>/@intros/scripts.json` (section `zones`) ; audio par **la boucle Elise** (`--all` seulement : les présentations ne sont dans aucune catégorie), section `zone` de `audio.json`. Lecture automatique **seulement avec son audio** ; une zone entendue est retenue par personnage (`ForeverSpeechDB.zonesSeen`) ; `/fs zone [where\|reset\|on\|off]` ; **bouton lecture en haut à droite de la carte du monde** pour réécouter la présentation de la zone affichée (2026-10-12, `ui/map_button.lua`). **Récit du lieu** (2026-10-21, `ui/map_panel.lua`, idée de Spoken) : une page de parchemin contre le bord droit de la carte, nom de la zone, texte d'Elise, **une peinture de la zone** (Codex, `tools/zone_pictures.ts`, `media/zones/<mapID>.tga`, non versionnées, refaites depuis `data/icons/zones/`), bouton rond de lecture ; zone non découverte : texte et voix gardés pour plus tard ; pas de sous-zones (décidé le 2026-10-21) ; non vérifié : T44. Index v5. | Elise devient la compagne du joueur (D9) ; idées suivantes : `docs/ideas.md`. |
| D17 | **Elise à chaque niveau gagné** (2026-10-11) : une réplique par niveau (2 à 60), **une seule histoire** qui mène des premiers pas à la vision de la fin du jeu (Ragnaros, Onyxia, Nefarian, Ahn'Qiraj, Naxxramas) ; fil propre à Elise (sentinelle au Mur du scarabée, révélé peu à peu) ; positive, valorise le joueur, **en crescendo, sans jamais en faire trop** ; côté Alliance. Claude écrit l'arc et les 59 répliques d'un coup (`python -m pipeline.level_lines generate`, `prompt_v1.md`, Opus ; `again <niveau>` pour en refaire une dans la même histoire), dans `data/zones/@elise/levels/scripts.json` ; audio par la boucle Elise (`--kind level`, `--all`). En jeu : `PLAYER_LEVEL_UP` (non vérifié), **2 s après**, la réplique passe dans la liste de lecture, icône de lumière sacrée ; automatique seulement avec son audio ; `/fs level [n\|on\|off]`. Index v6. | Idée I1 de `docs/ideas.md`, demandée le 2026-10-11. |
| D18 | **Journal des compagnons** (2026-10-14, critères validés ; codé le 2026-10-15, `core/companions.lua`, `ui/companions_panel.lua`, index v8 ; non vérifié : T27) : les joueurs avec qui le personnage a groupé (sous-groupe en raid, champs de bataille exclus, membres connectés, 5 min au moins), table de 100 par personnage, top 10 affiché ; **paliers** par temps cumulé (Rencontre, Compagnon de route 30 min, Camarade 3 h, Bon ami 10 h, Ami proche 30 h, Frère d'armes 75 h ; Meilleur ami : le n° 1 avec 10 h au moins) ; statistiques (part du temps de jeu, groupes, première rencontre…) ; infobulle du joueur et icône dans la barre de titre de la fenêtre (onglet sur le côté jusqu'au 2026-10-21) (insigne sur les cadres de groupe plus tard). **Elise à chaque palier franchi** : une de ses 10 répliques du palier, au hasard sans redite (`data/zones/@elise/companions/scripts.json`, écrites à la main, versionnées ; audio par la boucle Elise). Tout : [docs/companions.md](docs/companions.md). **Le détail d'un compagnon à la place de la liste de lecture** (2026-10-18 ; depuis le 2026-10-21, dans la fenêtre à part des compagnons) : dans la vue Compagnons, le cadre de droite (celui de la liste de lecture, même place, même aspect) montre le compagnon cliqué (nom dans la couleur de sa classe, palier, une statistique par ligne) ; sans compagnon choisi, une invite ; toujours ouvert dans cette vue (pas de flèche) ; la ligne choisie est surlignée et le reste. La liste des compagnons a toute la hauteur. De retour à la quête, la liste de lecture revient, ouverte ou fermée comme avant. Mécanisme : `PlayerFrame.RegisterPanel(nom, { …, side = { height, build } })`. Non vérifié : T37. | Idée demandée le 2026-10-14 : savoir avec qui l'on joue le plus. |
| D19 | **Livres lus par Elise** (2026-10-21) : tout texte qu'on lit dans le monde (livres, lettres, plaques, stèles : `page_text`), **jamais le courrier**, lu page par page par Elise avec sa voix ElevenLabs (D9). **Extraction** (`pipeline/books/extract.py` : VMaNGOS `page_text` + `locales_page_text`, objets de type TEXTE et objets d'inventaire avec page ; courrier et objets périmés exclus ; français seulement, D5) → `data/zones/@books/books.json` ; **scripts**, module à part (`pipeline/books/scripts.py` : lu tel qu'écrit, HTML en paragraphes, `$N` d'apostrophe retiré, dans la phrase « l'aventurier/l'aventurière », `$g` deux variantes, D8) → `scripts.json` section `pages` ; `tools/zone.sh books`. Périmètre Alliance (côté Alliance, neutre ou inconnu, signalé). **Boucle livres** (`tools/books/`, ElevenLabs `eleven_v4`, **sans juge depuis le 2026-11-01** (chaque prise ElevenLabs est gardée, validée par la règle « ElevenLabs est fiable » ; Whisper ne juge que Qwen, boucle Elise comprise), `--budget N` caractères, `--dry-run` hors ligne ; jamais en même temps que la boucle Elise ; **à sceller** après relecture : `tools/loop/seal.sh books`), audio `audio/1000000/book_<page>[_f].ogg`, section `book` de `audio.json`, cycle D15. En jeu : §9.17, index v9. Bilan : 314 livres dans le périmètre, 945 pages, 368 140 caractères (≈ 519 000 crédits avec les refus). **Sur le Mac** (API, comme toute boucle ElevenLabs ; le PC ne sert qu'à Qwen). Scellée le 2026-10-21 ; **toutes les pages faites le 2026-11-02** (950 lectures, 945 pages de 275 livres dans l'index ; forfait Pro, environ 177 000 crédits). Les livres propres à Forever viendront des captures (`ForeverSpeechCaptures.books`). | Demande du 2026-10-21 ; idée reprise de Spoken (sans son code ni ses données). |
| D15 | **Un cycle pour tout audio généré** (2026-10-10 ; lectures, répliques d'Elise, dialogues, voix modèles) : `todo` → `in_progress` → `refused` \| `validated` (par le juge ou à la main ; `pipeline/review.py`). **Un audio refusé est joué en jeu quand même** (son meilleur essai, marqué `refused`) jusqu'à ce qu'un essai passe. Décisions de la page de contrôle : **Valider** (un refusé), **Refuser** (un validé : refait à la prochaine passe), **Supprimer** (l'audio retiré entièrement, refait à la prochaine passe ; pour une voix modèle : `redo`). File `data/review/decisions.json`, appliquée quand aucune boucle n'écrit les mêmes fichiers. Valider et Refuser attendent la mise à jour des oracles (scellés, boucles arrêtées, décision humaine). | Les voix refusées valent mieux que la synthèse du client ; l'humain tranche ce que le juge ne sait pas juger. |

### Flux

```
[Jeu] Addon : UI + lecteur + capture ──► SavedVariables (ForeverSpeechCaptures)
                                              │
[Mac] Compagnon : surveille SavedVariables, Forever Database, registre PNJ,
                  (phase 3) génération audio ──► audio/*.ogg + data/index.lua
                                              │
[Jeu] Addon charge index.lua au /reload ; nouveaux .ogg visibles au prochain lancement (à confirmer, S2)
```

## 5. Contraintes du sandbox WoW (à respecter)

- Lua 5.1 (pas de `goto`, pas d'opérateur `//`, lib `bit` pour les opérations binaires). Pas de `io`, `os.execute` ni réseau.
- Lecture de fichiers : uniquement les fichiers de l'addon chargés via le TOC, et les sons/textures par chemin.
- Persistance : SavedVariables, écrites seulement au `/reload` et à la déconnexion. **Bug signalé sur la beta Forever : SavedVariables non rechargées à la connexion** → spike S3.
- Nouveaux fichiers ajoutés pendant que le client tourne : a priori invisibles avant redémarrage complet → spike S2.
- Anti-taint : jamais remplacer une fonction Blizzard ; utiliser `hooksecurefunc` et `HookScript`. Ne pas modifier de frames sécurisées en combat (`InCombatLockdown()`).
- Une seule globale : la table `ForeverSpeech`. SavedVariables : `ForeverSpeechDB` (réglages), `ForeverSpeechCaptures` (captures).

## 6. Environnement

- Client : WoW Forever beta **1.60.1** (build observé **70205** dans l'Info.plist le 2026-10-05 ; contenu Wowhead marqué 1.60.1.69893). Version d'interface du TOC : **`16001`, vérifiée en jeu le 2026-10-05** (`/dump select(4, GetBuildInfo())` → `16001, "", " "` : GetBuildInfo renvoie au moins 6 valeurs).
- macOS, dossier du jeu : `/Volumes/Games/Battle.net/World of Warcraft/_forever_/` (depuis le 2026-10-21 : la
  bêta est finie, `_forever_` est le test de charge, produit Battle.net `wowf`, build 1.60.1.70532, puis 1.60.1.70755 le 2026-11-03 et 1.60.1.70790 le 2026-11-05, toujours l'interface `16001` ; a priori
  aussi la version finale, sortie le 4/11/2026, à confirmer) → AddOns dans `…/_forever_/Interface/AddOns/`. Disque
  externe **Games** (Lexar ES3 512 Go en APFS, depuis le 2026-10-16), à brancher pour jouer. Sur le même disque :
  `_classic_beta_` (la bêta, finie ; réglages et captures de la bêta dans son `WTF/`) et `_retail_`.
- Dev : lien symbolique de `addon/ForeverSpeech` vers le dossier AddOns (`tools/link_addon.sh`). `/reload` suffit pour le Lua ; redémarrage complet pour tout nouveau fichier.
  Dossier du projet sur le Mac : `~/Documents/projects/cotcotquedec/alliance-epique` (renommé de `foreverspeech` le
  2026-11-06). Après tout déplacement du dossier : `node tools/relocate.ts <ancien chemin>` (environnements Python,
  luarocks, journaux des boucles, liens, worktrees), puis `tools/link_addon.sh` (refait un lien qui pointe ailleurs).
- Outils conseillés en jeu : BugGrabber + BugSack (erreurs Lua), `/fstack` (noms des frames), `/etrace` (événements).
- Outils locaux : LuaJIT + luacheck + busted dans `.luarocks/` (arbre local Lua 5.1), Python 3.12 dans `.venv/`. `tools/check.sh` lance tout.
  Voix (D11) : `.venv-voices/` (Qwen3-TTS, faster-whisper, speechbrain ; `tools/voices/setup.sh`), `ffmpeg` et
  `oggenc` (`vorbis-tools`). Installation complète : `tools/setup.sh` et `docs/pipeline.md`.
- **Deux machines de calcul** (2026-10-07) : le Mac (Apple Silicon, MLX) et un PC Windows avec une RTX 4090, sous
  **WSL2** (Ubuntu, PyTorch `qwen-tts`, CUDA 12.6). `tools/qwen_voices/backend.py` choisit selon la machine
  (`FS_TTS_BACKEND` pour forcer) ; vérification : `.venv-voices/bin/python -m tools.qwen_voices.doctor`. Le dossier
  du projet est copié entre les deux (les données ne sont pas dans git) ; une seule machine produit à la fois.
  **Sur le PC (WSL2), lire d'abord [docs/machines.md](docs/machines.md)** : différences, mise en route, pannes connues.
- `.data/` (non versionné) : la Forever Database (`.data/forever-db/`, 450 Mo de sources, 170 Mo de JSON construit)
  et un Lua 5.1.5 compilé depuis lua.org (`.data/lua-5.1.5/`, l'export QuestieDB dépasse la limite de constantes de
  LuaJIT). `tools/prepare_db.sh [--update]` refait tout.

## 7. Structure du dépôt

```
addon/ForeverSpeech/
  ForeverSpeech.toc
  core/        events.lua, capture.lua, autoplay.lua (lecture automatique, §9.1), index.lua (lookup), player.lua (son), game_voices.lua (voix du jeu coupées),
               zones.lua (présentations de zone d'Elise, D16), levels.lua (répliques de niveau, D17),
               fishing.lua (mode pêche, §9.10), played.lua (niveau et temps de jeu total, pour les compagnons), companions.lua
               (journal des compagnons, D18), announce.lua (annonce au groupe des quêtes terminées, §9.11),
               quest_area.lua (quêtes dont je suis dans la zone, §9.12), disenchant.lua (désenchantement, §9.13),
               text.lua (normalisation commune avec pipeline/match.py), books.lua (§9.17), dialogues.lua (§9.18),
               ducking.lua (§9.14), silence.lua (§9.16), bindings.lua (§9.15), check.lua (vérification du jeu, §2,
               chargé en dernier) ; Bindings.xml à la racine
  ui/          tracker_buttons.lua, questlog_buttons.lua, player_frame.lua, side_tabs.lua et
               fishing_tab.lua (onglets sur le côté, §9.10), emote_wheel.lua (roue d'émotes, §9.21), bag_tabs.lua (onglets du sac à dos, §9.13),
               bag_frame.lua (sac à dos déplaçable, §9.13), quest_sort.lua (quêtes triées par niveau, §9.20), style.lua (apparence commune, §9.19), map_panel.lua
               (récit du lieu, D16)
  data/        index.lua, game_voices.lua (GÉNÉRÉS — ne pas éditer à la main ; pipeline/build_index.py, pipeline/game_voices.py)
  audio/       test/*.ogg (phase 1), puis <npc>/<quest>_<kind>[_m|_f].ogg
  dev/         api.lua (/fs api : signatures de l'API du client ; les aides de la phase 0 sont retirées)
pipeline/      Python 3.11+ : foreverdb/ (import de la base), wowhead/ (lecture du cache des pages téléchargées
               jusqu'au 2026-10-12 et ses parsers : catégories de quêtes, ordre des zones, pages de zone d'Elise), quests/, npcs/, personas/
               (fiches, Claude), zone_intros/ (présentations de zone d'Elise, Claude, D16),
               level_lines/ (répliques de niveau d'Elise, Claude, D17), books/ (livres : extraction et scripts, deux
               modules, D19), match.py (normalisation de l'index v9), captures.py (lecture des SavedVariables),
               scripts.py (scripts, sans
               Claude), narration.py, build_index.py ; le « compagnon »
               (D3) = ces commandes lancées à la main
data/          (pas dans git, sauf accents.json) zones.json (catalogue), zones/<groupe>/<catégorie>/{quests,npcs,scripts,audio,readings}.json
               (registres, voir docs/data-registries.md ; D12), voices.json (fiche de personnalité, voice_text et
               voix Qwen3 par PNJ, voir docs/voices-and-text.md), accents.json (accent par race, D11), voices/samples/
               (voix modèles, banc), audio/ (masters FLAC), cache/ (Wowhead brut, boucles ; gitignore)
docs/spikes/   un fichier par spike : question, procédure, résultat, décision
docs/reference/ connaissances de référence sur le jeu (ex. npc-voices.md)
tests/         busted (Lua, avec stubs d'API WoW), pytest (pipeline)
tools/         scripts de dev (setup.sh, lien AddOns, relocate.ts, sons de test, check.sh, zone.sh, prepare_db.sh, report.sh)
tools/loop/    le moteur des boucles (arbitre, cliquet, sceau, périmètre --all/--group/--category) ;
               tools/base/, tools/text/, tools/voices/, tools/readings/, tools/dialogues/ (D14), tools/elise/ (D9),
               tools/books/ (D19) :
               constitution, oracle, juge, arbitre, acteur, critique de chaque passe (voir tools/loop/README.md)
tools/qwen_voices/ le cadre des voix modèles (frame.py, scellé), backend.py (MLX ou CUDA), doctor.py et les
               outils d'essai ; tools/voices/bench.py :
               le banc d'écoute (page unique, http://127.0.0.1:8765)
.data/         Forever Database et Lua 5.1 (non versionné, tools/prepare_db.sh)
```

## 8. Contrat d'index (couplage addon ↔ pipeline)

`addon/ForeverSpeech/data/index.lua`, généré. Toute évolution incrémente `version`.

```lua
ForeverSpeechIndex = {
  version = 9,
  quests = {
    [783] = {
      level = 1,                     -- v7 (2026-10-14) : niveau de la quête (registres), si connu
      giver = 823,                   -- PNJ donneur (registres) ; absent si objet/item
      ender = 197,                   -- v3 : PNJ de rendu ; absent si objet/item
      complete = { npc = 197, … },   -- v3 (2026-10-06) : fin de quête, mêmes champs que detail
      detail = {                     -- absent tant qu'aucun audio n'est généré
        npc   = 823,                 -- creatureID ; v4 : 1000000 (Elise, D9) si aucun PNJ ne le dit
        voice = "npc823@v1",         -- ID de voix versionné (changer la voix = régénérer)
        file  = "Interface\\AddOns\\ForeverSpeech\\audio\\823\\783_detail.ogg",
        fileF = nil,                 -- variante féminine si le texte contient $G ; sinon nil
        dur   = 23.4,                -- secondes (optionnel ; pour une barre de progression)
        src   = "wowhead_fr",        -- capture | wowhead_fr | test
      },
    },
  },
  npcs = {                           -- v2 (2026-10-05) : PNJ donneurs ; v3 : et PNJ de rendu
    [823] = { display = 2072, name = "Adjoint Willem" },  -- display → SetDisplayInfo (S8), tout PNJ
    [1000000] = { name = "Elise" },  -- v4 (2026-10-10) : la narratrice, sans modèle (son portrait, propre à l'addon)
  },
  zones = {                          -- v5 (2026-10-11) : présentations de zone d'Elise (D16), par identifiant de carte
    [1429] = { area = 12, name = "Forêt d'Elwynn", nameEn = "Elwynn Forest",
               text = "Sous les grands chênes…",   -- son texte : synthèse vocale du client tant que l'audio manque
               intro = { npc = 1000000, voice = "npc1000000@G6INpmIs", file = "…\\audio\\1000000\\12_zone.ogg",
                         dur = 31.2, src = "elise" } },  -- absent tant qu'aucun audio n'est fait
  },
  levels = {                         -- v6 (2026-10-11) : répliques de niveau d'Elise (D17), par niveau gagné
    [12] = { text = "Je m'appelle Elise…", intro = { npc = 1000000, …, file = "…\\1000000\\12_level.ogg" } },
  },
  companions = {                     -- v8 (2026-10-15) : journal des compagnons (D18)
    tiers = { { key = "encounter", name = "Rencontre", nameF = "Rencontre", from = 300 }, …,
              { key = "best_friend", name = "Meilleur ami", nameF = "Meilleure amie", from = 36000, rank = 1 } },
    lines = {                        -- ID = place du palier × 100 + variante (401 : bon ami, réplique 1)
      [401] = { tier = "good_friend", text = "C'est plus qu'une route partagée…", intro = { npc = 1000000, … } },
    },
  },
  books = {                          -- v9 (2026-10-21) : livres lus par Elise (D19), clé fs_key(titre)
    ["tombedeliza"] = { title = "Tombe d'Eliza", pages = {
      [1] = { { fp = "<fs_fp(texte de la page)>", intro = { npc = 1000000, voice = "npc1000000@G6INpmIs",
               file = "…\\audio\\1000000\\book_731.ogg", fileF = nil, dur = 12.5, src = "elise" } } } } },
  },
  dialogues = {                      -- v9 : pages de dialogue des PNJ avec audio (D14, D15), par PNJ
    [197] = { { page = "7590", words = "<40 premiers jetons fs_norm du texte de base>",
                intro = { npc = 197, voice = "npc197@q…", file = "…\\audio\\197\\dialogue_7590.ogg", fileF = nil,
                          dur = 7.5, src = "qwen" } } },
  },
}
```

**Normalisation commune** (v9) : `pipeline/match.py` = `core/text.lua`, octet pour octet (testé) : marqueurs `$B`,
`|n`, couleurs retirés ; variables `$N $C $R` et `$g…:…;` retirées ; minuscules ASCII seulement ; ponctuation et
blancs ASCII, `’ « » … – —` et espaces insécables comme séparateurs → jetons. `fs_key` = jetons collés (titres),
`fs_fp` = ses 48 premiers octets (empreinte de page). Livre : `books[fs_key(ItemTextGetItem())].pages[ItemTextGetPage()]`,
l'entrée dont `fp` correspond (seule entrée sinon). Dialogue : mêmes mots (après retrait du nom, de la classe et de
la race du personnage comme suites de jetons ; une page coupée à 40 jetons se compare aux 40 premiers), sinon le
meilleur score ≥ 0,7. L'addon accepte encore un index v8.

`build_index.py` lit les registres `data/zones/**` (donneur et modèle) et, en option, un fichier d'entrées audio.
Le lecteur prend le donneur de la capture, sinon `giver` ; puis `npcs[id].display` pour le modèle 3D et `name`
si la capture n'a pas de nom. Pour une fin de quête : le PNJ de la capture de rendu, sinon `ender`. Sans PNJ (v4) :
le nom de la capture (un objet), sinon celui de l'orateur de l'audio, `npcs[detail.npc].name` (« Elise »).

Sélection de fichier : `fileF` si `UnitSex("player") == 3` et `fileF ~= nil`, sinon `file`. Depuis le 2026-11-05, un
chemin de `ForeverSpeech\audio\` est lu dans `AllianceEpique_Voix\audio\` quand ce dossier (les voix, livrées à part)
est installé (`Index.FileFor`, `C_AddOns.DoesAddOnExist` ; non vérifié : T69, H43).
Entrée absente → fallback **et** capture enregistrée pour génération ultérieure. Fallback par défaut depuis le 2026-10-05 : **TTS du client** (`C_VoiceChat.SpeakText`, voix fr-FR, disponible sur Forever, S5) sur le texte capturé, sinon le texte du journal. Autres réglages : `test` (son de test) ou `none` (`/fs fallback`).

## 9. Spécification fonctionnelle — Phase 1 (audio de test)

1. **Lecture automatique** (2026-10-21, `core/autoplay.lua`, réglage « Lecture automatique des quêtes acceptées et rendues », `autoplay`, **activé par défaut**, `/fs autoplay on|off`) : une quête acceptée est lue **2 s après** l'événement du jeu `QUEST_ACCEPTED`, une quête rendue a sa fin lue 2 s après `QUEST_TURNED_IN` (après les quelques mots du PNJ), **quelle que soit l'interface** : boutons du jeu ou **Dialogue UI** (qui cache `QuestFrame` et appelle ses propres copies d'`AcceptQuest` et `GetQuestReward`, faites avant nos crochets ; vérifié en jeu le 2026-10-21, T56). Les événements suivent la réponse du serveur : une quête refusée (journal plein, sacs pleins) n'est pas lue. **Retirés le 2026-10-21** (demande du joueur : une seule option) : les boutons « Accepter et lire » (2026-10-05) et « Terminer et lire » (2026-10-10), la vérification du journal après leur clic (T32) et la lecture de la fin à l'ouverture de « Terminer » (`readOnTurnIn`, `/fs turnin`) ; migration des réglages v4 (`autoplay` remis à vrai). Non vérifié : T57.
2. **Capture** à `QUEST_DETAIL` (avant l'acceptation, la fenêtre se ferme ensuite) : questID, titre, texte (`GetQuestText`), objectifs (`GetObjectiveText`), creatureID via `UnitGUID("npc")` (vérifier que le format du GUID est `Creature-0-…-<id>-…` sur Forever), nom du PNJ, `UnitSex("npc")`, `UnitCreatureType("npc")`, zone, locale, sexe du joueur, horodatage → `ForeverSpeechCaptures`. Dédupliquer par (questID, hash du texte côté Lua autorisé ici uniquement pour la déduplication).
3. **Bouton lecture dans le suivi d'objectifs** : le suivi recycle ses blocs → se greffer sur sa fonction de mise à jour ou de layout (à identifier, S4), jamais sur des frames supposées fixes. Le bouton passe en « Stop » pendant la lecture.
4. **Bouton lecture dans le journal de quêtes**, même comportement.
5. **Lecteur** (frame déplaçable, position sauvegardée) :
   - visuel : depuis le 2026-10-21, le PNJ dans un médaillon rond en tête (§9.19 : son portrait 2D, sinon son modèle 3D,
     `SetDisplayInfo(displayID)`, S8), sinon icône de quête ; pour Elise (D9), son portrait peint, recadré sur son
     visage, sinon l'icône de quête ou de sa réplique ;
   - titre, PNJ, état, puis les boutons en icônes sous l'état ; le titre porte le **niveau de la quête** comme le
     suivi d'objectifs (2026-10-14) : `[12] Titre` dans la couleur de sa difficulté (gris, vert, jaune, orange,
     rouge ; niveau du journal, sinon de l'index v7 ; couleur de `GetQuestDifficultyColor`, sinon règles de Classic ;
     non vérifié : T26) ; **depuis le 2026-10-18, un blason** (en haut à droite, à côté du titre, 52 px, depuis le 2026-10-21), à la place de `[12]` : un
     par difficulté, du simple écu de bois (gris) au crâne en flammes (rouge), le niveau au centre dans la couleur
     de la difficulté (`media/difficulty/<clé>.tga`, découpés par `tools/difficulty_badges.ts` dans la planche
     peinte `data/icons/difficulty/sheet.png`, image ChatGPT ; `[12]` en secours ; non vérifié : T35) ;
     objectifs : le résumé (3 lignes au plus), puis
     **une ligne par objectif du journal** (2026-10-10) : une case à cocher et une barre de progression avec
     l'objectif écrit dedans, en direct (`C_QuestLog.GetQuestObjectives` ; la part faite vient de
     `numFulfilled`/`numRequired`, sinon du « 3/12 » ou « 45 % » du texte) ; objectif fait : case cochée, barre
     grisée ; 5 lignes au plus, la fenêtre grandit au besoin ; récompenses juste
     dessous (icônes d'objets, argent, XP si disponible). **Texte de la quête** en petit sous le modèle, réglage
     « Afficher le texte de la quête » (activé par défaut, 2026-10-07 ; avant : pas de description) : texte du jeu
     uniquement (capture, sinon journal ; pour une fin, le texte de rendu capturé), jamais les registres ; fermeture
     par la croix en haut à droite. **Les options sont dans le menu du jeu** (2026-10-21 : Échap > Options > AddOns >
     ForeverSpeech, une sous-catégorie par thème, API Settings ; non vérifié : T46), sinon **leur propre fenêtre** (2026-10-15, `ui/options_frame.lua`) :
     sept thèmes à gauche (Général, Lecture des quêtes, Fenêtre de quête, Elise, Compagnons, Confort, Avancé), leurs
     réglages à droite ; ouverte par l'engrenage, le clic droit sur l'icône de la minimap ou `/fs options [thème]`, et
     à la place de la fenêtre principale quand l'audio est coupé ; position et dernier thème retenus. Interrupteurs
     ajoutés pour ce qui était toujours actif : niveau de la quête dans le titre, bandeau du bas, cadrage du modèle
     (4 cadrages), suivi, infobulle et annonces des compagnons, onglet de pêche, émotes, bouton de la carte ; boutons
     « Réentendre toutes les zones » et « Réinitialiser les options » (deux clics ; la place de l'icône de la minimap
     est gardée). Non vérifié : T29 ;
   - boutons **Lecture** (toujours depuis le début), **Avancer** (quête suivante de la liste), **Stop** ;
   - un seul son à la fois, avec **liste de lecture** (décidé le 2026-10-05, ordre fixe le 2026-10-05) :
     - la liste garde son ordre et contient chaque quête une seule fois ;
     - **lire une quête** (boutons ▶, lecture automatique, `/fs play`) la met toujours dans la liste : à la fin,
       ou à sa place si elle y est déjà (une quête lue redevient « à lire ») ; si la liste est en lecture, elle
       continue ; sinon cette quête démarre tout de suite ;
     - **pause entre deux quêtes** (2 s par défaut, réglable dans Options) et son de page plus fort (canal
       Master, deux copies) pour bien entendre le changement de quête ;
     - **Stop** coupe la lecture en cours (`StopSound(handle)`) et arrête la liste ; les quêtes pas encore lues
       restent. **Avancer** (`/fs next`) passe tout de suite à la première quête pas encore lue ;
     - **double-clic** sur une ligne, ou **Lecture** dans la fenêtre (pour la quête affichée) : stop, puis cette
       quête repart du début, à sa place, sans changer l'ordre (ajoutée à la fin si elle n'est pas dans la liste) ;
       Avancer et Stop agissent sur la liste ;
     - la liste **fait partie de la fenêtre**, comme le journal de quêtes de la carte (2026-10-13) : ouverte, la
       fenêtre s'élargit ; on l'ouvre et la ferme par **le petit bouton rond aux trois barres**, à la suite de
       Lecture / Avancer / Stop (2026-10-21 ; avant : la flèche du jeu en bas à droite ; infobulle « Ouvrir / Fermer la
       liste de lecture ») ; le coin haut gauche reste fixe ; cadre du jeu
       (`PortraitFrameTemplate`, sans portrait) ; plus d'onglets : un
       engrenage à gauche de la croix ouvre la fenêtre d'options, recliqué il la ferme ; en bas, le bandeau du sac à
       dos avec l'or et le niveau du personnage (2026-10-14, **retiré le 2026-11-05** à la demande du joueur ; le temps
       de jeu à ce niveau l'était depuis le 2026-10-18 : l'addon sert à profiter de l'histoire, pas à compter le temps) ; `core/played.lua` demande le temps de jeu total à l'entrée en jeu, pour le journal des
       compagnons (`RequestTimePlayed`, réponse `TIME_PLAYED_MSG` gardée hors du chat ; T26) ;
     - bouton **Vider** en haut de la liste et `/fs reset` : tout s'arrête, la liste est vide ;
       `/fs clear` arrête tout et retire les quêtes pas encore lues ;
   - fin de lecture : sondage de `C_Sound.IsPlaying(handle)`. `SOUNDKIT_FINISHED` ne se déclenche pas
     pour `PlaySoundFile` (S5). Minuterie sur `dur` en secours ;
   - **journal de bord** (2026-10-10, réglage « Hors lecture, afficher la quête suivie », activé par défaut) :
     quand la liste n'a plus rien à lire (dernière quête finie, Avancer sur la dernière, Vider), la fenêtre revient
     à la **quête suivie** (celle mise en avant dans le suivi, sinon la première du suivi ; `C_SuperTrack`, non
     vérifié sur Forever) ; hors lecture, elle suit chaque changement de quête suivie, et une quête choisie à la main
     reste affichée jusque-là. Jamais pendant une lecture ou la pause entre deux quêtes, ni après Stop ; elle ne
     s'ouvre pas d'elle-même et ne change pas d'onglet (fermée, elle s'ouvre sur la quête suivie).
6. **Commande** `/fs` : `test`, `play [questID]`, `show [questID]`, `stop`, `next`, `clear`, `queue`, `debug on|off` (désactivé par défaut),
   `reset`, `zoom [0-1]` (cadrage du modèle 3D), `captures`, `channel`, `fallback tts|test|none`, `autoplay on|off`,
   `npcvoices on|off`, `zone [mapID|where|reset|on|off]` (D16), `level [n|on|off]` (D17),
   `fish` (mode pêche, §9.10), `options [thème]` (fenêtre d'options), `friends [on|off|say <palier>]` (journal des compagnons, D18),
   `announce [questID|on|off|party|say]` (annonce au groupe, §9.11), `area` (quêtes dont je suis dans la zone, §9.12),
   `disenchant` (objets à désenchanter, §9.13), `bag [reset]` (place du sac à dos, §9.13), `duck on|off` (baisse du
   son du jeu, §9.14), `books [on|off]` (livres lus par Elise, §9.17), `gossip [on|off]` (dialogues des PNJ, §9.18), `sort [on|off|probe]` (quêtes triées par niveau, §9.20), `check` (vérification du jeu, §2).
7. Canal audio : « Dialog » par défaut, configurable.
8. **Fin de quête** (2026-10-06) : capture du texte de rendu à `QUEST_COMPLETE` (`GetRewardText`, PNJ de rendu,
   `ForeverSpeechCaptures.completions`, vérifié sur Forever le 2026-10-07, S9) ; **lue une fois la quête rendue**
   (lecture automatique, §9.1), comme toute quête dans la liste de lecture. Une quête peut y être deux fois :
   **!** début, **?** fin. (Lue à l'ouverture de l'onglet « Terminer la quête » du 2026-10-07 au 2026-10-21, puis
   retiré.)
9. **Voix du jeu coupées avec les PNJ à quête** (2026-10-10, réglage « Couper les voix du jeu des PNJ à quête »,
   activé par défaut, `/fs npcvoices on|off`) : tant que l'audio est activé, les répliques d'origine des PNJ
   (salutations, adieux, répliques agacées, salutations de marchand, voix uniques du lore) sont coupées par
   `MuteSoundFile`, **seulement avec un PNJ qui a une quête pour le joueur** ; les autres gardent leur voix. La
   salutation part au clic : la coupure se décide au survol (ou à la cible d'interaction) d'après l'index (donneur
   d'une quête ni faite ni dans le journal, destinataire d'une quête du journal prête à rendre) ; fenêtre ouverte,
   sa liste de quêtes décide ; 2 s de plus après sa fermeture pour l'adieu. Un PNJ dont la fenêtre ne montre aucune
   quête à prendre est retenu (l'index ignore niveau, classe et prérequis) jusqu'au prochain changement du journal. Les 1 035 fichiers viennent de la liste Wowhead Classic
   « NPC Greetings » en cache (`pipeline/game_voices.py` → `data/game_voices.lua`, non versionné). Vérifié sur
   Forever le 2026-10-10 (S10) : la coupure marche, mais les PNJ ajoutés par Forever parlent encore (leurs voix ne
   sont pas dans la liste) ; gardé tel quel.

10. **Onglets sur le côté** (2026-10-13, `ui/side_tabs.lua`) : de petits interrupteurs collés au bord gauche de la
   fenêtre, à l'extérieur, un par amélioration de confort (grisé : éteint ; en couleur, cadre lumineux : allumé ;
   verrouillé en combat). Premier : **la pêche** (sur le côté du sac à dos depuis le 2026-10-20, au-dessus du
   désenchantement, §9.13 ; affichée avec le sac) (`core/fishing.lua`, `ui/fishing_tab.lua`, `/fs fish`) : la canne des
   sacs équipée, armes retenues par personnage ; reclic : les armes reviennent. La pêche se lance depuis une barre
   d'action (pas de bouton de l'addon : un bouton sécurisé, essayé puis retiré le 2026-10-13). Onglet affiché seulement
   si le personnage connaît la pêche et a une canne (sacs ou main), et toujours en mode pêche. **Icônes peintes pour
   l'addon** (2026-10-15, `media/tabs/*.tga`, 64×64 ; originaux `data/icons/tabs/`, Gemini 3 Pro Image par OpenRouter ;
   `tools/tab_icons.sh`). Les boutons d'émote du bas de la tranche (Saluer, Remercier, S'asseoir, Féliciter,
   `ui/emote_tabs.lua`, 2026-10-13) sont **retirés le 2026-10-21** : la roue d'émotes les remplace (§9.21), qui garde
   leurs icônes ; le bord de la fenêtre est vide.
11. **Annonce au groupe des quêtes terminées** (2026-10-17, `core/announce.lua`, idée reprise de Questie sans son
   code ; réglage dans Options > Confort, activé par défaut) : **en groupe seulement**, quand tous les objectifs d'une
   quête du journal passent de « à faire » à « faits » pendant la session (`QUEST_LOG_UPDATE`, `GetQuestObjectives`),
   une ligne `{rt1} J'ai terminé « Titre » : objectif : 6/6 ; ….` (255 octets au plus), une fois par quête et par
   session, jamais pour une quête déjà faite à la connexion. Canal **Groupe** par défaut (`PARTY`, `RAID` ou
   `INSTANCE_CHAT` : la bulle s'affiche au groupe), ou **Dire (/s)** : un addon ne peut sans doute pas écrire en `/s`
   hors instance sans clic (bloqué sur Classic depuis 1.13.3 ; message dans le chat s'il est bloqué). Non vérifié : T33.
12. **Quêtes dont je suis dans la zone** (2026-10-18, `core/quest_area.lua` ; réglage dans Options > Confort, activé
   par défaut) : la **zone d'une quête** est la tache de ses objectifs sur la minimap et la carte, pas la région. Le
   jeu ne met pas à part ces quêtes (H15) : l'addon les fait ressortir **dans le suivi** (barre dorée derrière le titre,
   fond doré sur les objectifs, trait doré foncé à droite) et **dans le journal** (barre dorée sur la ligne du titre), sans changer l'ordre du suivi.
   **C'est le jeu qui décide** (H16, vérifié le 2026-10-18) : un `QuestPOIFrame` invisible de l'addon dessine la zone
   d'une quête à la fois (`SetMapID`, `DrawBlob`) et `UpdateMouseOverTooltip(x, y)` dit si la position du joueur
   (`C_Map.GetPlayerMapPosition`, normalisée) y est ; pour les quêtes de `C_QuestLog.GetQuestsOnMap`, chaque seconde
   si le joueur a bougé. `/fs area` les dit dans le chat. Non vérifié : T34 (rendu et fluidité).
13. **Onglets du sac à dos et désenchantement** (2026-10-18, `ui/bag_tabs.lua`, `core/disenchant.lua`) : une barre
   d'onglets sur le côté, comme celle de la fenêtre (`ui/side_tabs.lua` gère plusieurs barres et des **onglets
   sécurisés**), collée au bord gauche du cadre qui montre le sac à dos (sac combiné `ContainerFrameCombinedBags`,
   sinon le `ContainerFrameN` du sac 0). Premier onglet : **Désenchanter**, affiché seulement si le personnage connaît
   le sort (13262 ; réglage dans Options > Confort). **Un clic sur l'onglet lance le sort comme le grimoire** (onglet
   `SecureActionButtonTemplate`, `type = spell` ; rattaché à l'écran, posé sur la barre, retiré en combat par
   `PLAYER_REGEN_DISABLED` pour qu'aucun cadre du jeu ne devienne protégé) ; **tant que le curseur attend l'objet**
   (`SpellIsTargeting`, sondé), une bordure dorée sur chaque case dont l'objet se désenchante et l'onglet est allumé ;
   le clic sur l'objet est celui du jeu (décidé le 2026-10-18, à la place d'une première version : interrupteur et
   bouton sécurisé posé sur la case survolée). **Ce qui se désenchante : l'infobulle de l'objet le dit** (idée du
   joueur, 2026-10-18) : la ligne du jeu « Peut être désenchanté » ou « Désenchantement : … requis » (la compétence
   n'est pas comptée : trop haut, le jeu refuse), et non « Ne peut pas être désenchanté » ; comparée aux chaînes du jeu
   (`ITEM_DISENCHANT_ANY_SKILL`, `ITEM_DISENCHANT_MIN_SKILL`, `ITEM_DISENCHANT_NOT_DISENCHANTABLE`), lue par
   `C_TooltipInfo.GetBagItem`, sinon une infobulle cachée. (Essayé d'abord : la liste de la Forever Database, VMaNGOS
   `disenchant_id` ; elle ignore les objets propres à Forever, presque tous les verts de ses quêtes, H18.) Pendant la
   visée, `ForeverSpeechDB.disenchantCheck` garde ce que dit chaque objet. `/fs disenchant` dit combien d'objets se
   désenchantent. H18 vérifié (sac combiné de Retail, `GetBagID`, `UpdateItems`, le sort 13262 lancé par l'onglet) ;
   non vérifié : T36.
   **Le sac combiné se déplace** (2026-10-20, `ui/bag_frame.lua`) : glissé par son bord ou son titre, sa place est
   retenue (`ForeverSpeechDB.bagPos`) et remise après chaque rangement des sacs par le jeu
   (`UpdateContainerFrameAnchors`) ; `/fs bag [reset]`, Options > Confort. **Une ligne par sac** (réglage `bagRows`, activé par défaut) : après la grille du
   jeu, ses cases reprises sac par sac, le sac à dos en haut, chaque sac à la ligne sous son nom, ses cases et ses cases
   libres, un trait entre deux sacs, le cadre grandi d'autant, même quand le jeu le redimensionne (colonnes, pas et coin
   de la grille du jeu ; le premier titre remonté de 11 pixels sous la recherche, 6 de plus sous le dernier sac) ; `/fs bag slots` dit la taille de
   chaque sac. Sacs séparés : laissés au jeu. **Règle (2026-10-20) : les onglets des métiers vont sur le sac** : la
   pêche, puis **un onglet par métier appris qui a une fenêtre** (2026-11-05 ; la cuisine et la couture depuis le
   2026-10-20) : alchimie, forge, enchantement, ingénierie, travail du cuir, couture, fonte (le minage), cuisine,
   secourisme ; onglets sécurisés qui lancent le sort du métier par son nom, donc le rang connu, et ouvrent sa fenêtre ;
   réglage `professionTabs`. **Grisé, toujours cliquable**, quand le jeu dit que le lieu du métier n'est pas à
   proximité (cuisine : un feu ; fonte : une forge ; forge : une enclume ; `C_TradeSkillUI.IsNearProfessionSpellFocus`,
   demandé deux fois par seconde sac ouvert ; sans réponse du jeu, jamais grisé ; l'infobulle dit ce qui manque). Puis
   Désenchanter. Vérifié en jeu le 2026-11-05 (T62, H37) ; non vérifié : T38. Les onglets sécurisés suivent le sac quel
   que soit celui qui le déplace (2026-11-05, §9.22).
14. **Le son du jeu baisse pendant une lecture** (2026-10-21, `core/ducking.lua`, idée de Spoken, MIT) : pendant toute
   lecture de l'addon, la musique, l'ambiance et les effets descendent en 0,8 s à 30 %, 40 % et 60 % du réglage du
   joueur (jamais le canal de l'addon, `channel`) et remontent 1,2 s après la fin de la liste (pas entre deux quêtes).
   Valeurs d'origine gardées dans `ForeverSpeechDB.duckState` ; un curseur bougé par le joueur n'est plus touché ;
   remise immédiate à `PLAYER_LOGOUT` (`/reload` compris), et à la connexion après un plantage. Réglage `duck`
   (Options > Lecture des quêtes, activé). Non vérifié : T41.
15. **Raccourcis clavier** (2026-10-21, `Bindings.xml`, `core/bindings.lua`) : Options > Raccourcis > AddOns >
   ForeverSpeech : Lecture / Stop (la quête affichée), Avancer, Stop. `Bindings.xml` est lu par le client sans ligne
   dans le TOC (redémarrage complet). Non vérifié : T41.
16. **Silence en champ de bataille et en arène** (2026-10-21, `core/silence.lua`) : l'addon n'y lance rien de lui-même
   (zone, niveau, compagnons, lecture automatique des quêtes, livres, dialogues :
   `Player.AUTO`) ; ce que le joueur demande est lu ; en entrant, ce que l'addon avait mis lui-même dans la liste en est
   retiré. Réglage `readInBattleground` (Options > Général, désactivé). **Valeurs secrètes** : en donjon et en combat,
   Forever rend secrets le nom et le GUID du PNJ, `GetTitleText`, `GetQuestID` (fait relevé par Spoken) ; l'addon les
   lit par `H.Safe` / `H.NotSecret` (secret = inconnu). Non vérifié : T42.
17. **Livres et plaques lus par Elise** (D19, 2026-10-21, `core/books.lua`, index v9 `books`) : chaque page affichée
   (`ITEM_TEXT_READY`) est capturée (`ForeverSpeechCaptures.books`) puis lue : l'audio d'Elise (titre et empreinte du
   texte, `core/text.lua`), sinon le repli des quêtes (synthèse vocale) ; page tournée : la suivante remplace la page en
   cours ; livre fermé : arrêt. Une lettre (d'un joueur, ou à la boîte aux lettres) n'est ni lue ni capturée. Réglage
   `readBooks` (activé). Non vérifié : T39.
18. **Dialogues des PNJ lus en jeu** (D14, 2026-10-21, `core/dialogues.lua`, index v9 `dialogues`) : 0,1 s après
   `GOSSIP_SHOW`, le texte est comparé aux pages du PNJ (§8) et lu dans la voix du PNJ, son modèle 3D dans la fenêtre ;
   page suivante : remplace ; fenêtre fermée : arrêt. Pas de synthèse vocale pour un dialogue. Sa salutation du jeu est
   coupée comme celle d'un PNJ à quête (§9.9). Réglage `readGossip` (activé). Non vérifié : T40.
19. **Apparence de la fenêtre** (2026-10-21, `ui/style.lua`, `ui/player_frame.lua` ; demandée pour égaler la finition
   de Spoken sans rien lui prendre ; état final après cinq passes et quatre maquettes, le détail : `git log`) :
   - **éléments peints pour l'addon par Codex** (`tools/ui_icons.ts`, originaux `data/icons/ui/`) : l'anneau bronze et
     or des boutons ronds et du médaillon, les pictogrammes dorés (Lecture, Stop, Avancer, Rejouer, Liste), la
     nouvelle icône de l'addon ; boutons éclairés au survol, enfoncés au clic, grisés désactivés, son du jeu au clic,
     infobulles en trois niveaux ; dans le suivi et le journal, le pictogramme sur la case fine du jeu ;
   - **en-tête « médaillon »** (choisi parmi quatre maquettes) : le PNJ dans un médaillon rond (son portrait 2D du jeu,
     `SetPortraitTextureFromCreatureDisplayID`, masqué rond ; sinon son modèle 3D cadré sur la tête dans l'anneau ;
     Elise : son portrait peint recadré sur son visage), à côté le titre de la quête (deux lignes au plus, le seul
     point fort), « PNJ · état », les contrôles de 20 px et le bouton de la liste de lecture ; le blason de difficulté
     (52 px) en haut à droite, son chiffre centré sur la plaque (`BADGE_NUDGE`) ;
   - **dessous, en pleine largeur** : la description de la quête (le seul bloc optionnel : « Afficher le texte de la
     quête », `/fs compact`), les objectifs (liste à puces, coche dorée une fois fait, fine ligne de progression pour
     un compteur), les récompenses (argent et XP au bout de leur ligne, icônes bordées à la couleur de leur qualité) ;
     titres de section petits, en or atténué, sans frise ;
   - **proportions** : 450 px de large, échelle d'espacement 4 / 8 / 12 / 16 ; hauteur **mesurée sur la vraie mise en
     page** une image après l'affichage, jamais moins que ce qu'il faut aux onglets du côté (`SideTabs.MinHeight`) ;
   - **liste de lecture** dans le cadre creusé du jeu (`InsetFrameTemplate`), croix rouge du jeu, barre dorée sur la
     ligne affichée ; **les Compagnons dans leur propre fenêtre** (icône de la barre de titre, à gauche de l'engrenage,
     ou `/fs friends`) ; le côté gauche est vide depuis la roue d'émotes (§9.21) ;
   - **la fenêtre ouverte le reste** (`ForeverSpeechDB.windowShown`) : rouverte à la connexion et après un `/reload` ;
     **la quête cliquée s'affiche** (journal de la carte, titre dans le suivi : sur Forever un clic ne « suit » pas la
     quête) ;
   - tout atlas du jeu passe par `C_Texture.GetAtlasInfo` avec un repli (un atlas absent n'affiche rien) ; sous
     l'interface manette, les boutons de la carte pendent à `UIParent`.
   Essayé puis retiré le 2026-10-21 : un cadre de portrait rectangulaire, des frises dorées, le PNJ dans le portrait
   du coin de la fenêtre. Non vérifié : T55 (récapitulatif).
20. **Quêtes triées par niveau dans le suivi et le journal** (2026-10-21, `ui/quest_sort.lua`, demande du joueur ; réglage
   `sortByLevel`, Options > Confort, activé ; `/fs sort [on|off|asc|desc|probe]`) : la plus basse en haut, ou la plus
   haute (`sortOrder`, Options > Confort « Ordre du tri », clic droit sur le bouton du suivi), niveau inconnu en
   dernier, à niveau égal l'ordre du jeu ; niveau du journal, sinon de l'index (`QuestData.Level`). **Retrié** après
   chaque quête acceptée, rendue ou retirée et chaque mise à jour des objectifs ; **bouton de tri à la main** (icône de
   liste) sur l'en-tête « Tous les objectifs » du suivi (`ObjectiveTrackerFrame.Header`, à gauche de son bouton de
   réduction ; coin haut droit du suivi sinon), qui trie même réglage éteint et réessaie un ordre refusé. Rien de Blizzard
   n'est remplacé. **Suivi** : il suit l'ordre des quêtes suivies (`GetQuestIDForQuestWatchIndex`) ; les quêtes mal
   placées sont retirées puis remises au suivi dans l'ordre (`RemoveQuestWatch` / `AddQuestWatch`, qui ajoute à la fin,
   même type de suivi), jamais en combat (après) ; un ordre que le jeu ne garde pas n'est pas retenté. **Journal** :
   après `QuestLogQuests_Update`, dans chaque zone (entre deux en-têtes), les quêtes (ligne de titre et lignes
   d'objectifs) reprennent les mêmes `layoutIndex` dans l'ordre des niveaux, puis `QuestScrollFrame.Contents:Layout()` ;
   sans cadre de mise en page, rien ne change. Le tri et son sens marchent en jeu (2026-10-21, T58, T59). Essayée
   puis retirée le 2026-10-21 : une ligne dorée peinte sous chaque quête du suivi (pas assez belle) (`/fs sort probe` garde ce que le client a dans
21. **Roue d'émotes** (2026-10-21, `ui/emote_wheel.lua`, demande du joueur : « comme la roue des pings » ; réglage
   `emoteWheel`, Options > Confort, activé) : **maintenir sa touche** (raccourci « Roue d'émotes (maintenir) »,
   `Bindings.xml` `FOREVERSPEECH_EMOTEWHEEL`, `runOnUp` ; la touche se choisit dans Options > Confort, ligne « Touche de
   la roue d'émotes » : clic puis une touche avec ses modificateurs ou un bouton de souris 3 à 5, Échap annule, clic droit
   retire ; `SetBinding` puis `SaveBindings`, jamais en combat ; un bouton de manette : Options > Raccourcis > AddOns, la
   capture d'un bouton de manette demandant `EnableGamePadButton`, protégée) : la roue s'ouvre au curseur (au centre en
   vue souris ou en mode manette du jeu), on vise, **relâcher** lance l'émote (`DoEmote`, la cible sinon tout le monde) ;
   au centre ou après un appui de moins de 0,15 s : rien ; clic gauche : tout de suite ; clic droit : annuler. 8 émotes,
   la première en haut puis dans le sens inverse des aiguilles : Saluer, Remercier, Féliciter, Applaudir, Rire, Danser,
   S'incliner, S'asseoir. **Icônes** (2026-10-21) : des émojis « World of Warcraft » simples et plats, sur fond
   transparent, dans le style de la roue des pings (planche `data/icons/wheel/sheet.jpg`, Gemini 3.1 Flash Image par
   OpenRouter, découpée par `tools/wheel_icons.ts` en `media/wheel/<clé>.tga`) ; noms en blanc à l'extérieur de
   chaque icône, poussés le long du quartier (taille 14, police de la roue du jeu). **Disque sombre, cône doré du quartier visé et bouton central** dessinés par
   `tools/wheel_art.ts` (`media/ui/wheel_*.tga`), Forever n'ayant pas ces images pour 8 quartiers. **Habillée des images de la roue
   des pings** : atlas du client par leur nom (`Radial_Wheel_BG`, `Radial_Wheel_Frame_Count_8`,
   `Radial_Wheel_Select_Wedge_Count_8` pivoté, `Radial_Wheel_Select_Pointer`, `Radial_Wheel_Icon_Close` ; relevés dans le
   code de l'interface Forever, rien de copié), repli sur l'anneau de l'addon, des traits et la croix du jeu ; la roue
   des pings elle-même est interdite aux addons. Manette (mode manette du jeu) : stick droit lu par
   `C_GamePad.GetDeviceMappedState` sans le capter (`EnableGamePadStick` est protégée), la dernière direction visée reste ;
   souris et stick visent tous les deux, le dernier qui a bougé l'emporte (T60, premier essai : la roue s'affichait mais
   rien ne s'éclairait ni ne partait, sans doute le mode manette du jeu, où la v1 n'écoutait que le stick). Rien de
   sécurisé : marche en combat. **Pointeur et surbrillance comme la roue du jeu** (comportement lu dans
   `Blizzard_RadialWheel`) : le pointeur centré sur la roue, à la taille de son atlas, tourné vers la direction visée ;
   le quartier visé éclairé par `Radial_Wheel_Select_Wedge_Count_N` (taille de l'atlas, tourné, 20 px vers l'extérieur),
   sinon le cône doré de l'addon, centré et tourné (sur Forever, ni cadre ni surbrillance à 8 quartiers).
   Vérifié en jeu le 2026-10-21 (T60, à la souris) ; non vérifiés : le pointeur et le disque corrigés, le stick (H33 à H35).
   `ForeverSpeechDB.sortProbe`).
22. **Compatibilité avec FlareUI** (2026-11-05, FlareUI 2.7.0, licence MIT : son code lu pour le nom de ses cadres,
   rien de copié) : son suivi des quêtes remplace celui du jeu (garé hors de vue) par sa propre fenêtre,
   `FlareUI_ObjectiveTracker`, redessinée par `FlareUI.ObjectiveTracker:Render`. Après chaque redessin,
   `ui/tracker_buttons.lua` y remet ce que l'addon met dans le suivi du jeu : le bouton Lecture / Stop au bout du titre
   de chaque quête, le lavis doré des quêtes dont je suis dans la zone (§9.12), la quête cliquée affichée dans la
   fenêtre (§9.19) ; la quête suivie du journal de bord (§9.5) est la première qu'il montre. **Le tri par niveau est le
   sien** (Suivi des quêtes > Trier par « Par niveau », dans ses options) : l'addon ne touche plus à la liste de suivi
   tant qu'il tourne (§9.20 ; le journal de quêtes reste trié par l'addon ; `/fs sort` le dit). Son « Déplacer
   n'importe quel cadre » fait glisser le sac par sa propre poignée : **les onglets sécurisés du sac suivent le sac**,
   qui que ce soit qui le déplace (`ui/side_tabs.lua` compare sa place à chaque image). Son suivi éteint, rien ne
   change. Vérifié en jeu le 2026-11-05 (T63, H38).
   **Les fenêtres de l'addon à l'apparence de FlareUI** (2026-11-05, demande du joueur) : quand FlareUI tourne, la
   fenêtre principale, les options et les Compagnons prennent l'apparence de sa fenêtre d'options
   (`FlareUI.WINDOW_STYLE`). Le cadre du jeu est caché (bordure, barre de titre, fond de pierre). À sa place : le bord
   d'infobulle teinté de son bronze, le fond en tuiles des collections sous un voile noir, un filet bronze sous la barre
   de titre, le titre à gauche, la croix dans le coin. Les cadres creusés (liste de lecture, détail d'un compagnon)
   deviennent un voile noir léger dans un filet bronze, et le séparateur des options passe en bronze (`ui/style.lua` :
   `Style.FlareWindow`, `Style.FlareInset`). Sans FlareUI, les cadres du jeu, comme avant. La page du récit du lieu
   (sur la carte du monde) et la roue d'émotes gardent leur apparence. Vérifié en jeu le 2026-11-05 (T64, H39).
   **La fenêtre accrochée au suivi de FlareUI** (2026-11-05, demande du joueur ; réglage `dockFlare`, Options > Fenêtre
   de quête, activé) : tant que le suivi de FlareUI tourne, la fenêtre se colle contre lui, du côté du centre de l'écran
   (sa propre lecture, `Side`), les hauts alignés, jamais moins haute que lui ; FlareUI place l'ensemble (son mode
   édition) ; la liste de lecture s'ouvre entre la quête et le suivi. **La fenêtre se déplace toujours à la souris**
   (2026-11-05, après un essai en jeu : chacun a sa taille d'écran) : glissée, elle se décolle (`dockFlare` éteint) ;
   **le bouton « remettre en place »** (flèche ronde, à gauche des icônes de la barre de titre, affiché seulement quand
   la fenêtre n'est pas chez elle) la recolle au suivi, ou sans FlareUI la remet à sa place par défaut
   (`PlayerFrame.GoHome`, `playerMoved`). Réglage éteint, ou sans FlareUI : la fenêtre là où le joueur l'a laissée.
   Non vérifié : T66.
   **Le thème FlareUI** (2026-11-05, demande du joueur : les fenêtres, les boutons, les couleurs et la police de
   FlareUI quand il tourne, toujours les éléments du jeu sans lui) : le **contenu peint** reste dans les deux thèmes
   (portrait d'Elise, blasons de difficulté, peintures de zone, icônes de la roue et des onglets) ; le **décor** suit
   FlareUI : son cadre de fenêtre (ci-dessus) ; les polices de son suivi des quêtes (`FlareUI.db.profile.objectivetracker` :
   `headerFont` pour le titre de la fenêtre et des sections, `titleFont` pour le titre de la quête, `objectiveFont` pour le
   reste ; contour et ombre compris, tailles de l'addon gardées ; `Style.FlareFonts`, refait à chaque ouverture) ; son
   bronze (titres de section, filets, anneau du médaillon) ; son bronze frappé (`FlareUI.BronzeIcon.Apply` : l'icône
   blanche, une copie sombre dessous, une claire dessus ; `Paint` ensuite), plus clair au survol ou allumé, sur **ses
   propres icônes** dans la barre de titre (engrenage `DMSettings`, compagnons `ChatSocial`, de son dossier `Media/Icons`)
   et sur **nos pictogrammes en blanc** (`media/ui/glyph_<nom>_white.tga`, `tools/white_glyphs.ts` ; dorés et grisés,
   le bronze ne prenait pas : premier essai du 2026-11-05) pour les boutons ronds (sans leur anneau), ceux du suivi
   (sans leur case) et le bouton « remettre en place » ; **la croix en bouton carré de FlareUI** (celui de son suivi :
   contour bronze d'un pixel aux coins coupés, fond sombre). **Le bandeau du bas (niveau et or) est retiré** le
   2026-11-05 (demande du joueur), dans tous les thèmes. Les boutons de la carte du monde et la page du récit du lieu gardent leur anneau. Non vérifié :
   T67 (H41).
   **Le cadre et l'en-tête du suivi** (2026-11-05, réglés sur deux captures en jeu) : à côté du suivi, la fenêtre prend
   son fond (« Blizzard Dialog Background Dark » de LibSharedMedia, à l'opacité du suivi) et sa bordure (« FlareUI
   Frames » sauf autre choix du joueur, dans son bronze), son bandeau d'en-tête de 30 pixels (titre à 14 pixels du bord,
   police et or de « Quêtes », séparateur du jeu dessous), des icônes de 13 pixels sur la ligne du titre à 6 pixels
   d'écart (l'engrenage de FlareUI, haut dans son image, descendu d'un pixel) et une croix sur la géométrie de son « − »
   (pixels entiers, coins en marche, traits de 2 pixels). Le bouton de lecture du suivi est 3 pixels plus à gauche et
   reste en bronze (sa couleur d'état ne le recouvre plus).
23. **L'avancement du groupe sous les objectifs** (2026-11-05, demande du joueur) : en groupe, sous les objectifs de la
   fenêtre, « Le groupe » : chaque membre qui a la quête puis ses objectifs, faits cochés en gris, avec les lignes et les
   couleurs du jeu (`C_TooltipInfo.GetQuestPartyProgress`, celles de l'infobulle de quête de Retail, que FlareUI lit
   aussi ; un membre se reconnaît au type de sa ligne, `Enum.TooltipDataLineType.QuestPlayer`). Rien à installer
   chez les autres : c'est le serveur qui donne ces lignes. Relu à `UNIT_QUEST_LOG_CHANGED`, `GROUP_ROSTER_UPDATE` et chaque
   seconde, redessiné seulement s'il change (`QuestData.PartyProgress`, `ui/player_frame.lua`). Non vérifié : T66 (H40).

24. **L'interface s'efface pendant les déplacements** (2026-11-05, demande du joueur : profiter du monde en marchant ;
   `ui/fade.lua` ; réglage `fadeOnMove`, Options > Confort, activé ; `/fs fade on|off`) : le personnage en mouvement
   (`IsPlayerMoving`), griffon compris (`UnitOnTaxi`, demandé le même jour), toute l'interface (`UIParent`) descend de là où elle est à 20 % en 3 secondes, **sauf la mini-carte**, toujours affichée
   pour guider (10 % partout au premier essai ; la mini-carte à 40 % ensuite la faisait sauter : réglé le même jour) ; arrêté, elle
   remonte à 100 % en une demi-seconde depuis là où elle était. L'élément sous la souris (l'enfant d'`UIParent` qui tient
   le focus de la souris) et l'infobulle restent à 100 % (`SetIgnoreParentAlpha`, leur réglage rendu ensuite). Jamais
   quand l'interface sert : en combat (revenue d'un coup), carte du monde ou fenêtre du jeu ouverte (`GetUIPanel`),
   dialogue, menu du jeu, butin, chat en cours de saisie, objet sur le curseur, mode édition, options de l'addon. Une
   erreur remet l'interface et arrête l'effet. La barre d'action et le reste suivent `UIParent` ; un élément qui
   ignore déjà l'opacité de son parent (certains de FlareUI) ne s'efface pas. Non vérifié : T68 (H42).

**Fin de phase 1** : sur Forever beta, accepter une quête lance un son de test et ouvre le lecteur ; le replay fonctionne depuis le suivi et depuis le journal ; Stop fonctionne ; les captures sont présentes dans le fichier SavedVariables après `/reload`.

## 10. Spikes — Phase 0 (à traiter en premier, un fichier par spike dans `docs/spikes/`)

| # | Question | Impact si échec |
|---|---|---|
| S1 | `PlaySoundFile` lit-il un .ogg du dossier de l'addon sur Forever ? Valeurs de retour (`willPlay`, `handle`) ? | Projet bloqué |
| S2 | Un .ogg **ajouté** pendant la session est-il lisible sans redémarrage ? Un .ogg **existant écrasé** est-il relu avec le nouveau contenu ? | Définit le mode du compagnon : prochain lancement, ou `/reload` avec des fichiers « slots » pré-créés |
| S3 | Les SavedVariables persistent-elles et se rechargent-elles (bug beta signalé) ? | Plus de canal de capture → alternative à trouver |
| S4 | Noms et points d'accroche : fenêtre de détail de quête, bouton Accepter, suivi d'objectifs (modernisé sur Forever), journal de quêtes | Choix des hooks |
| S5 | `SOUNDKIT_FINISHED` existe-t-il et se déclenche-t-il pour `PlaySoundFile` ? `C_VoiceChat.SpeakText` est-il disponible ? | Minuterie ; pas de fallback TTS |
| S6 | Couverture Wowhead Forever FR : sur un échantillon de 50 quêtes d'une zone, part avec description FR et PNJ donneur identifié | Poids du pré-chargement face à la capture |
| S7 | Faisabilité du crawl : robots.txt, protection anti-bot, structure des pages `wowhead.com/forever/fr/quest=<id>` et `/forever/fr/npc=<id>` (données structurées embarquées dans la page ? endpoint de tooltip ?) | Conception du crawler |
| S8 | Modèle du PNJ hors interaction : `SetCreature` / `SetDisplayInfo` fonctionnent-ils sur Forever ? | Icône seule |
| S9 | Fin de quête : `QUEST_COMPLETE`, `GetRewardText`, `GetQuestReward` existent-ils sur Forever ? (2026-10-06) | Pas de lecture au rendu |
| S11 | Dialogues des PNJ : à l'ouverture de la fenêtre de discussion (`GOSSIP_SHOW`), le texte est-il lisible (`C_GossipInfo.GetText`, sinon `GetGossipText`) ? Est-ce celui de la base (VMaNGOS) ? (2026-10-10 ; seulement la conversation affichée, lue en direct, pas les paroles déjà sonores du jeu) | Pas de lecture des dialogues ; texte de la base seulement |
| S13 | Les fichiers du client Forever (CASC, caches WDB et ADB) donnent-ils les techniques de classe, le jeu de voix et le sexe des PNJ ? (2026-10-12 : tables chiffrées en beta, caches vides avant de jouer ; à reprendre après la sortie, rien de chiffré n'est lu) | Rester sur la Forever Database et Wowhead |

S6 et S7 sont faisables sans le jeu ; les autres nécessitent mes tests en jeu.

## 10 bis. État d'avancement (au 2026-10-05)

- **Phase 0 terminée** : S1 à S8 validés. Résultats et décisions dans `docs/spikes/`.
- **Phase 1 terminée** : T1, T2 et T3 validés en jeu. Résultats dans `docs/ingame-tests.md`.
- **Faits vérifiés sur Forever 1.60.1.70205**, à utiliser sans re-vérifier :
  - interface `16001` ;
  - UI de quêtes de style Retail 11.x :
    - `QuestFrameAcceptButton` ;
    - `QuestObjectiveTracker`, avec ses hooks `AddBlock` et `GetBlock` ; `block.id` = questID ;
    - `QuestMapFrame` > `QuestScrollFrame.Contents`, où les lignes de titre et d'objectif portent `questID` ;
    - `QuestMapFrame.DetailsFrame` ;
    - `QuestLogQuests_Update` et `QuestMapFrame_ShowQuestDetails` ;
  - `C_QuestLog.*` ; `GetQuestLogQuestText(logIndex)` ; récompenses `GetQuestLogReward*` et `GetQuestLogChoice*` ;
  - `PlaySoundFile` : il renvoie `true, handle`, ou rien si le fichier manque ;
  - fin de son par `C_Sound.IsPlaying` : `SOUNDKIT_FINISHED` ne se déclenche pas ;
  - `StopSound` ;
  - TTS `C_VoiceChat.SpeakText(voiceID, text, rate, volume, overlap)`, avec voix fr-FR (Thomas) ;
  - un nouveau .ogg est lisible après `/reload` ; un .ogg écrasé ne l'est qu'après redémarrage (S2) ;
  - SavedVariables persistantes (S3) ;
  - modèle 3D : `SetDisplayInfo` marche pour tout PNJ, `SetCreature` seulement en cache (S8) ;
  - `AddonCompartmentFrame:RegisterAddon` ; la documentation d'API complète est dumpable via `/fs api`.
- **Addon livré** :
  - lecteur avec liste de lecture (ordre fixe, Avancer, Stop, Vider, pause entre quêtes) ;
  - TTS en repli par défaut ;
  - capture à `QUEST_DETAIL`, récompenses incluses ;
  - fenêtre principale : quête, liste de lecture, barre de debug ; fenêtre d'options à part (2026-10-15) ;
  - lecture automatique à l'acceptation et au rendu, boutons ▶ dans le suivi et le journal ;
  - son de page, bouton de minimap et menu des addons ;
  - journal de diagnostic `ForeverSpeechDB.trace`.
- **Pipeline livré** :
  - client Wowhead poli avec cache ;
  - parsers de quêtes et de PNJ ;
  - `build_index.py` (contrat v1) ;
  - spike S6 ;
  - **phase 2, zone par zone** (`tools/zone.sh`, doc : `docs/data-registries.md`) : catalogue des
    123 catégories de quêtes Wowhead (`data/zones.json`) ; **Forêt d'Elwynn récupérée** (76 quêtes, dont 65
    complètes ; 32 PNJ donneurs, dont 25 avec une voix d'archétype et 6 nouveaux dans Forever, voix inconnue) ;
  - contrat d'index v2 (donneur et displayID → modèle 3D de tout PNJ ; test en jeu T4 à faire) ;
  - **fiches de personnalité** des 32 donneurs d'Elwynn (`tools/zone.sh personas`, Claude Code en mode
    non interactif, schéma JSON fixe, consigne versionnée) et règles pour le texte : `docs/voices-and-text.md` ;
  - **scripts de jeu** des quêtes (`tools/zone.sh scripts`, `scripts.json` par zone : texte dépersonnalisé ;
    sans Claude ni direction d'acteur depuis le 2026-10-07) ;
  - **voix et lectures en local avec Qwen3-TTS** (D11, 2026-10-07 ; ElevenLabs, Chatterbox, Fish et Higgs essayés
    puis abandonnés) : **Forêt d'Elwynn complète** (41 voix modèles, 129/129 lectures), quêtes de guerrier 84/92 ;
  - référence des voix PNJ : `docs/reference/npc-voices.md`.
- **Questions ouvertes** :
  - **Q-VOIX-1**, remplacer ou prolonger les voix du jeu : voir `docs/reference/npc-voices.md` ;
  - le sens du suffixe `:c` dans les variables Wowhead (`<un/une:c>`), voir S6.

## 11. Phase 2 — Données (aperçu, après la phase 1)

- **Les boucles** (2026-10-06, voix et lectures le 2026-10-07, D11) : **base** (construire la Forever Database et
  importer les registres, `tools/base/run.sh`), **texte** (fiches et scripts, `tools/text/run.sh`), **voix**
  (`tools/voices/run.sh`), **lectures** (`tools/readings/run.sh`). Voir `README.md` et `tools/loop/README.md`. État : `tools/report.sh --all | --group G [--category C]`.
- **Découpage** : catégorie par catégorie, selon les catégories de quêtes de Wowhead dans leur groupe (D12 ; le Comté
  du Nord fait partie de la Forêt d'Elwynn). Une quête absente de ces listes suit la zone parente de la base. Décidé le 2026-10-05 : **Alliance seulement** (quêtes Alliance ou des
  deux factions), **jamais de filtre de niveau** sur les quêtes, **zones triées par niveau** (`tools/zone.sh order`),
  rien de déjà généré n'est refait sans décision humaine.
- **Wowhead** : plus crawlé (D10), crawler retiré le 2026-11-01 (§3). Le cache des pages téléchargées jusqu'au
  2026-10-12 reste lu (`pipeline/wowhead/cache.py`) ; les textes manquants viendront des captures en jeu.
- **Quêtes** : id, nom, description, objectifs, progression, achèvement, donneurs et finisseurs, zone, niveau, faction, état Forever, avec l'état `complete` / `incomplete` / `unavailable` / `capture_only` et la liste `missing`. Français uniquement (D5).
- **PNJ donneurs** : id, nom, titre, type, classification, réaction A/H, zones, coordonnées, displayID, quêtes données et rendues, et **jeu de voix du jeu** (race, sexe, personnalité, archétype ou voix unique), lu sur la fiche Wowhead Classic FR. Les PNJ nouveaux dans Forever n'ont pas de fiche Classic : voix `unknown`, le sexe viendra de la capture.
  Depuis D10, les PNJ venus de la base n'ont pas de voix du jeu : la fiche de personnalité (consigne v3) estime
  leur race, qui choisit l'archétype de voix.
- **Chaîne de fallback du texte** : capture en jeu > Wowhead FR (déjà en cache) > Forever Database > aucun audio
  (TTS du client en jeu). L'étape « Wowhead EN + traduction LLM » est abandonnée (2026-10-05) ; la source `wowhead_en_tr` du contrat d'index ne sera plus produite.
- **Registre des voix** (`data/voices.json`) : une fiche de personnalité par PNJ donneur, générée par Claude à partir de ses quêtes et de sa voix dans le jeu, puis une voix par PNJ : la voix modèle Qwen3 (clé `qwen`, D11). Voir `docs/voices-and-text.md`.
  - Le jeu structure déjà ses voix en **58 archétypes** (race × sexe × personnalité) et une quarantaine de voix uniques du lore. Le jeu de voix d'un PNJ se lit sur sa fiche Wowhead Classic FR et donne sa race et son sexe. Référence : [docs/reference/npc-voices.md](docs/reference/npc-voices.md).
  - **Q-VOIX-1, option A retenue** (une voix propre par PNJ, 2026-10-05) ; les salutations du jeu sont coupées depuis le 2026-10-10 (§9.9), sans salutations de remplacement pour l'instant. Question d'origine : remplacer les voix du jeu, ce qui implique de couper les sons d'origine, ou les prolonger avec des voix proches des archétypes ? Voir la référence ci-dessus.
- **Contribution à Wowhead** : Wowhead Client sur Windows uniquement → hors périmètre sur Mac.

## 12. Phase 3 — Génération audio (je m'en charge ; Claude Code fournit les entrées et sorties)

Réalisée depuis le 2026-10-07 par les boucles voix et lectures (D11, `docs/pipeline.md`). Reste à faire : le lexique
phonétique des noms propres du lore (« Stormwind » sur une phrase courte fait monter la détection d'anglais).

- Entrées : texte normalisé (D8), lexique phonétique des noms propres du lore (Kalimdor, Thrall…), ID de voix.
- Sorties : .ogg + mise à jour de `index.lua` (contrat §8).
- Mode A, lot complet : tout est généré à partir de Wowhead et des captures.
- Mode B, incrémental : le compagnon génère depuis les captures ; disponible selon le résultat de S2.
