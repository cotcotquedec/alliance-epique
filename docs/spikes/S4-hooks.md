# S4 — Noms des frames et points d'accroche

**Question.** Sur Forever, quels sont les noms et les points d'accroche :
- de la fenêtre de détail de quête et de son bouton Accepter ;
- du suivi d'objectifs (modernisé, avec des blocs recyclés) ;
- du journal de quêtes ?

On veut aussi savoir :
- quelles fonctions de mise à jour sont appelées, pour s'y greffer avec `hooksecurefunc` ;
- ce qu'on capte à `QUEST_DETAIL`, notamment le format du GUID du PNJ.

**Impact.** C'est ce qui détermine les hooks de toute l'interface de la phase 1.

## Ce que fait le module

| Commande | Effet |
|---|---|
| `/fs spike s4 globals` | Teste environ 50 noms candidats : Classic (`QuestWatchFrame`, `QuestLogFrame`), Wrath (`WatchFrame`) et Retail (`ObjectiveTrackerFrame`, `QuestObjectiveTracker`, `QuestMapFrame`). Pour chacun, il note le type, la visibilité et le parent, ou les méthodes s'il s'agit d'une table. Il parcourt aussi `_G` à la recherche de *Quest / Objective / Tracker / Watch* et stocke le résultat sans l'afficher. |
| `/fs spike s4 hooks` | Pose des `hooksecurefunc` de comptage sur les fonctions et méthodes candidates qui existent. Au premier appel de chacune, il note ses arguments (type et nom de frame). |
| `/fs spike s4 mouse <étiquette>` | Note la frame sous le curseur : sa chaîne de parents, `GetID`, son texte, et des champs comme `id`, `questID` ou `questLogIndex`. Laisse la souris en place pendant que tu tapes la commande dans le chat. |
| `/fs spike s4 report` | Affiche le nombre d'appels de chaque hook et de chaque événement de quête. |
| (automatique) | Enregistre les événements de quête (`QUEST_DETAIL`, `QUEST_ACCEPTED`, `QUEST_WATCH_LIST_CHANGED`…). À chaque `QUEST_DETAIL`, il stocke un instantané complet : questID, titre, texte intégral, objectifs, GUID et creatureID déduit, nom, sexe et type du PNJ, zone, mapID, sexe du joueur, récompenses. |
| `/fs spike shot` | Fait une capture d'écran 1 s plus tard, une fois le chat fermé. Les images vont dans `_classic_beta_/Screenshots/`, que je peux lire. |

## Procédure

1. `/fs spike s4 globals`, puis `/fs spike s4 hooks`.
2. Va voir un donneur de quête et ouvre le détail d'une quête **sans l'accepter**.
   - Survole le bouton **Accepter** : `/fs spike s4 mouse accept`.
   - Survole le texte de la quête : `/fs spike s4 mouse detail_text`.
   - `/fs spike shot`.
   - Accepte la quête.
3. La quête doit apparaître dans le suivi à droite.
   - Survole son titre : `/fs spike s4 mouse tracker_title`.
   - Survole une ligne d'objectif : `/fs spike s4 mouse tracker_objective`.
   - `/fs spike shot`.
4. Ouvre le journal (L) et sélectionne la quête.
   - Survole la quête dans la liste : `/fs spike s4 mouse log_entry`.
   - Survole le texte de détail : `/fs spike s4 mouse log_detail`.
   - `/fs spike shot`.
5. Dans le journal, retire la quête du suivi puis remets-la (Maj+clic ou case « Suivre »). Cela déclenche
   les hooks du suivi.
6. `/fs spike s4 report`, puis `/reload`.

Fais aussi `/fstack` sur le bouton Accepter et sur un bloc du suivi : une capture d'écran de l'info-bulle
de `/fstack` est un bon complément.

Si une étape ne se passe pas comme prévu (pas de suivi visible, journal différent…), décris ce que tu
vois : c'est aussi une information utile.

## À me renvoyer

- « fait ».
- Tes remarques sur l'emplacement idéal du bouton « Accepter et lire ».
- Je lis le reste dans le fichier SavedVariables et dans les captures d'écran.

## Résultat

Session du 2026-10-05, Northshire, personnage humain guerrière.

Les noms de frames sont de **style Retail 11.x**. Seule la fenêtre de PNJ garde les noms Classic.

**Fenêtre de détail de quête**
- Hiérarchie : `QuestFrame` > `QuestFrameDetailPanel` > `QuestFrameAcceptButton` (texte « Accepter »)
  et `QuestFrameDeclineButton`.
- Texte : `QuestDetailScrollFrame` > `QuestDetailScrollChildFrame`, rempli par
  `QuestInfo_Display(template, parent, acceptButton, material)`. Ce hook est appelé à chaque affichage.
- Portrait : `QuestFramePortrait`, parent `QuestFrame.PortraitContainer`. `QuestModelScene` existe.
- Position : en haut à gauche de l'écran, sur un fond parchemin, avec Accepter et Refuser en bas.

**Suivi d'objectifs**
- Hiérarchie : `ObjectiveTrackerFrame` > `QuestObjectiveTracker` (module) > `.ContentsFrame` > blocs
  anonymes, puis `<bloc>.HeaderButton` pour le titre.
- `ObjectiveTrackerManager` est une table de 22 méthodes (`UpdateAll`, `UpdateModule`,
  `EnumerateActiveBlocksByTag`…).
- Hooks observés, comptés pendant la session :
  - `QuestObjectiveTracker:Update(self, dirtyFlags, …)` : 5 appels ;
  - `:MarkDirty` : 5 ;
  - `:LayoutContents` : 5 ;
  - `:GetBlock(self, questID)` : 14 ;
  - `:AddBlock(self, block)` : 14.
- `ObjectiveTrackerFrame:Update` et `ObjectiveTrackerManager:UpdateAll`/`UpdateModule` n'ont **pas** été
  appelés.
- Pas de `QuestWatchFrame`, de `WatchFrame` ni de `QUEST_TRACKER_MODULE`.

**Journal de quêtes**
- Il fait partie de la carte (« Carte & Journal des quêtes ») : `WorldMapFrame` > `QuestMapFrame` >
  `QuestMapFrame.QuestsFrame` > `QuestScrollFrame.Contents` > boutons de quête anonymes.
- Chaque bouton porte les champs `questID`, `questLogIndex` et `info` (le `QuestInfo` de
  `C_QuestLog.GetInfo`).
- Hooks : `QuestLogQuests_Update()` (9 appels) et `QuestMapFrame_ShowQuestDetails(questID)` (2).
  `QuestLogPopupDetailFrame` existe.
- Il n'y a pas de `QuestLogFrame` Classic.

**Événements** (signatures confirmées par la documentation d'API du client)
- `QUEST_DETAIL(questStartItemID?)` : a reçu 0 pour une quête donnée par un PNJ.
- `QUEST_ACCEPTED(questId)`.
- `QUEST_WATCH_LIST_CHANGED(questID?, added?)` : `(nil, nil)` à la connexion, `(33, false)` puis
  `(33, true)` quand on bascule le suivi.
- `QUEST_FINISHED` : se déclenche deux fois à la fermeture.

**Capture à `QUEST_DETAIL`** (quête 18, Adjoint Willem)
- GUID : `Creature-0-4621-0-80-823-0000407152`. Le motif d'extraction donne bien `823`.
- PNJ :
  - `UnitSex("npc")` = 2 (masculin) ;
  - `UnitCreatureType("npc")` = « Humanoïde », 7 ;
  - `UnitClassification` = normal ;
  - `UnitRace("npc")` ne renvoie rien.
- Quête :
  - `GetQuestID()` = 18 ;
  - `GetTitleText()` = « La confrérie des voleurs » ;
  - `GetQuestText()` = le texte complet (339 caractères, paragraphes séparés par `

`) ;
  - `GetObjectiveText()` = les objectifs.
- Joueur : `UnitSex("player")` = 3. Zone : `mapID` 1429, Forêt d'Elwynn, sous-zone Vallée de
  Northshire.
- Récompenses : `GetRewardXP()` = 360, `GetNumQuestChoices()` = 5.
- Le texte capturé est identique à la description Wowhead de la quête 18, à vérifier côté pipeline.

**API générales**
- `C_QuestLog.*` de style Retail : `GetInfo(questLogIndex)`, `GetTitleForQuestID`, `GetQuestObjectives`,
  `GetSelectedQuest`, `SetSelectedQuest`, `RequestLoadQuestByID` et `QUEST_DATA_LOAD_RESULT`.
- Absents : `GetQuestLogTitle`, `GetNumQuestWatches`, `GetMouseFocus` et `LoadAddOn`. Il faut utiliser
  `C_AddOns.LoadAddOn` et `GetMouseFoci`.
- `Screenshot()` fonctionne depuis un addon.

## Décision

- **Bouton « Accepter et lire »** : un bouton enfant de `QuestFrameDetailPanel`, ancré à
  `QuestFrameAcceptButton`. On le crée une fois et on le montre ou le cache via
  `QuestFrameDetailPanel:HookScript("OnShow")`. La capture se fait sur l'événement `QUEST_DETAIL`.
- **Suivi** : `hooksecurefunc(QuestObjectiveTracker, "AddBlock", fn(self, block))`, puis on attache ou
  réutilise un bouton par bloc. Les blocs sont recyclés : on stocke le bouton sur le bloc et on relit son
  `questID` à chaque appel.
  - **À vérifier** : le champ qui porte l'ID de quête sur le bloc (`block.id` en Retail). Ce sera le
    premier test de l'incrément « suivi ».
  - Repli : `GetBlock(self, questID)` reçoit le questID ; on peut s'y greffer pour associer un bloc à
    son ID.
- **Journal** : `hooksecurefunc("QuestLogQuests_Update")` pour décorer les boutons de
  `QuestScrollFrame.Contents`, qui portent `questID`, et `hooksecurefunc("QuestMapFrame_ShowQuestDetails")`
  pour un bouton dans le panneau de détail.
- **Capture** : questID, titre, texte, objectifs, PNJ et zone sont tous disponibles à `QUEST_DETAIL`
  (§9.2 confirmé). La race du PNJ n'est pas disponible en jeu, elle viendra du pipeline (§11).
- Tous les hooks passent par `hooksecurefunc`. Aucune frame Blizzard n'est remplacée.
