# S6 — Couverture Wowhead Forever FR

> Le script de ce spike (`pipeline/spikes/s6_coverage.py`) a été retiré le 2026-10-07 : voir l'historique git.

**Question.** Sur un échantillon de 50 quêtes d'une zone, quelle part a une description en français et un
PNJ donneur identifié ?

**Impact.** Cela mesure le poids du pré-chargement Wowhead face à la capture en jeu (D1).

**Statut : fait le 2026-10-05.**

## Méthode

- Zone : **Forêt d'Elwynn**, page de catégorie `/forever/fr/quests/eastern-kingdoms/elwynn-forest`
  (76 quêtes).
- Échantillon : 50 quêtes, tirage aléatoire avec la graine 6.
- Commande, qui peut être relancée gratuitement grâce au cache :
  `.venv/bin/python -m pipeline.spikes.s6_coverage --npcs`
- Coût réseau : 77 requêtes à 2,5 s d'intervalle, aucun blocage. Cela comprend la liste, les 50 quêtes,
  les 25 PNJ donneurs et robots.txt.
- Détail par quête : `data/cache/s6/eastern-kingdoms_elwynn-forest.json` (non versionné).
- « FR » = description présente, titre non marqué `[…]`, et plus de mots-outils français qu'anglais
  (heuristique).

## Résultat

| Mesure | Valeur |
|---|---|
| Page trouvée | 50/50 |
| **Description FR** | **45/50 (90 %)** |
| Donneur identifié sur la page | 43/50 (86 %) : 40 PNJ, 3 objets |
| Aucun donneur listé | 7/50. Ce sont des quêtes démarrées par un **objet d'inventaire** (note, livre, trophée, bon) ou des quêtes d'événement : Wowhead ne les indique pas dans l'infobox. |
| **Description FR et PNJ donneur** | **38/50 (76 %)** |
| Texte d'achèvement présent | 42/50 |
| Quêtes nouvelles dans Forever (`envChange: new`) | 20/50, dont 3 non traduites |
| Description avec un accord genré `<a/b>` | 4/50 (8 %) |

Pages PNJ des donneurs : 25/25 avec un nom et un displayID ; 7 ont un titre (`tag`).

### Les 5 quêtes sans description FR

| Quête | Cause |
|---|---|
| 16 « Procurer de l'eau à Gerard » | Wowhead n'a pas de section Description. |
| 7961 « Waskily Wabbits! » | Quête d'événement, texte resté en anglais. |
| 91736, 91738, 95771 | Nouvelles quêtes 1.60, non traduites sur Wowhead : titre `[English]`, pas de description. |

### Variables observées dans les textes Wowhead

| Variable | Occurrences |
|---|---|
| `<nom>` | 8 |
| `<classe>` | 2 |
| Accords `<prudent/prudente>`, `<costaud/costaude>`, `<cher monsieur/ma dame>` | 1 chacun |
| Forme avec suffixe `<un/une:c>`, `<impliqué/impliquée:c>` (quête 54) | 2 |

Le sens de `:c` n'est **pas établi**. Hypothèse : accord selon la classe ou le personnage plutôt que le
sexe, ou marqueur de casse. À éclaircir en comparant avec une capture en jeu de la quête 54 (S4 stocke
le texte intégral).

## Décision

- **Le pré-chargement Wowhead est rentable.**
  - 90 % des quêtes de l'échantillon ont une description FR exploitable : on peut générer l'audio avant
    d'avoir vu la quête.
  - Grâce à D9 (narrateur pour les quêtes démarrées par un objet ou un item), la part non couverte se
    limite aux 10 % sans texte FR.
- **La capture en jeu reste indispensable** :
  - pour les nouvelles quêtes 1.60 non traduites sur Wowhead, environ 15 % des nouveautés ici ;
  - pour les textes absents ou restés en anglais ;
  - pour détecter les réécritures (D7).

  Elle remplace de toute façon le texte Wowhead dès qu'elle existe (D1).
- Chaîne de fallback (§11) confirmée : capture > Wowhead FR > Wowhead EN + traduction > rien. Le cas
  « EN + traduction » concerne surtout les nouvelles quêtes 1.60. À vérifier : la page EN de ces quêtes
  a-t-elle une description ? Elles n'en ont pas toujours sur la page FR.
- Normalisation (D8) : prévoir les formes Wowhead `<nom>`, `<classe>` et `<a/b>`, ainsi que le suffixe
  `:c`, en plus des `$N`, `$C`, `$G` du client.
- Règle du pipeline : `starters == []` avec une description présente veut dire « démarrée par un item ou
  inconnue », donc voix narrateur (D9), sauf si une capture en jeu fournit un PNJ.
