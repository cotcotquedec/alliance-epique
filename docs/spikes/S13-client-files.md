# S13 — Les fichiers du client Forever comme source de données

**Question.** Les données dont on a besoin (techniques de classe, voix et sexe des PNJ, zones) sont-elles lisibles
dans les fichiers du jeu installé, sans passer par la Forever Database ni Wowhead ?

**Impact.** L'idée I2 (techniques des maîtres de classe, `docs/ideas.md`) n'attendrait plus la Forever Database ; le
jeu de voix et le sexe de **tous** les PNJ, Forever compris, viendraient du client.

## Ce qui a été vu (2026-10-12, PC, sans lancer de jeu côté agent)

- **Installation** : `D:\Games\World of Warcraft` (WSL : `/mnt/d/Games/World of Warcraft`), produit
  `wow_classic_beta`, build **1.60.1.70338** après la mise à jour du 2026-10-12 (70291 avant), client **frFR**
  (`_classic_beta_/WTF/Config.wtf` : `textLocale` et `audioLocale` à `frFR`).
- **Stockage CASC** : le lecteur de la Forever Database (`.data/forever-db/etl/casc.py`, lecture seule) l'ouvre en
  5 s, 1 248 803 fichiers à la racine. Les tables (`.db2`) ne se trouvent pas par leur nom : il faut leur numéro de
  fichier (FileDataID), connu par la liste communautaire (wowdev/wow-listfile, **pas téléchargée**), ou en dur dans
  le code (comme `etl/maps.py`).
- **`SpellName.db2`** (FileDataID 1990283) : **chiffré** (`encrypted BLTE chunk`). Le lire demanderait les clés de
  Blizzard ; les extraire du client ou prendre des clés publiées par d'autres serait contourner une protection
  (CLAUDE.md §3) : **arrêt**. Probablement du contenu de beta, peut-être en clair à la sortie.
- **Caches du client**, écrits en clair au lancement, dans `_classic_beta_/Cache/` :
  - `ADB/frFR/DBCache.bin` (3 Mo) : les correctifs des tables envoyés par le serveur (ce que Forever change) ;
  - `WDB/frFR/questcache.wdb`, `creaturecache.wdb`, `npccache.wdb` (textes des fenêtres de discussion),
    `pagetextcache.wdb`, `gameobjectcache.wdb` : **vides** (32 octets) tant qu'on n'a pas joué ; le client les
    remplit avec ce que le serveur envoie. Une source de captures sans addon, en français et au texte exact de
    Forever (S11 pour les dialogues).
- Le décodeur de tables de la Forever Database (`etl/db2.py`) ne lit que les champs numériques, pas les chaînes.

## Ce que les fichiers du client ne donnent pas

Ce qui vient du serveur : textes de quête (sauf le cache WDB), liste des PNJ et de ce qu'ils vendent, prix chez le
maître de classe, dialogues (sauf le cache WDB). D1 ne change pas.

## À reprendre après la sortie (4/11/2026)

1. Réessayer `SpellName.db2` et les tables utiles (`Spell`, `SpellDescription`, `SkillLineAbility`, `SpellLevels`,
   `CreatureDisplayInfo`, `CreatureDisplayInfoExtra`, `NPCSounds`, `AreaTable`) : en clair, l'idée I2 se débloque.
   Il faudra leurs FileDataID (liste communautaire : demander avant de la télécharger) et un décodeur des chaînes.
2. Après quelques heures de jeu sur le PC : lire les caches WDB (format à écrire) et `DBCache.bin`.

## Décision

En attente de la sortie (décidé le 2026-10-12). Rien de chiffré n'est lu.
