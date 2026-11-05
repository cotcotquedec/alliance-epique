# S8 — Modèle 3D du PNJ hors interaction

**Question.** Sur Forever, un `PlayerModel` affiche-t-il un PNJ :
- via `SetCreature(npcID)`, y compris pour un PNJ jamais croisé dans la session (cache client) ?
- via `SetDisplayInfo(displayID)` ?

On veut aussi savoir si `SetUnit("target")` suivi de `GetDisplayInfo()` permet de **capturer le
displayID en jeu**.

**Impact.** En cas d'échec, le lecteur affichera seulement l'icône de quête.

## Données de référence (Wowhead, S7)

| PNJ | npcID | displayID | Lieu |
|---|---|---|---|
| Adjoint Willem | 823 | 2072 | Northshire |
| Frère Sammuel | 925 | 3346 | Northshire |

## Ce que fait le module (`/fs spike s8 [npcID] [displayID]`, environ 15 s)

Une fenêtre noire déplaçable s'ouvre. Elle a un bouton de fermeture et une étiquette qui indique l'étape
en cours.

| Temps | Étape | Action |
|---|---|---|
| t = 0 | A | `SetCreature(npcID)` (823 par défaut) |
| t = 5 s | B | `SetDisplayInfo(displayID)` (2072 par défaut) |
| t = 10 s | C | Si tu as une cible : `SetUnit("target")` |

Deux secondes après chaque étape, le module note `GetModelFileID()`, non nul si un modèle est chargé, et
`GetDisplayInfo()`. Il vérifie aussi que `CreateFrame("ModelScene")` est possible.

## Procédure

1. **Loin de Northshire, ou sans être passé près de l'adjoint Willem** : `/fs spike s8`. Cela teste
   un PNJ absent du cache.
2. Cible un PNJ quelconque à proximité, puis `/fs spike s8 823 2072` pour tester l'étape C.
3. Si tu es Horde ou ailleurs, prends un PNJ proche : je te donnerai son displayID, ou relance avec
   `/fs spike s8 <npcID> 0` et seuls A et C seront utiles.
4. Ferme la fenêtre (croix en haut à droite).

## À me renvoyer

Pour A, B et C : un modèle visible (lequel, à peu près), un cadre vide, ou un modèle par défaut (cube,
point d'interrogation…).

## Résultat

Session du 2026-10-05, à côté de l'Adjoint Willem, donc **PNJ en cache**. Fenêtre vue par l'utilisateur.

| Étape | Appel | `GetModelFileID` | `GetDisplayInfo` |
|---|---|---|---|
| A | `SetCreature(823)` | 1011653 | **2072**, identique à Wowhead |
| B | `SetDisplayInfo(2072)` | 1011653 | 2072 |
| C | `SetUnit("target")` | 1000764 | **0** |

`CreateFrame("ModelScene")` fonctionne aussi.

**Hors cache** (Thrall, jamais croisé, personnage Alliance à Northshire) : `/fs spike s8 4949 4527`.

| Étape | Appel | `GetModelFileID` | `GetDisplayInfo` |
|---|---|---|---|
| A | `SetCreature(4949)` | **nil** : aucun modèle | 0 |
| B | `SetDisplayInfo(4527)` | 917116 | 4527 |

Non testé : `SetCreature` sur un PNJ hors cache se charge-t-il plus tard que 2 s, après la réponse du
serveur ?

## Décision

- **Le lecteur utilise `SetDisplayInfo(displayID)`**, avec le displayID de Wowhead
  (`data-mv-display-id`, identique à celui du client). Il fonctionne même pour un PNJ jamais croisé.
- `SetCreature(npcID)` ne marche que si le PNJ est en cache. Il reste en secours quand on n'a pas de
  displayID.
- `SetUnit` puis `GetDisplayInfo` renvoie 0 : on ne peut pas capturer le displayID en jeu.
- Le displayID devient donc une donnée de l'index (§8), à ajouter au contrat dans un champ optionnel
  `display`, avec incrément de `version`. Ce sera proposé avec l'incrément « lecteur ».
- Si on n'a ni displayID ni modèle chargé (`GetModelFileID()` nil après un court délai), on affiche
  l'icône de quête.
