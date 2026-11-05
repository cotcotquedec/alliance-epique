# Constitution de la boucle base

**Lecture seule pour la boucle.** Ce texte peut être écrit avec une IA, mais c'est un humain qui le valide, puis
le scelle (`tools/loop/seal.sh base`). La boucle refuse de tourner si lui, l'oracle, l'arbitre ou le cliquet ont
changé depuis le sceau.

## But

Les registres de toutes les zones (`data/zones/<groupe>/<zone>/{quests,npcs}.json`) sont importés depuis la
version actuelle de la **Forever Database** (D10), construite en local dans `.data/` par `tools/prepare_db.sh`.

L'oracle (`tools/base/oracle.py`) dit oui quand chaque zone du catalogue a été importée depuis cette version.

## Interdits

- **Jamais de perte** : quêtes, descriptions et textes de fin ne baissent jamais. Un texte déjà présent (capture
  en jeu, Wowhead) n'est jamais remplacé par celui de la base : priorité capture > Wowhead > base.
- **Pas de crawl** de Wowhead ni d'aucun site ; seules sources réseau : les dépôts GitHub de la base (QuestieDB,
  VMaNGOS, AzerothCore) et lua.org. Aucun contournement de protection.
- **Pas d'appel payant** : pas de Claude.
- **Écriture limitée** à `.data/` (base et Lua 5.1, non versionnés), aux registres `data/zones.json`,
  `data/zones/**/{quests,npcs}.json`, et au dossier de la boucle `data/cache/loops/base/`.
- Les données de la base restent locales (GPL, usage personnel) : jamais commitées ni redistribuées.

## Schéma cible

Le format des registres ne change pas (`docs/data-registries.md`) ; chaque registre porte en plus
`source.foreverdb` (la version de la base) et chaque quête `source.texts` (d'où vient chacun de ses textes).

## Hors du but

Les quêtes sans texte français dans la base (surtout les quêtes nouvelles de Forever) : le critique les liste,
la capture en jeu les complétera.
