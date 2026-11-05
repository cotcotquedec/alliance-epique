# Vérifications en jeu : l'échange entre les deux agents (2026-10-10)

Deux sessions Claude Code travaillent sur ce projet, une par machine (voir aussi [docs/machines.md](../machines.md)) :

| | Agent du **PC** (WSL2, RTX 4090) | Agent du **Mac** |
|---|---|---|
| Rôle | génération des voix et des lectures (boucles voix, lectures, Elise), données, pipeline, page de contrôle (banc d'écoute) | **le jeu** : il fait vérifier en jeu par l'utilisateur, lit les SavedVariables, teste l'addon |
| Ne fait pas | rien en jeu : ses hypothèses sur le client restent des hypothèses | ne lance pas les boucles de génération (une seule machine produit, `data/voices.json`) |

Le PC ne peut pas lancer le jeu ; le Mac a le jeu. Tout ce qui dépend du client Forever (API, événements, ce que le
joueur voit ou entend) passe donc par **la file** : [queue.md](queue.md).

## Le canal : git

- Le code et la file passent par GitHub, en pull requests (une branche par session, `main` protégée).
- Les données (audio, `data/`, captures) passent par le disque externe : pas dans git.
- Les captures contiennent le nom du joueur : ne jamais les commiter telles quelles. Un résultat cite l'extrait utile
  (le texte d'un dialogue, une valeur de `/dump`), sans le nom du personnage.

## Le cycle d'une vérification

1. **L'agent du PC ouvre une demande** : une ligne dans `queue.md` (statut `ouverte`), avec l'hypothèse à
   vérifier, ce qu'elle débloque, et un lien vers la procédure : une fiche de spike (`docs/spikes/Sxx-….md`) ou une
   section de test (`docs/ingame-tests.md`, `Txx`). La procédure dit les commandes, le résultat attendu, et ce que
   l'agent du Mac doit relever. Le code nécessaire (capture, commande de diagnostic) est livré sur la même branche.
2. **L'agent du Mac, au début de chaque session**, récupère `main` (`git fetch`, puis sa branche de session), lit
   `queue.md` et propose à l'utilisateur les demandes `ouvertes`, les plus utiles d'abord (colonne « débloque »).
   Si la demande demande une branche pas encore fusionnée, il la récupère pour le test.
3. **Il fait faire le test**, lit lui-même les SavedVariables
   (`WTF/Account/<compte>/SavedVariables/ForeverSpeech.lua`), et demande seulement à l'utilisateur ce qu'il voit et
   entend.
4. **Il consigne le résultat** dans la fiche (section « Résultat », avec la date et la version du client), passe la
   ligne de la file à `répondue` avec un résumé d'une ligne, et ouvre sa pull request.
5. **L'agent du PC, au début de sa session**, lit les demandes `répondues`, en tire la décision (ou la propose à
   l'utilisateur quand elle lui revient), l'écrit dans la fiche et passe la ligne à `close`.

Statuts : `ouverte` → `en cours` (le Mac l'a prise) → `répondue` (résultat consigné) → `close` (décision prise).
Une demande qui ne peut pas être faite (le jeu ne le permet pas, une zone inaccessible) passe à `bloquée`, avec
la raison.

## Règles

- Une demande = une hypothèse vérifiable, avec un résultat attendu. Pas de « regarde si ça marche ».
- La procédure tient en quelques commandes : l'utilisateur joue, il ne débogue pas.
- Ce qui est vérifié devient un fait : il va dans CLAUDE.md (« Faits vérifiés sur Forever »), et le code arrête de
  le traiter comme une hypothèse.
