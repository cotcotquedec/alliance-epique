# À faire, dans l'ordre

Le plan de travail décidé avec l'utilisateur. Une ligne faite est retirée (sa trace reste dans git et CLAUDE.md).
Mis à jour le 2026-11-03, veille de la sortie de Forever.

## Fait depuis le 2026-10-12

Repasse globale finie (2026-10-13) ; répliques d'Elise pour les compagnons (70/70) ; **les 945 pages de livres lues par
Elise** (2026-11-02, D19) ; prises ElevenLabs gardées sans Whisper (PR #31) ; crawler Wowhead retiré (PR #30) ;
vérification du jeu à chaque build du client (`core/check.lua`, 2026-11-03).

## Ensuite

| # | Quoi | Détail |
|---|---|---|
| 1 | **Jour de sortie : T61** | Redémarrage complet, puis le tour de `docs/ingame-tests.md#t61` ; lire `ForeverSpeechDB.check` dans les sauvegardes et traiter chaque nom manquant (repli de l'addon, ou correction). |
| 2 | Mise à jour de la Forever Database après la sortie | `tools/db_check.sh`, puis `tools/prepare_db.sh --update` et `tools/zone.sh sync --dry-run` à la première release qui suit ; QuestieDB a déjà, depuis notre v0.1.6, 312 quêtes et 334 noms de PNJ français propres à Forever (titres et objectifs, jamais de description). |
| 3 | **L'oracle des voix suit les décisions humaines** | `HONOURED` de `pipeline/review.py` sans `voice` ; modifier `tools/voices/oracle.py`, puis l'utilisateur rescelle voix, lectures et dialogues. |
| 4 | Comptage des lectures « en attente d'une voix » | L'oracle des lectures compte les quêtes d'Elise (voix ElevenLabs, pas Qwen). Fichier scellé. |
| 5 | Écoute des refus restants | Page de contrôle, vue « Refusées » : 205 lectures et 552 dialogues que le juge refuse encore (joués en jeu quand même, D15). |
| 6 | Section Horde et Benjamin | Plan du 2026-10-22 (`docs/horde.md`) ; rien de codé (un premier essai, jamais commité, a été jeté le 2026-11-03). Décisions B1 à B4 d'abord. |

## En attente d'un événement

| Quoi | Quand |
|---|---|
| Fichiers du client comme source (spike S13 : tables chiffrées en beta, caches WDB) | Après la sortie (4/11/2026) |
| Techniques des maîtres de classe (idée I2, `docs/ideas.md`) | Quand la Forever Database couvrira les techniques de Forever, ou après S13 |
| Vérifications en jeu ouvertes (`docs/ingame/queue.md`) | Agent du Mac ; la vérification du jeu répond d'abord à la part « ce nom existe-t-il ? » |
| Sceau de la boucle base cassé depuis le 2026-10-07 | À revoir à la prochaine mise à jour de la base |
| Textes des quêtes sans description française (1 445 dans les registres) | Captures en jeu (Wowhead est fermé aux robots, QuestieDB n'a pas les descriptions) |
