# Constitution de la boucle texte

**Lecture seule pour la boucle.** Ce texte peut être écrit avec une IA, mais c'est un humain qui le valide, puis
le scelle (`tools/loop/seal.sh text`). La boucle refuse de tourner si lui, l'oracle, l'arbitre ou le cliquet ont
changé depuis le sceau.

## But

Chaque zone qui a des quêtes de l'Alliance ou des deux factions a son texte, dans l'ordre des niveaux :

- chaque PNJ qui parle dans ces quêtes a sa fiche de personnalité : le donneur, et le PNJ de rendu quand la quête a un
  texte de fin ;
- chaque texte qui peut être dit a son script : le début de quête (description et objectifs, dit par le donneur) et
  la fin de quête (texte de rendu, dit par le PNJ de rendu ; 2026-10-06). La progression n'est jamais dite.

Les registres de zones viennent de la boucle base (Forever Database, D10) : cette boucle ne crawle rien.

L'oracle (`tools/text/oracle.py`) dit oui quand plus aucune zone n'a de texte à faire (`next_text` à `null` dans
`tools/zone.sh progress --side alliance --json`).

## Interdits

- **Jamais de régénération** : une fiche ou un script existant est gardé ; pas de `--force`.
- **Jamais de perte** : le niveau (zones avec texte, scripts, fiches, quêtes récupérées) ne baisse jamais.
- **Pas de crawl** : ni Wowhead ni aucun site ; les données viennent des registres (boucle base). Aucun
  contournement de protection, jamais.
- **Pas d'audio** : ce sont les boucles voix et lectures.
- **Écriture limitée** à `data/voices.json` (fiches), `data/zones/**/scripts.json` et au dossier de la boucle
  `data/cache/loops/text/`. Les registres de quêtes et de PNJ appartiennent à la boucle base.
- Les quêtes réservées à la Horde sont laissées de côté ; **aucun filtre de niveau**.

## Schéma cible

- `data/zones/<groupe>/<zone>/quests.json` et `npcs.json` : registres de la zone (`docs/data-registries.md`).
- `data/voices.json` : `npcs.<id>.persona`, la fiche de chaque donneur (`docs/voices-and-text.md`).
- `data/zones/<groupe>/<zone>/scripts.json` : `scripts.<questID>` (début) et `complete.<questID>` (fin), avec
  `text` (le texte dépersonnalisé, `pipeline/narration.py`), `gendered` et `generator`. Depuis le 2026-10-07, un
  script n'a plus de mise en scène et ne passe plus par Claude (`pipeline/scripts.py`) : seules les fiches
  l'utilisent. Les scripts écrits avant gardent leurs champs `segments`, `overall`, `render`… inutilisés.

## Hors du but

Ces cas ne sont pas des échecs : le critique les note dans le backlog, la boucle continue.

- Quêtes sans texte français : elles viendront d'une capture en jeu (D5).
- Quêtes sans PNJ donneur ou sans PNJ de rendu : voix du narrateur, plus tard (D9).
- Quêtes sans texte de fin : elles n'ont simplement pas de fin à dire.
