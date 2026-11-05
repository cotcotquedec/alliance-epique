# S12 — Le changement de zone (pour Elise)

**Question.** Sur Forever 1.60.1, quand le joueur entre dans une zone ou une sous-zone, quels événements se
déclenchent (`ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`) et quelles valeurs donnent
`GetZoneText()`, `GetSubZoneText()`, `GetRealZoneText()` et `C_Map.GetBestMapForUnit("player")` ? Lequel est un
identifiant stable (le même à chaque passage, indépendant de la langue) ?

**Impact.** Les répliques d'Elise à l'entrée d'une zone (D9, étape 2) se rangent par cet identifiant. Sans
identifiant stable : par le nom français de la zone (moins sûr : un renommage de Forever casse le lien).

**Livré depuis** (2026-10-11, D16) : les présentations de zone d'Elise (`core/zones.lua`) prennent
`C_Map.GetBestMapForUnit("player")`, remonté au niveau de la zone (`C_Map.GetMapInfo` : `mapType`, `parentMapID`),
et le cherchent dans l'index par l'identifiant de carte de la Forever Database (`uiMapId`, QuestieDB Forever,
build 1.60.1.69893 : Elwynn 1429, Marche de l'Ouest 1436, Stormwind 1453) ; sinon par le nom
(`GetRealZoneText`, `GetZoneText`). Le vol en griffon : `UnitOnTaxi("player")`, et `PLAYER_CONTROL_GAINED` à
l'atterrissage (avec un sondage toutes les 2 s en secours). Test : [T20](../ingame-tests.md). `/fs zone where`
donne d'un coup la carte, les noms et ce que l'index trouve.

## Procédure

Aucun code à installer : des `/dump` et `/etrace`.

1. `/etrace`, filtre `ZONE` : laisser la fenêtre ouverte.
2. Dans la Forêt d'Elwynn, aller de l'abbaye de Northshire jusqu'à Goldshire (changement de sous-zone), puis
   jusqu'à la Marche de l'Ouest (changement de zone).
3. À chaque endroit (Northshire, Goldshire, Marche de l'Ouest), taper :
   `/dump GetZoneText(), GetSubZoneText(), GetRealZoneText(), C_Map and C_Map.GetBestMapForUnit("player")`

**À relever :** les événements vus dans `/etrace` à chaque passage, et les quatre valeurs du `/dump` aux trois
endroits.

## Attendu

- `ZONE_CHANGED_NEW_AREA` au passage Elwynn → Marche de l'Ouest, `ZONE_CHANGED` au passage Northshire → Goldshire.
- `C_Map.GetBestMapForUnit` : un numéro par zone (Forêt d'Elwynn : 1429 sur Classic, 37 sur Retail ; Forever, à vérifier).

## Résultat

À faire (en jeu, sur le Mac).
