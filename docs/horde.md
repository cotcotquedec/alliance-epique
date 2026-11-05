# Section Horde et Benjamin — plan (2026-10-22)

Statut : **plan, rien n'est codé.** Décision proposée : D20 (à reporter dans `CLAUDE.md` une fois validée). Un premier
essai de l'étape 1 (la faction comme paramètre du pipeline et des boucles, jamais commité) a été jeté le 2026-11-03.

## Objectif

Un personnage de la Horde a la même expérience qu'un personnage de l'Alliance : ses quêtes, ses dialogues et ses
livres lus par les voix des PNJ, et **Benjamin** comme compagnon et narrateur, en miroir d'Elise (D9, D16, D17, D18,
D19). **La voix de Benjamin est ElevenLabs**, comme celle d'Elise (décidé le 2026-10-22).

## Volumes mesurés (registres et base du 2026-10-22)

| Poste | Horde seule | Moteur |
|---|---|---|
| Quêtes | 1 547, aucune avec audio | — |
| Textes de quête (débuts + fins) | 1 233 + 1 360 = 2 593, ≈ 1,03 M caractères, 141 avec `$G` | Qwen (PC) |
| PNJ qui parlent sans voix | ≈ 527 (fiche Claude + voix modèle) | Claude, Qwen |
| Dialogues (PNJ amicaux envers la Horde seulement) | 435 PNJ, 2 254 pages, ≈ 470 k caractères | Qwen |
| Quêtes des deux factions encore sans audio | ≈ 550 (sans doute en zone Horde, à vérifier) | Qwen |
| Livres côté Horde | 82 livres, 201 pages, ≈ 80 k caractères | ElevenLabs |
| Benjamin : présentations des 48 zones | ≈ 27 k caractères | ElevenLabs |
| Benjamin : 59 répliques de niveau | ≈ 7,5 k | ElevenLabs |
| Benjamin : 60 répliques de palier | ≈ 6,4 k | ElevenLabs |
| Benjamin : textes de quête Horde sans orateur | 177 textes, ≈ 65 k | ElevenLabs |

**Crédits ElevenLabs de Benjamin** (avec ≈ 40 % de refus, comme pour Elise) :

| Périmètre | Caractères | Crédits | Mois de forfait Creator (≈ 100 k/mois) |
|---|---|---|---|
| Minimal (zones, niveaux, paliers, quêtes Horde sans orateur) | ≈ 105 k | ≈ 150 k | 1,5 |
| + livres de la Horde | ≈ 185 k | ≈ 260 k | 2,6 |
| + textes communs qu'Elise lit déjà (≈ 296 quêtes, 641 pages de livres) | ≈ 600 k | ≈ 840 k | 8,4 |

Ces crédits s'ajoutaient à ceux des livres d'Elise ; **les livres sont finis depuis le 2026-11-02** (forfait
Pro) : B1 ne bloque plus rien.

## Décisions à prendre avant de commencer

- **B1. Ordre des crédits.** Recommandation : Benjamin minimal **avant** la suite des livres d'Elise (un mois et demi de
  forfait, puis les livres reprennent). Sinon, Benjamin attend environ mars 2027.
- **B2. Textes communs aux deux factions** (quête sans orateur, livre neutre) : lus par Elise pour tout le monde, ou par
  le narrateur de la faction du joueur ? Recommandation : **Elise pour tous dans un premier temps** (×5 de crédits
  sinon) ; Benjamin les reprend plus tard, texte par texte, si l'on veut.
- **B3. Qui est Benjamin.** Race, âge, caractère et voix (à écrire comme `PERSONA` d'Elise), son fil narratif à lui
  (l'équivalent de la sentinelle du Mur du scarabée), son portrait. À proposer par Claude, choisi par le joueur. Piste :
  un réprouvé ou un tauren, contraste avec l'elfe timide d'Elise.
- **B4. Faction de l'addon.** Un seul addon qui choisit selon le personnage (recommandé), pas deux paquets.

## Étapes

Chaque étape = un petit incrément testable, une session et une PR (`session/<date>-<sujet>`).

### 1. Faction comme paramètre du pipeline (sans rien générer)

- `pipeline/narrator.py` : deux narrateurs, `ELISE_ID = 1000000` (Alliance) et `BENJAMIN_ID = 1000001` (Horde), une
  table par faction ; `is_narrator` reconnaît les deux ; `NARRATOR_ID` garde son sens pour la compatibilité.
- Le filtre « Alliance » en dur devient `--side alliance|horde|all` : `foreverdb/importer.py`,
  `foreverdb/dialogues.py` (`react` « A » ou « H »), `books/extract.py`, `quests/registry.py`, `npcs/registry.py`,
  `scripts.py` (orateur des textes sans PNJ selon la faction de la quête), `zones/report.py`, `build_index.py`,
  `tools/all_zones.sh`, `tools/package_addon.ts`.
- Tests pytest : une quête Horde sans orateur → Benjamin ; une quête « both » sans orateur → Elise (B2) ; périmètre
  `--side` des rapports.
- **Rien n'est régénéré côté Alliance** : vérification avec `tools/report.sh --all` avant et après (mêmes chiffres).

### 2. Oracles et boucles par faction (fichiers scellés)

- Les oracles et cadres de `tools/voices/`, `tools/readings/`, `tools/dialogues/` filtrent l'Alliance : il faut les
  paramétrer, et `tools/elise/` lit `NARRATOR_ID` en dur. **Fichiers scellés** : modification décidée par le joueur,
  boucles arrêtées, puis `tools/loop/seal.sh`. Proposition : une boucle « narrateur » unique, `--narrator elise|benjamin`,
  plutôt qu'une copie de `tools/elise/` (budget de crédits partagé, jamais deux en même temps, comme la boucle livres).
- Faire cette étape **quand aucune boucle ne tourne** (ni sur le PC, ni la boucle livres du Mac).

### 3. Benjamin : fiche, voix et portrait

- Fiche (`PERSONA`) et voix ElevenLabs conçue depuis la description, choisie à l'oreille parmi quelques essais
  (`tools/elise/voice.py` généralisé ; une création de voix sur le quota mensuel).
- Portrait peint (Gemini par OpenRouter, comme `tools/elise_portrait.sh`), `media/benjamin.tga` 256×256, original dans
  `data/icons/benjamin/`.

### 4. Textes de Benjamin (Claude, Opus)

- **Zones** : consigne `pipeline/zone_intros/prompt_horde_v1.md`, miroir de `prompt_v2.md` : point de vue de la Horde,
  une terre de l'Alliance racontée par son lore et son danger. Sortie à côté de celle d'Elise (`scripts.json`,
  section `zones_horde` ou un dossier `@intros-horde`, à trancher à l'implémentation).
- **Niveaux** : `pipeline/level_lines/prompt_horde_v1.md`, une seule histoire du niveau 2 au niveau 60, son fil propre
  (B3), même crescendo mesuré, vision finale identique (Ragnaros… Naxxramas), `data/zones/@benjamin/levels/`.
- **Paliers des compagnons** : 60 répliques écrites à la main, comme celles d'Elise, `data/zones/@benjamin/companions/`.
- Relecture humaine avant tout audio.

### 5. Données Horde (Qwen, PC)

- Fiches de personnalité des ≈ 527 PNJ (boucle texte), puis voix modèles (boucle voix), lectures (boucle lectures),
  dialogues (boucle dialogues), avec `--side horde` et l'ordre des zones par niveau (Durotar, Mulgore, Tirisfal
  d'abord).
- Ordre de grandeur : le même que tout le travail de l'Alliance. Commencer par une zone de départ (Durotar), écouter,
  puis élargir.

### 6. Audio de Benjamin (ElevenLabs, Mac)

- Boucle narrateur `--narrator benjamin`, `--budget N` : zones, niveaux, paliers, puis quêtes Horde sans orateur, puis
  livres de la Horde (si B1 le permet). Audio `audio/1000001/…`, cycle D15.

### 7. Addon : narrateur selon la faction (index v10)

- `UnitFactionGroup("player")` choisit le narrateur : présentations de zone, répliques de niveau et de palier, portrait,
  nom. Un personnage neutre (pandaren non concerné en Classic) : Elise par défaut.
- Index v10 : `zones[mapID].intro` et `introHorde` (ou `intros = { Alliance = …, Horde = … }`), même chose pour
  `levels` et `companions.lines` ; `npcs[1000001] = { name = "Benjamin" }`. L'addon accepte encore un index v9.
- Tests busted : choix du narrateur et du fichier selon la faction ; repli sur Elise si Benjamin n'a pas d'audio.
- Options : rien à ajouter (le narrateur suit le personnage).

## Vérifications en jeu (file `docs/ingame/queue.md`)

- `UnitFactionGroup("player")` sur Forever : valeurs « Alliance » / « Horde », dès la connexion (non vérifié).
- Personnage Horde : quête acceptée et rendue (voix du PNJ), dialogue, présentation de Durotar (Benjamin, après
  2 min), passage de niveau, portrait de Benjamin dans la fenêtre.
- Personnage Alliance : rien ne change (non-régression).

## Hors périmètre pour l'instant

- Benjamin qui relit les textes communs (B2).
- Captures des quêtes propres à Forever côté Horde : elles arrivent d'elles-mêmes en jouant un personnage Horde.
