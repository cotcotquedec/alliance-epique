# Tests en jeu — phase 1

Chaque incrément livré s'accompagne d'une procédure courte. Les résultats sont consignés ici.

Rappel : je lis directement `WTF/Account/<COMPTE>/SavedVariables/ForeverSpeech.lua` après un
`/reload` ou une déconnexion. Tu n'as à me renvoyer que ce que tu **entends** et ce que tu **vois**.

---

## T1 + T2 — Lecteur de son et capture (incréments 1 et 2)

**Livré** :
- `core/player.lua` :
  - un seul son à la fois, avec **liste de lecture** : une nouvelle demande se met en file ;
  - Stop passe à la suivante, `/fs clear` arrête tout ;
  - les doublons sont ignorés ;
  - détection de fin par `C_Sound.IsPlaying` ;
  - repli vers le son de test ou la synthèse vocale.
- `core/index.lua` : recherche dans l'index généré.
- `core/capture.lua` : capture à `QUEST_DETAIL` vers `ForeverSpeechCaptures`.
- Nouvelles commandes : `/fs test`, `/fs play [questID]`, `/fs stop`, `/fs clear`, `/fs queue`,
  `/fs channel …`, `/fs fallback test|tts|none`, `/fs captures`.

**Prérequis** : ce sont de nouveaux fichiers Lua dans le TOC. Il faut donc **un lancement complet du
jeu** ; un `/reload` ne suffit pas.

### T1 — Lecteur

| # | Action | Attendu |
|---|---|---|
| 1 | `/fs` | L'aide liste `test`, `play`, `stop`, `channel`, `fallback`, `captures`. |
| 2 | `/fs debug on` | `debug is on`. |
| 3 | `/fs test`, puis laisse jouer jusqu'au bout (environ 9 s) | La phrase « Test numéro deux… ». En gris, `playback started: file (test)`, puis à la fin `playback ended: finished (test)`. |
| 4 | `/fs test`, puis `/fs stop` au bout de 2 ou 3 s | La voix se coupe. Message `playback ended: stopped`. |
| 5 | `/fs test`, puis `/fs test` à nouveau tout de suite | La 2e demande est ignorée : `the test sound is already playing`. Une seule voix. |
| 6 | `/fs channel master`, `/fs test`, puis `/fs channel dialog` | Le son joue aussi sur Master. |

### T2 — Capture

| # | Action | Attendu |
|---|---|---|
| 1 | Parle à un donneur de quête et ouvre le détail d'une quête. Inutile de l'accepter. | Avec `debug on` : `captured quest <ID> (<PNJ>)`. Note l'ID. |
| 2 | `/fs captures` | `1 quest(s) captured, 1 text(s)`. |
| 3 | Ferme la fenêtre, puis rouvre la même quête. `/fs captures` | Toujours `1 text(s)`. Le doublon est fusionné. |
| 4 | `/fs play` (sans ID : dernière quête ouverte). `/fs captures` liste aussi les ID. | `playing quest <ID> (test)` et le son de test, car il n'y a pas encore d'audio pour cette quête. |
| 5 | `/fs fallback tts`, puis `/fs play <ID>` | **Le texte de la quête lu par la voix Thomas.** |
| 6 | `/fs stop` pendant la lecture | La synthèse s'arrête. |
| 6b | **File** : `/fs play <ID>`, puis tout de suite `/fs test` | `the test sound queued (position 1)`. La quête est lue jusqu'au bout, **puis** le son de test démarre tout seul. |
| 6c | `/fs play <ID>`, `/fs test`, puis `/fs stop` | La quête se coupe et le son de test démarre aussitôt. |
| 6d | `/fs play <ID>`, `/fs test`, puis `/fs queue`, puis `/fs clear` | `/fs queue` affiche `now: quest <ID>` et `1. test sound`. `/fs clear` coupe tout. |
| 7 | `/fs fallback test`, puis `/reload` | — |

Bonus, si tu en croises une : ouvre aussi une quête démarrée par un **objet**, comme un panneau ou un
cadavre. On vérifiera que le type de donneur est bien capté.

### À me renvoyer

- T1 : les numéros qui ne se sont pas passés comme prévu, ou « T1 OK ».
- T2 : l'ID de quête, et si la synthèse vocale de l'étape 5 a bien lu le texte de la quête.
- « fait » après le `/reload`.

### Résultat (2026-10-05)

T1 et T2 sont validés en jeu.
- Lecture, fin de lecture détectée, Stop.
- Capture de la quête 18 (Adjoint Willem).
- TTS du texte capturé, entendu.
- La file de lecture a été demandée pendant ce test, puis livrée.

---

## T3 — Interface de la phase 1 et fenêtre principale

**Livré** :

| Élément | Contenu |
|---|---|
| **Fenêtre principale** (`ui/player_frame.lua`) | Déplaçable, position mémorisée. En-tête « ForeverSpeech » avec deux onglets (**Quête** et **Options**) et le bouton **Liste**. Elle **s'ouvre à chaque lecture** (option). |
| Onglet Quête | Modèle 3D du PNJ (ou icône de quête), titre, donneur, état, objectifs, description qui défile, récompenses. Boutons Lecture (du début), Stop (passe à la suivante), Fermer. |
| Onglet Options | Cases à cocher : ouvrir à chaque lecture, son de page, lire avec le bouton Accepter du jeu, liste de lecture, icône de minimap, mode debug. Deux réglages à choix : repli sans fichier audio (synthèse vocale, son de test, rien) et canal audio. |
| **Liste de lecture** (panneau latéral) | Historique en gris, quête en cours en vert, file en jaune et numérotée. Un clic affiche la quête, la croix la retire de la file. Le panneau passe à gauche de la fenêtre si elle est collée au bord droit de l'écran. |
| **Son de page** | Le son d'ouverture de quête du jeu (`SOUNDKIT.IG_QUEST_LIST_OPEN`, repli sur l'ID 875) au début de chaque quête lue. |
| **Bouton de minimap** (`ui/minimap_button.lua`) | Clic : ouvrir ou fermer la fenêtre. Clic droit : options. Glisser : le déplacer autour de la minimap (position mémorisée). |
| « Accepter et lire » | Icône ▶ dorée et lecture des objectifs à la suite de la description. |
| Suivi et journal | Boutons ▶/■ sur les quêtes. |

Commandes : `/fs` seul ouvre ou ferme la fenêtre, `/fs help` affiche l'aide, et `/fs options` ouvre les
options.

**Prérequis** : il y a de nouveaux fichiers (`minimap_button.lua`, `icon.tga`). Il faut donc **un
lancement complet du jeu**.

Hypothèses non vérifiées, que ce test doit trancher :
- l'ID de quête porté par les blocs du suivi (`block.id`) ;
- la signature de `GetQuestLogQuestText` et les fonctions de récompenses du journal ;
- `QuestMapFrame.DetailsFrame` ;
- les templates `BackdropTemplate`, `UIPanelScrollFrameTemplate` et `UICheckButtonTemplate` (avec repli) ;
- `SOUNDKIT` ;
- les textures de bouton de minimap.

### Procédure, 100 % à la souris

La **barre de debug** apparaît sous la fenêtre quand le mode debug est coché. Elle a trois boutons :
- **Repère n°X** : écrit « étape X » dans le journal de diagnostic ;
- **Capture** : capture d'écran ;
- **Recharger** : `/reload`.

Clique sur **Repère** avant chaque étape, à partir de l'étape 2.

| # | Action | Attendu |
|---|---|---|
| 1 | Lance le jeu. Clique sur l'**icône haut-parleur** de la minimap, onglet **Options**, puis coche **Mode debug** | La fenêtre s'ouvre et la barre de debug apparaît dessous. |
| 2 | **Repère**. Ouvre une quête nouvelle chez un PNJ, **Capture**, puis clique sur **Accepter et lire** | Bouton avec ▶ doré. Au clic : son de page, puis la voix lit la description puis « Objectif : … ». La fenêtre affiche la quête avec le modèle du PNJ, et la quête est en vert dans la liste. |
| 3 | **Repère**. Molette sur la description, survol d'une récompense, déplacement de la fenêtre, **Stop** puis **Lecture**, **Capture** | Tout réagit. La liste et la barre de debug suivent la fenêtre. |
| 4 | **Repère**. Suivi à droite : ▶ sur une autre quête, **Capture**, puis reclic sur ■ | Son de page et lecture, la fenêtre affiche cette quête, ■ vert. Reclic : arrêt. |
| 5 | **Repère**. ▶ quête A puis ▶ quête B. Croix de B dans la liste, ▶ B à nouveau, puis **Stop** | A en vert, B en jaune « 1. ». La croix retire B. Après Stop, B démarre, la fenêtre suit et A passe en gris. |
| 6 | **Repère**. Journal (L) : ▶ sur une ligne, puis ouvre le détail d'une quête et clique sur son ▶. **Capture** | Les boutons sont présents et lisent la quête. |
| 7 | **Repère**. Onglet **Options** : décoche puis recoche « Son de page », change « Sans fichier audio » et remets « Synthèse vocale », décoche puis recoche « Icône sur la minimap » | Les réglages s'appliquent : l'icône disparaît puis revient. |
| 8 | **Repère**, puis **Recharger**. Clique ensuite sur l'icône de la minimap | La fenêtre et l'icône sont à la même place, les options sont conservées. |

### À me renvoyer

- Pour chaque étape : **OK**, ou ce qui cloche.
- Modèle 3D affiché à l'étape 2 ?
- Erreurs rouges éventuelles.
- « fait » : je lis le journal et les captures.

### Résultat (2026-10-05) : **T3 validé**

L'utilisateur a validé tout le scénario. Le journal de diagnostic (`ForeverSpeechDB.trace`) tranche les
hypothèses :

| Hypothèse | Constat |
|---|---|
| ID de quête sur les blocs du suivi | `block.id` = questID (33), identique à l'ID passé à `GetBlock` |
| Texte du journal | `GetQuestLogQuestText(logIndex)` renvoie la description (forme Retail, sans sélection) |
| Récompenses du journal | `GetNumQuestLogRewards`, `GetQuestLogRewardInfo`, `GetNumQuestLogChoices`, `GetQuestLogChoiceInfo`, `GetQuestLogRewardMoney`, `GetQuestLogRewardXP` existent et renvoient des données (quête 33 : 2 choix, 170 XP) |
| Templates | `BackdropTemplate` et `UIPanelScrollFrameTemplate` présents |
| Panneau de détail | `QuestMapFrame.DetailsFrame` présent |
| Modèle 3D | `SetCreature(823)` → fileID 1011653 juste après l'acceptation |
| « Accepter et lire » | Il tient entre Accepter (droite à 99) et Refuser (gauche à 270) : largeur 150 |
| Minimap | Au 1er chargement, le bouton était créé avant que la minimap ait sa taille, donc invisible. Après correction (placement à `PLAYER_ENTERING_WORLD`) : largeur de la minimap 198. `AddonCompartmentFrame` existe et l'inscription réussit. L'utilisateur n'a pas besoin de l'icône : la fenêtre s'ouvre via les boutons ▶. |
| `GetCoinTextureString`, `GameTooltip:SetItemByID` | Présents |

Retours d'usage, appliqués :
- un seul ▶ par quête dans le journal, sur la ligne du titre ;
- icône ▶ sur « Accepter et lire » ;
- les objectifs sont lus après la description ;
- file de lecture, fenêtre principale avec liste de lecture, options et barre de debug.

---

## T4 — Modèle 3D de tout PNJ donneur (index v2)

**Livré** :
- `data/index.lua` passe au contrat v2. Il est généré à partir des registres de la Forêt d'Elwynn :
  64 quêtes y sont reliées à leur donneur, et 32 PNJ y ont leur numéro de modèle (`display`) et leur nom.
- Le lecteur prend le donneur dans la capture, sinon dans l'index. Il affiche ensuite le modèle avec `SetDisplayInfo`,
  qui marche même si le PNJ n'est pas dans le cache du client (S8).
- **Avant** : une quête relancée depuis le journal sans capture affichait l'icône.
- **Maintenant** : elle affiche le PNJ et son nom.

**Prérequis** : seul un fichier existant a changé. Un `/reload` (bouton **Recharger**) suffit.

| # | Action | Attendu |
|---|---|---|
| 1 | Barre de debug : **Recharger** | Pas d'erreur rouge. |
| 2 | **Repère**. Journal (L) : ▶ sur une quête de la Forêt d'Elwynn, de préférence une quête acceptée il y a longtemps, ou loin de son donneur. **Capture** | La fenêtre affiche le **modèle 3D du donneur** et son nom sous le titre. |
| 3 | **Repère**. Suivi à droite : ▶ sur une autre quête d'Elwynn. **Capture** | Même chose, avec le bon PNJ. |
| 4 | **Repère**. Ouvre une nouvelle quête chez un PNJ et clique sur **Accepter et lire** | Le modèle s'affiche, comme avant. |

**À me renvoyer** : OK ou ce qui cloche pour chaque étape, les PNJ que tu as vus, puis « fait ». Je lis
`ForeverSpeechDB.trace` (lignes `frame: model … display=… fileID=…`).

---

## T5 — Premières vraies voix de PNJ (ElevenLabs v4)

**Livré** : 8 quêtes de la Forêt d'Elwynn ont maintenant leur audio, joué par la voix propre du PNJ. Le reste passe
toujours par la synthèse vocale du client.

| PNJ | Quêtes |
|---|---|
| Adjoint Willem | 6 (versions joueur et joueuse), 18, 783, 3903, 5261 |
| Maman Stonefield | 88 |
| Billy Maclure | 86, 87 |

**Prérequis** : `data/index.lua` a changé et de nouveaux `.ogg` sont apparus. D'après S2, un nouveau `.ogg` est lisible après un `/reload` :
la barre de debug, bouton **Recharger**, suffit.

| # | Action | Attendu |
|---|---|---|
| 1 | **Recharger** | Pas d'erreur rouge. |
| 2 | **Repère**. Journal (L) : ▶ sur une quête de la liste ci-dessus, si tu l'as dans ton journal | La **voix du PNJ**, jouée avec émotion, à la place de la voix Thomas. Le modèle 3D du donneur s'affiche. |
| 3 | **Repère**. Ou `/fs play 783` (et `/fs play 6`) | Même chose, même pour une quête déjà rendue. |
| 4 | **Repère**. **Stop** pendant la lecture | La voix se coupe. |

**À me renvoyer** : ce que tu entends, puis « fait ». Je lis `ForeverSpeechDB.trace`.

---

## T6 — Liste de lecture : ordre fixe, lire, pause entre quêtes, double-clic, Vider, debug coupé

**Livré** :
- le mode debug est coupé une fois au chargement (réglage enregistré remis à « non ») ; il se réactive dans l'onglet
  **Options**, case « Mode debug », et reste alors activé ;
- la liste de lecture garde son ordre et ne contient chaque quête qu'une fois ;
- **lire une quête** (▶ du suivi ou du journal, **Accepter et lire**, `/fs play`) la met toujours dans la liste : à la
  fin, ou à sa place si elle y est déjà (une quête grise redevient jaune, « à lire »). Si une lecture est en cours,
  la liste continue ; sinon cette quête démarre tout de suite ;
- **pause de 2 s entre deux quêtes** (Options : « Pause entre deux quêtes », Aucune / 1 / 2 / 3 / 5 s) ; pendant la
  pause, la liste compte comme « en lecture » ;
- **son de page plus fort** au début de chaque quête : canal Master au lieu d'Effets, joué en deux copies ;
- **double-clic** sur une ligne : la lecture en cours s'arrête et cette quête repart du début, à sa place. Ensuite,
  la lecture continue avec la première quête pas encore lue ;
- **Lecture** dans la fenêtre : relance du début la quête en cours ; pour une autre quête, comme un ▶ ;
- bouton **Vider** en haut de la liste (et `/fs reset`) : tout s'arrête et la liste est vide.

**Non vérifié sur Forever** : le script `OnDoubleClick` des boutons (standard, a priori présent) ; le gain réel du
son de page (Master + deux copies) dépend de tes curseurs de volume : dis-moi s'il est trop fort ou pas assez.

| # | Action | Attendu |
|---|---|---|
| 1 | `/reload` | Plus de barre de debug sous la fenêtre ; Options : « Mode debug » décoché, « Pause entre deux quêtes : 2 s ». |
| 2 | Suivi à droite : ▶ sur trois quêtes A, B, C | A joue tout de suite (son de page plus fort) ; B (1.), C (2.) en jaune. |
| 3 | ▶ sur B une deuxième fois | Pas de nouvelle ligne ; B toujours en 1. |
| 4 | Laisse A finir | Environ 2 s de silence, son de page, puis B. |
| 5 | Pendant B, ▶ sur A (grise) | Pas de nouvelle ligne ; A redevient jaune, en tête de liste. |
| 6 | Double-clic sur la ligne C | B s'arrête, C repart du début ; l'ordre reste A, B, C. |
| 7 | **Stop** | Pause, puis A (première quête pas encore lue). |
| 8 | **Vider** | Le son s'arrête, la liste est vide. |
| 9 | Chez un PNJ, **Accepter et lire** sans rien en lecture | La lecture démarre tout de suite. |
| 10 | Pendant une lecture, **Accepter et lire** sur une autre quête | Elle s'ajoute à la fin de la liste (jaune) et démarre après la pause. |

**À me renvoyer** : OK ou ce qui cloche pour chaque étape, ton avis sur le volume du son de page et sur la durée de
la pause, puis « fait ». Je lis `ForeverSpeechDB.trace`.

---

## T7 — Boutons en icônes sous l'état, Avancer, sans description

**Livré** :
- les boutons **Lecture / Avancer / Stop** sont des icônes sous la ligne d'état (à droite du modèle 3D), avec une
  bulle au survol ; le bouton **Fermer** est retiré (la croix en haut à droite suffit) ;
- **Stop** arrête la lecture **et la liste** : rien ne démarre ensuite, les quêtes jaunes restent. **Avancer** passe
  tout de suite à la première quête pas encore lue (sans pause), et relance une liste arrêtée ;
- la description n'est plus affichée. Les objectifs (police plus grande, 5 lignes au plus) sont suivis
  directement des récompenses ; la fenêtre est compacte sur l'onglet Quête (344 au lieu de 506) et grandit vers
  le bas sur l'onglet Options (430). La liste garde au plus 19 quêtes et dépasse sous la fenêtre si besoin ;
- **Lecture** joue la quête **affichée** : tout de suite, du début, à sa place dans la liste (à la fin si elle n'y
  est pas). **Avancer** et **Stop** agissent sur la liste.

**Prérequis** : nouvelle texture `media/next.tga`. D'après S2, un `/reload` devrait suffire ; si l'icône Avancer
reste vide ou verte, redémarre le jeu.

| # | Action | Attendu |
|---|---|---|
| 1 | `/reload`, puis ▶ sur trois quêtes A, B, C | Sous l'état : trois icônes ▶ ⏭ ■ dorées ; plus de Fermer en bas ; plus de description. |
| 2 | Survol des trois icônes | Bulles « Lecture (depuis le début) », « Avancer : quête suivante de la liste », « Arrêter la lecture ». |
| 3 | **Avancer** pendant A | B démarre tout de suite. |
| 4 | **Stop** | Le son s'arrête, C reste en jaune, rien ne démarre. Stop grisé. |
| 5 | **Avancer** | C démarre. |
| 6 | Onglet **Options** | La fenêtre grandit vers le bas (le haut ne bouge pas) ; toutes les lignes visibles. Retour à **Quête** : elle redevient compacte. |
| 7 | Clic sur la ligne A de la liste (fenêtre sur A), puis **Lecture** | A repart du début tout de suite, à sa place dans la liste. |
| 8 | Quête aux longs objectifs | 5 lignes au plus, coupées par « … » ; les récompenses juste dessous. |

**À me renvoyer** : OK ou ce qui cloche pour chaque étape (une capture de la fenêtre si la mise en page cloche),
puis « fait ».

---

## T8 — Modèle 3D cadré sur la tête et le buste

**Livré** : le modèle du PNJ est cadré en portrait (`PlayerModel:SetPortraitZoom`, 0 = en pied, 1 = visage), à 0,6
par défaut, réappliqué quand le modèle a fini de charger. Réglable en jeu : `/fs zoom 0.7`, appliqué tout de suite.

**Non vérifié sur Forever** : `SetPortraitZoom` et le script `OnModelLoaded`. S'ils manquent, le modèle reste en
pied (aucune erreur).

| # | Action | Attendu |
|---|---|---|
| 1 | `/reload`, puis ouvre une quête dont le donneur a un modèle (Adjoint Willem, quête 783) | Tête et buste, pas le personnage entier. |
| 2 | `/fs zoom 0.4`, `/fs zoom 0.8` | Le cadrage change tout de suite : plus large, puis plus serré. |
| 3 | Deux ou trois autres PNJ (humain, nain, gnome) | Cadrage correct pour chacun. |

**Résultat (2026-10-05)** : cadrage validé, zoom 0,6 gardé par défaut.

**À me renvoyer** : la valeur de zoom qui te plaît (je la mettrai par défaut), une capture si un PNJ est mal cadré,
puis « fait ». Je lis `ForeverSpeechDB.trace` (lignes `frame: model … zoom=… ok=…`).

---

## T9 — Récompenses d'une quête capturée avant leur prise en charge

**Constat (2026-10-05)** : « La confrérie des voleurs » (18) n'affichait aucune récompense. Sa capture date d'avant la
lecture des récompenses (pas de champ `rewards` dans `ForeverSpeechCaptures`) et, le texte étant identique, chaque
réouverture comptait comme un doublon (`seen = 12`) sans jamais compléter la capture.

**Corrigé** : une capture déjà connue est complétée à la réouverture (récompenses fraîches et champs ajoutés
depuis) ; sans récompenses capturées, le lecteur prend celles du journal de quêtes.

| # | Action | Attendu |
|---|---|---|
| 1 | `/reload`, puis ▶ sur « La confrérie des voleurs » dans le suivi ou le journal | Les récompenses s'affichent (les objets au choix en grisé, bulle « au choix »). |
| 2 | Rouvre la quête chez l'Adjoint Willem si elle est encore disponible, puis `/reload` | La capture contient maintenant `rewards`. |

**À me renvoyer** : OK ou ce qui manque, puis « fait ».

---

## T10 — Progression des objectifs en direct

**Livré** : sous le résumé des objectifs, la fenêtre affiche la progression lue dans le journal
(`C_QuestLog.GetQuestObjectives`, présent dans le dump d'API), par exemple « - Masque rouge : 3/12 », en vert une
fois rempli. Mise à jour à chaque `QUEST_LOG_UPDATE` tant que la fenêtre est ouverte. Une quête absente du journal
(rendue, pas encore acceptée) n'affiche que le résumé.

**Non vérifié sur Forever** : le format des lignes renvoyées (champs `text` et `finished`, comme sur Retail).

| # | Action | Attendu |
|---|---|---|
| 1 | `/reload`, ▶ sur « La confrérie des voleurs » (en cours) | Le résumé, puis « - Masque rouge : n/12 » en blanc. |
| 2 | Tue un Défias qui laisse tomber un masque, fenêtre ouverte | Le compteur passe à n+1 sans rien toucher. |
| 3 | Objectif rempli | La ligne passe en vert. |

**À me renvoyer** : OK ou ce qui cloche, puis « fait ». Je lis `ForeverSpeechDB.trace`.

## T11 — Fin de quête (spike S9, index v3)

**Livré** (2026-10-06) : le texte de rendu est capturé à l'ouverture de la fenêtre de récompense. Au clic sur
« Terminer la quête », il est lu 2 s après, avec la voix du PNJ de rendu si l'audio existe, sinon par la synthèse
vocale du client. Il passe dans la liste de lecture comme toute quête : **!** pour un début, **?** pour une fin.
Seules les 5 fins du Maréchal McBride (quêtes 7, 15, 21, 783, 91752) ont un audio pour l'instant.

**Non vérifié sur Forever** : `QUEST_COMPLETE`, `GetRewardText`, `GetQuestReward` (S9).

| # | Action | Attendu |
|---|---|---|
| 1 | `/reload`, puis `/dump ForeverSpeechIndex.version` | `3` |
| 2 | `/fs play 783 end` | Le Maréchal McBride dit « Ah, parfait, un autre volontaire… » ; dans la liste, la ligne commence par **?**. |
| 3 | Rends une quête que tu as finie (n'importe laquelle) et, fenêtre de récompense ouverte : `/dump GetQuestID(), GetRewardText()` | L'ID de la quête et le texte affiché par le PNJ. |
| 4 | Clique sur « Terminer la quête » | Le PNJ parle, puis 2 s après la fin de quête est lue (synthèse vocale si pas d'audio) ; le lecteur montre le PNJ de rendu et un **?** devant le titre. |
| 5 | Rends une deuxième quête pendant que la première se lit | Elle s'ajoute dans la liste (**?**) et se lit ensuite. |
| 6 | `/fs turnin off`, rends une quête | Rien ne se lit. `/fs turnin on` pour remettre. |

**À me renvoyer** : le résultat de l'étape 3, OK ou ce qui cloche pour les autres étapes, puis « fait ».
Je lis `ForeverSpeechDB.trace` et `ForeverSpeechCaptures.completions`.

## T12 — Fin de quête lue dès l'ouverture de l'onglet « Terminer la quête »

**Livré** (2026-10-07, demandé pour pouvoir tester les fins) : la fin de quête n'attend plus le clic sur « Terminer la
quête ». Elle entre dans la liste de lecture **dès que l'onglet de fin de quête s'affiche** (événement
`QUEST_COMPLETE`) : elle démarre tout de suite si rien ne joue, sinon elle attend son tour. Le clic sur « Terminer
la quête » ne relance rien. Les audios d'Elwynn ayant été supprimés le 2026-10-07, les fins d'Elwynn se lisent par la
synthèse vocale du client ; Dun Morogh garde ses audios de début.

**Premier essai (2026-10-07, 08:59)** : rien ne se lit. `QUEST_COMPLETE` arrive bien, mais le second abonnement à cet
événement était perdu (`RegisterEvent` renvoie `false` pour un événement déjà enregistré, voir S9). Corrigé ; à refaire.
Deuxième essai : la fin se lit, mais les textes courts chevauchent la voix d'origine du PNJ. La lecture part
désormais **1 s après** l'ouverture de l'onglet.

| # | Action | Attendu |
|---|---|---|
| 1 | `/reload`, puis parle à un PNJ qui attend une quête finie, jusqu'à l'onglet « Terminer la quête » | 1 s après l'affichage de l'onglet, la fin de quête est lue (synthèse vocale si pas d'audio) ; dans la liste de lecture, une ligne **?** pour cette quête. |
| 2 | Ferme l'onglet **sans** cliquer sur « Terminer la quête » | La lecture continue ; la quête n'est pas rendue (tu peux donc réécouter et tester). |
| 3 | Rouvre l'onglet de la même quête, puis clique sur « Terminer la quête » | La fin repart du début, à sa place dans la liste ; le clic sur « Terminer » ne la relance pas une troisième fois. |
| 4 | Pendant qu'une quête se lit, ouvre l'onglet de fin d'une autre quête | Elle s'ajoute dans la liste (**?**) et se lit ensuite. |
| 5 | `/fs turnin off`, ouvre un onglet de fin de quête | Rien ne se lit. `/fs turnin on` pour remettre. |

**À me renvoyer** : OK ou ce qui cloche pour chaque étape, puis « fait ». Je lis `ForeverSpeechDB.trace` (lignes
`turn-in: reward panel`).

**Résultat (2026-10-07)** : validé en jeu après les deux correctifs ci-dessus.

## T13 — Texte de la quête dans l'onglet Quête

**Livré** (2026-10-07) : le lecteur affiche le texte de la quête en petit, couleur parchemin, entre le modèle et
les objectifs ; la fenêtre grandit pour le contenir (14 lignes au plus, « … » au-delà). Réglage « Afficher le texte
de la quête » dans Options (activé par défaut). Le texte vient toujours du jeu : la capture faite chez le PNJ, sinon
le journal de quêtes ; pour une fin de quête, le texte de rendu capturé. Pas d'italique : le client n'a pas de
police italique.

| # | Action | Attendu |
|---|---|---|
| 1 | `/reload`, puis ▶ sur une quête du suivi | Le texte de la quête s'affiche en petit sous le modèle ; objectifs et récompenses dessous, sans chevauchement. |
| 2 | Ouvre l'onglet « Terminer la quête » d'une quête finie | Le lecteur montre le texte de rendu (celui affiché par le PNJ). |
| 3 | Options, décoche « Afficher le texte de la quête », reviens sur Quête | Le texte disparaît et la fenêtre reprend sa taille compacte. |
| 4 | Une quête au texte long (ou Options → Quête plusieurs fois) | Le texte s'arrête à 14 lignes avec « … » ; rien ne déborde de la fenêtre ; Options : la dernière ligne ne touche pas le pied de page. |

**À me renvoyer** : OK ou ce qui cloche par étape (une capture d'écran aide pour la mise en page).

**Résultat (2026-10-07)** : validé en jeu (texte affiché, mise en page correcte).

## T14 — Journal de bord : la fenêtre suit la quête suivie

**Livré** (2026-10-10) : quand la liste de lecture n'a plus rien à lire (dernière quête finie, Avancer sur la
dernière, Vider), la fenêtre revient à la **quête suivie** ; hors lecture, elle suit chaque changement de quête
suivie. Pendant une lecture, la pause entre deux quêtes ou après Stop, elle reste sur la quête lue. Elle ne s'ouvre
pas d'elle-même et ne change pas d'onglet ; fermée, elle s'ouvre sur la quête suivie. Réglage « Hors lecture,
afficher la quête suivie » dans Options (activé par défaut).

**Quête suivie** : celle mise en avant dans le suivi d'objectifs (`C_SuperTrack.GetSuperTrackedQuestID`), sinon la
première du suivi (`C_QuestLog.GetQuestIDForQuestWatchIndex(1)`). **Non vérifié sur Forever** : les deux viennent
de Retail, ainsi que l'événement `SUPER_TRACKING_CHANGED` (les événements du journal rattrapent le changement s'il
manque).

| # | Action | Attendu |
|---|---|---|
| 1 | Lance le jeu (lancement complet : T16 ajoute des fichiers), puis `/dump C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID()` | L'ID de la quête mise en avant (ou `0` si aucune) ; `nil` si l'API n'existe pas. |
| 2 | `/dump C_QuestLog.GetQuestIDForQuestWatchIndex(1)` | L'ID de la première quête du suivi d'objectifs. |
| 3 | ▶ sur une quête du suivi, laisse la lecture aller au bout | Dès la fin de l'audio, la fenêtre passe à la quête suivie (titre, objectifs en direct, récompenses). |
| 4 | Sans rien lire, change la quête mise en avant (clic sur une autre quête du suivi, ou sur la carte) | La fenêtre passe à la nouvelle quête. Dis-moi comment on met une quête en avant sur Forever. |
| 5 | ▶ sur une quête, et pendant la lecture change la quête mise en avant | La fenêtre reste sur la quête lue, puis passe à la quête suivie à la fin de l'audio. |
| 6 | Hors lecture, clic sur une ligne de la liste de lecture | La fenêtre montre cette quête et la garde tant que la quête suivie ne change pas. |
| 7 | Ferme la fenêtre, change la quête suivie, rouvre-la (minimap ou `/fs`) | Elle ne s'est pas rouverte seule ; rouverte, elle montre la quête suivie. |
| 8 | Options, décoche « Hors lecture, afficher la quête suivie », refais l'étape 3 | La fenêtre reste sur la quête lue. Recoche ensuite. |

**À me renvoyer** : les valeurs des étapes 1 et 2, puis OK ou ce qui cloche pour les autres étapes. Je lis
`ForeverSpeechDB.trace` (lignes `frame: followed quest` et `frame: logbook`).

## T15 — « Terminer et lire »

**Livré** (2026-10-10) : un bouton « Terminer et lire » à côté de « Terminer la quête », comme « Accepter et lire ».
Il rend la quête par le bouton du jeu, qui vérifie le choix de la récompense, puis lit la fin de quête 2 s après le
rendu. Pour laisser le choix, la lecture dès l'ouverture de l'onglet « Terminer la quête » est maintenant
**désactivée par défaut**, et ton réglage actuel passe à désactivé une fois. Elle reste dans Options et
`/fs turnin on`.

**Non vérifié sur Forever** : les noms `QuestFrameCompleteQuestButton` et `QuestFrameCancelButton`, et l'appel de
`GetQuestReward` par le bouton « Terminer la quête ».

**Prérequis** : nouveaux fichiers dans le TOC (T16), donc **un lancement complet du jeu**.

| # | Action | Attendu |
|---|---|---|
| 1 | Parle à un PNJ qui attend une quête finie, jusqu'à l'onglet « Terminer la quête » | Le bouton « Terminer et lire » est à droite de « Terminer la quête » (ou juste au-dessus s'il manque de place) ; rien ne se lit tout seul. |
| 2 | Quête **avec récompense au choix** : clique « Terminer et lire » sans choisir | Le jeu demande de choisir une récompense ; rien ne se lit. |
| 3 | Choisis la récompense, clique « Terminer et lire » | La quête est rendue, puis 2 s après la fin est lue ; le lecteur montre le PNJ de rendu et un **?** devant le titre. |
| 4 | Rends une autre quête avec « Terminer la quête » (le bouton du jeu) | Rien ne se lit. |
| 5 | `/fs turnin on`, ouvre un onglet de fin de quête | La fin se lit 1 s après l'ouverture, comme avant. `/fs turnin off` pour revenir. |

**À me renvoyer** : OK ou ce qui cloche par étape (une capture d'écran de l'onglet aide pour la place du bouton).
Je lis `ForeverSpeechDB.trace` (lignes `turn-in:`).

## T16 — Voix du jeu des PNJ coupées

**Livré** (2026-10-10) : tant que l'audio est activé, les répliques d'origine des PNJ sont coupées : salutations
(« Bonjour, aventurier »), adieux, répliques agacées, salutations de marchand et voix uniques du lore. Ce sont
1 035 fichiers, tirés de la liste Wowhead Classic « NPC Greetings » en cache. Réglage « Couper les voix du jeu des
PNJ (salutations, adieux) » dans Options (activé par défaut) et `/fs npcvoices on|off` (`on` : voix du jeu
entendues). Les voix que Forever aurait ajoutées ne sont pas dans la liste.

**Non vérifié sur Forever** : `MuteSoundFile` et `UnmuteSoundFile` (API Retail). Sans elles, rien ne change et
`/fs npcvoices` le dit.

**Prérequis** : deux nouveaux fichiers dans le TOC (`data/game_voices.lua`, `core/game_voices.lua`), donc **un
lancement complet du jeu** ; un `/reload` ne suffit pas.

| # | Action | Attendu |
|---|---|---|
| 1 | Lance le jeu, puis `/dump type(MuteSoundFile), type(UnmuteSoundFile), #ForeverSpeechGameVoices.files` | `"function", "function", 1035` |
| 2 | Parle à un PNJ humain (garde, donneur de quête), puis éloigne-toi ou ferme la fenêtre | Ni salutation ni adieu. |
| 3 | `/fs npcvoices on`, recommence l'étape 2 | Le PNJ salue et dit au revoir comme avant. Puis `/fs npcvoices off`. |
| 4 | Parle à des PNJ d'autres races (nain, elfe de la nuit, gnome) et à un marchand | Silence. Note ceux qui parlent encore : nom du PNJ et zone. |
| 5 | Accepte une quête avec « Accepter et lire » | Notre lecture démarre normalement (2 s après). |

**À me renvoyer** : le résultat de l'étape 1, OK ou ce qui cloche pour les autres, et la liste des PNJ qui parlent
encore (étape 4).

**Premier essai (2026-10-10)** : `MuteSoundFile` existe, les 1 035 fichiers sont coupés au chargement (journal), mais
les PNJ saluent et disent au revoir comme avant. Diagnostic : spike [S10](spikes/S10-mute-npc-voices.md).

**Résultat (2026-10-10)** : la coupure marche pour les PNJ de Classic ; les PNJ ajoutés par Forever (quêtes 92xxx)
parlent encore, leurs voix ne sont pas dans la liste. Décision : garder tel quel (S10).

## T17 — Voix du jeu coupées seulement avec les PNJ à quête

**Livré** (2026-10-10, suite de T16 et S10) : les voix du jeu ne sont plus coupées en permanence, mais seulement
avec un PNJ qui a une quête pour toi : une quête à prendre, ou une quête de ton journal prête à rendre. Les autres
PNJ (marchands, gardes, maîtres sans quête pour toi) gardent leur voix. La coupure se décide **au survol** du PNJ,
car la salutation part dès le clic. Fenêtre ouverte, sa liste de quêtes décide ; la coupure dure encore 2 s après la
fermeture, pour l'adieu. Rappel : seules les voix des PNJ de Classic sont coupées, ceux ajoutés par Forever parlent
toujours (S10).

**Non vérifié sur Forever** : `C_QuestLog.IsQuestFlaggedCompleted`, `C_QuestLog.IsComplete`, `C_GossipInfo`,
l'unité `softinteract` et l'événement `PLAYER_SOFT_INTERACT_CHANGED` (tous protégés ; sans eux, l'index et le journal
suffisent).

**Prérequis** : `/reload`.

| # | Action | Attendu |
|---|---|---|
| 1 | Parle à un garde ou à un marchand de Classic (Hurlevent, Forgefer, Darnassus) | Il salue et dit au revoir. |
| 2 | Parle à un PNJ de Classic qui a une quête pour toi (point d'exclamation jaune) | Ni salutation ni adieu. |
| 3 | Rends une quête terminée à un PNJ de Classic (point d'interrogation jaune) | Ni salutation ni adieu. |
| 4 | Parle à un PNJ de Classic dont tu as déjà fait les quêtes | Il salue. |
| 5 | Parle à un maître de classe d'une autre classe que la tienne, deux fois | La première fois, la salutation peut manquer (l'index ne connaît pas la classe) ; la seconde, il salue. |

**À me renvoyer** : OK ou ce qui cloche par étape, avec le nom du PNJ. Je lis `ForeverSpeechDB.trace` (lignes
`game voices:` avec la raison : `hover npc=…`, `window`, `farewell`).

## T18 — Objectifs en barres de progression

**Livré** (2026-10-10) : dans le lecteur, sous le résumé des objectifs, chaque objectif de la quête (journal de
quêtes, en direct) a sa ligne : une **case à cocher** et une **barre de progression** avec l'objectif écrit dedans
(« Masque rouge : 3/12 » remplit un quart de la barre). Objectif fait : case cochée, barre grisée. Un objectif sans
compteur (« Parler à … ») reste vide jusqu'à ce qu'il soit fait. 5 objectifs au plus ; la fenêtre grandit au besoin.

**Non vérifié sur Forever** : les champs `numFulfilled` / `numRequired` des objectifs (sinon le « 3/12 » du texte
suffit) et `GetQuestProgressBarPercent` (objectifs en pourcentage).

**Prérequis** : `/reload`.

| # | Action | Attendu |
|---|---|---|
| 1 | Affiche une quête de ton journal avec un compteur (ex. « tuer 4 loups »), à moitié faite | Une barre à moitié remplie, le texte de l'objectif lisible dedans, case vide. |
| 2 | Avance l'objectif (tue un loup) avec la fenêtre ouverte | La barre avance aussitôt. |
| 3 | Termine un objectif | La case se coche et la barre devient grise, pleine. |
| 4 | Une quête à 3 objectifs ou plus, avec le texte de la quête affiché | Tout tient sans chevauchement ; les récompenses restent sous les barres. |
| 5 | Une quête qui n'est pas dans ton journal (ligne de la liste de lecture) | Le résumé seul, sans barre. |

**À me renvoyer** : OK ou ce qui cloche par étape ; une capture d'écran de la fenêtre aide pour la lisibilité
(couleurs, taille du texte dans la barre).

**Premier essai (2026-10-10)** : barre collée au résumé, case à cocher à peine visible, texte peu lisible, et barre
pleine pour « Atteindre une compétence de 20 en dépeçage », qui n'a pas de compteur. Corrigé : seule une barre avec
compteur (au moins 2 requis, « x/y » ou « % ») se remplit ; la barre s'arrête à 90 % de la largeur ; 10 px sous le résumé, lignes de 22 px espacées de 6 px,
case de 22 px, texte plus grand avec ombre au-dessus d'un ambre plus sombre, liseré ; fenêtre élargie à 420 px. Les
champs bruts de chaque objectif vont dans le journal (`frame: objective …`). À refaire.

## T19 — Elise, la narratrice (index v4)

**Livré** (2026-10-10, branche `session/2026-10-10-elise`) : une quête qu'aucun PNJ ne dit (donnée par un objet ou
un item, rendue à un objet) est lue par **Elise** (D9), voix ElevenLabs, fichiers dans
`addon/ForeverSpeech/audio/1000000/`. Index v4 : l'addon refuse un index v3 (et inversement).

**Prérequis** : la branche récupérée, et le dossier `addon/ForeverSpeech/audio/1000000/` copié depuis le PC (disque
externe) ; **redémarrage complet** du jeu (nouveaux fichiers).

| # | Action | Attendu |
|---|---|---|
| 1 | `/dump ForeverSpeechIndex.version, ForeverSpeechIndex.npcs[1000000]` | `4` et `{ name = "Elise" }`. |
| 2 | Une quête d'objet dont Elise a l'audio : par exemple, en Orneval, rendre « Le nettoyage selon Raene » (1028, fin) ; ou toute quête donnée par un panneau « Recherché » | La voix d'Elise (calme, féminine), pas la synthèse vocale du client. |
| 3 | La fenêtre du lecteur pendant cette lecture | L'icône de quête (pas de modèle 3D), « Elise » ou le nom de l'objet sous le titre, aucune erreur (BugSack). |
| 4 | Une quête de PNJ ordinaire | Inchangée : la voix Qwen du PNJ, son modèle 3D. |

**À relever** (agent du Mac) : les valeurs du `/dump`, les quêtes testées (ID), ce que l'utilisateur entend et voit à
chaque étape, et les erreurs éventuelles.

## T20 — Elise présente chaque zone à la première visite (index v5)

**Livré** (2026-10-11, branche `session/2026-10-11-elise-zones`) : la première fois que le personnage pose le pied
dans une zone (48 zones des deux continents, villes comprises), la présentation d'Elise passe dans la liste de
lecture, avec l'icône de carte (exploration). Jamais en vol (trajet en griffon) : elle attend l'atterrissage.
Automatique **seulement quand l'audio d'Elise existe** ; avant, `/fs zone` lit son texte avec la synthèse vocale du
client. Une zone entendue est retenue par personnage (`ForeverSpeechDB.zonesSeen`). Réglage « Elise présente chaque
zone à la première visite » (Options, activé par défaut), `/fs zone on|off`.

**Prérequis** : la branche récupérée ; **redémarrage complet** du jeu (nouveau fichier `core/zones.lua`) ; pour les
étapes 4 à 7, le dossier `addon/ForeverSpeech/audio/1000000/` copié depuis le PC (fichiers `<zone>_zone.ogg`) avec
`data/index.lua`. Sans eux, faire les étapes 1 à 3 seulement.

| # | Action | Attendu |
|---|---|---|
| 1 | `/dump ForeverSpeechIndex.version` puis `/fs zone where` (dans la Forêt d'Elwynn) | `5` ; `map 1429`, index `Forêt d'Elwynn (map)`. Une autre valeur de `map`, ou `(name)` : à relever (S12). |
| 2 | `/fs zone` | La présentation de la zone (synthèse vocale si pas d'audio, sinon la voix d'Elise) ; une ligne avec l'icône de carte dans la liste ; la fenêtre montre le nom de la zone, « Elise », l'icône de carte, « Exploration » et le texte. |
| 3 | Double-clic sur la ligne, puis le bouton Lecture de la fenêtre | La présentation repart du début ; aucune erreur (BugSack). |
| 4 | `/fs zone reset`, puis `/reload` dans une zone qui a son audio | Environ 6 s après le chargement, la voix d'Elise présente la zone. |
| 5 | À pied, entrer dans une zone voisine jamais entendue (par ex. Elwynn → Marche de l'Ouest) | Environ 3 s après le passage, sa présentation ; repasser la frontière dans l'autre sens ne relit pas Elwynn. |
| 6 | Prendre un griffon qui survole une zone jamais entendue, jusqu'à une autre zone jamais entendue | Rien pendant le vol ; à l'atterrissage (2 à 3 s), la présentation de la zone **d'arrivée** seulement. |
| 7 | Pendant la lecture d'une quête, entrer dans une zone jamais entendue | La présentation attend son tour dans la liste (après la quête). |

**À relever** (agent du Mac) : les valeurs de l'étape 1 dans 3 zones (dont une ville : Stormwind ou Ironforge, et une
zone avec une grotte ou une mine : l'intérieur donne-t-il encore la bonne zone ?), ce que l'utilisateur entend et voit
à chaque étape, les lignes `zones:` du journal (`ForeverSpeechDB.trace`, dans les SavedVariables), et les erreurs.

## T21 — Elise à chaque niveau gagné (index v6)

**Livré** (2026-10-11, branche `session/2026-10-11-elise-zones`) : 2 s après chaque niveau gagné (2 à 60), la réplique
d'Elise pour ce niveau passe dans la liste de lecture, icône de lumière sacrée (`Spell_Holy_HolyBolt`, non vérifiée
sur Forever). Automatique **seulement quand l'audio existe** ; avant, `/fs level <n>` lit son texte avec la synthèse
vocale. Réglage « Elise vous parle à chaque niveau gagné » (Options, activé par défaut), `/fs level on|off`.

**Prérequis** : la branche récupérée ; **redémarrage complet** (nouveau fichier `core/levels.lua`) ; pour l'étape 3,
les fichiers `addon/ForeverSpeech/audio/1000000/<niveau>_level.ogg` et `data/index.lua` copiés depuis le PC.

| # | Action | Attendu |
|---|---|---|
| 1 | `/dump ForeverSpeechIndex.version, UnitLevel("player")` puis `/fs level` | `6` et le niveau du personnage ; sa réplique (synthèse vocale sans audio) ; une ligne « Niveau N » avec l'icône dans la liste ; la fenêtre montre « Niveau N », « Elise », « Votre voyage » et le texte. |
| 2 | `/etrace`, filtre `LEVEL`, puis gagner un niveau | `PLAYER_LEVEL_UP` avec le nouveau niveau en premier argument. |
| 3 | Gagner un niveau dont l'audio existe (pendant ou hors d'une lecture de quête) | 2 s après, la voix d'Elise (ou à son tour, après la quête en cours). |

**À relever** (agent du Mac) : l'événement et ses arguments vus dans `/etrace`, ce que l'utilisateur entend et voit,
les lignes `levels:` du journal (`ForeverSpeechDB.trace`), et les erreurs.

## T22 — Réécouter la présentation d'une zone depuis la carte (2026-10-12)

**Livré** (branche `session/2026-10-12-completion`) : en haut à droite de la carte du monde, un bouton lecture quand
la carte affiche une zone qui a sa présentation par Elise ; clic : elle repart du début ; second clic : stop. Caché
sur un continent, une ville sans présentation, ou audio coupé.

**Prérequis** : redémarrage complet (nouveau fichier `ui/map_button.lua`).

| # | Action | Attendu |
|---|---|---|
| 1 | Ouvrir la carte sur la Forêt d'Elwynn | Le bouton lecture en haut à droite, à gauche des boutons de la fenêtre ; survol : « Forêt d'Elwynn ». |
| 2 | Cliquer, puis recliquer | La voix d'Elise, la fenêtre de l'addon sur la zone ; le bouton passe en stop ; le second clic arrête. |
| 3 | Passer la carte sur le continent, puis sur une autre zone | Le bouton disparaît sur le continent, revient sur la zone (celle affichée, pas celle où l'on est). |
| 4 | Afficher une zone jamais visitée (ni présentation entendue, ni brouillard levé) | Bouton grisé ; survol : « Explorez d'abord cette zone… » ; clic : rien. |
| 5 | Survoler le bouton d'une zone découverte | L'icône s'éclaircit, sans carré gris. |

**À relever** : la place du bouton (gêne-t-il un bouton du jeu ?), `/dump WorldMapFrame:GetMapID()` sur Elwynn
(attendu : 1429), `/dump #C_MapExplorationInfo.GetExploredMapTextures(1429)` (non vérifié : une zone explorée en
donne au moins un), la ligne `map: button installed` du journal, les erreurs.

## T23 — La fenêtre au cadre du jeu, la liste de lecture ouverte par la flèche (2026-10-13)

**Livré** (branche `session/2026-10-13-queue-toggle`) : la fenêtre prend le cadre des fenêtres du jeu, comme la carte
(`PortraitFrameTemplate` : bandeau de titre « ForeverSpeech », croix du jeu ; son portrait masqué, la bordure faite
pour une fenêtre sans portrait) ; sans ce modèle, l'ancien cadre. **Plus d'onglets** : un bouton Options
(engrenage du journal de quêtes de la carte, sinon celui de Classic) à gauche de la croix ouvre les options ; recliqué,
il revient à la quête. La liste de lecture fait partie de la fenêtre : ouverte, la fenêtre s'élargit (et grandit si la
liste a beaucoup de lignes) ; fermée, elle reprend sa largeur. **Le coin haut gauche reste fixe** : la liste s'ouvre
et se ferme à droite. On l'ouvre et la ferme par la flèche en bas à droite de la partie quête, le bouton de la carte (ses
textures copiées depuis `WorldMapFrame.SidePanelToggle`, sinon un bouton carré avec une flèche) ; survol : « Ouvrir /
Fermer la liste de lecture ».

**Prérequis** : `/reload` (aucun nouveau fichier).

| # | Action | Attendu |
|---|---|---|
| 1 | `/fs show` | Le cadre du jeu : bandeau « ForeverSpeech », sans portrait, croix du jeu, l'engrenage à sa gauche ; le contenu juste sous le bandeau, bordure sans trou en haut à gauche. |
| 2 | Survoler l'engrenage, cliquer, recliquer | Infobulle « Options » ; les options s'ouvrent (engrenage doré), infobulle « Revenir à la quête » ; le second clic revient à la quête. |
| 3 | Survoler la flèche en bas à droite de la partie quête | Le même bouton que sur la carte ; infobulle « Fermer la liste de lecture ». |
| 4 | Cliquer, puis recliquer | La liste disparaît puis revient ; **le coin haut gauche ne bouge pas** (la fenêtre s'élargit et se rétrécit par la droite). |
| 5 | Mettre 5 quêtes ou plus dans la liste ; passer aux options et revenir | La flèche ne masque ni l'argent, ni l'XP, ni la ligne d'info des options ; la fenêtre grandit si la liste dépasse sa hauteur ; le haut ne bouge pas. |
| 6 | `/reload` | La liste reste ouverte ou fermée comme avant ; la fenêtre revient au même endroit. |

**À relever** : les lignes `frame: PortraitFrameTemplate=…` et `frame: options button …` du journal (`/fs debug on`),
`/dump WorldMapFrame.SidePanelToggle ~= nil` et `/dump C_Texture.GetAtlasInfo("questlog-icon-setting") ~= nil` (non
vérifiés sur Forever : sinon, la flèche et l'engrenage de secours), une capture de la fenêtre liste ouverte et
fermée, les erreurs.

## T24 — Onglets sur le côté : mode pêche, saluer, remercier, s'asseoir (2026-10-13)

**Livré** (branche `session/2026-10-13-queue-toggle`) : de petits onglets collés au bord gauche de la fenêtre, à
l'extérieur (art des onglets du grimoire, retourné) ; le premier est la **pêche**. Clic : la canne des sacs est
équipée (armes retenues) ; reclic : les armes reviennent (la main gauche une demi-seconde après). La pêche se lance
depuis une barre d'action. Verrouillé en combat. **Onglet affiché seulement si le personnage connaît la pêche et a une
canne** (sacs ou main), et toujours en mode pêche (pour remettre les armes). `/fs fish` fait la même chose. Mode
retenu par personnage. **En bas de la même tranche**, trois boutons d'émote : **Saluer** (`HELLO`) et **Remercier**
(`THANK`), à la cible s'il y en a une, sinon à tout le monde ; **S'asseoir** (`SIT`).

**Prérequis** : **redémarrage complet du jeu** (quatre nouveaux fichiers : `core/fishing.lua`, `ui/side_tabs.lua`,
`ui/fishing_tab.lua`, `ui/emote_tabs.lua`) ; `/fs debug on` ; une canne à pêche dans les sacs, une arme (et un bouclier ou une arme en main
gauche) équipée.

| # | Action | Attendu |
|---|---|---|
| 1 | `/fs show` | Un onglet carré collé à gauche de la fenêtre, icône de pêche grisée ; survol : « Pêche », « Clic : équiper la canne à pêche. ». |
| 2 | Cliquer l'onglet | La canne est équipée ; l'onglet en couleur avec un cadre lumineux ; infobulle « Mode pêche activé ». |
| 3 | Pêcher depuis la barre d'action | La pêche marche avec la canne équipée par l'addon. |
| 4 | Recliquer l'onglet | L'arme et la main gauche reviennent ; l'onglet regrisé. |
| 5 | Mode pêche activé, entrer en combat ; cliquer l'onglet | Rien ne change ; survol : « Indisponible en combat » en rouge. Après le combat, l'onglet marche de nouveau. |
| 6 | Mettre la canne en banque (ou sur un personnage sans pêche) | L'onglet disparaît ; il revient avec la canne dans les sacs. |
| 7 | Mode pêche activé, `/reload` | Toujours en mode pêche ; reclic : les armes d'avant reviennent. |
| 8 | En bas à gauche de la fenêtre, à l'extérieur : survoler les trois boutons | « Saluer », « Remercier », « S'asseoir », rien d'autre ; en couleur (pas des interrupteurs). |
| 9 | Sans cible, cliquer Saluer puis Remercier | « Vous saluez tout le monde. », « Vous remerciez tout le monde. » (texte exact du jeu). |
| 10 | Cibler un joueur ou un PNJ, recliquer les deux | Le salut et le merci s'adressent à la cible. |
| 11 | Cliquer S'asseoir, puis avancer | Le personnage s'assoit, puis se relève en bougeant. |

**À relever** : les lignes `fishing: …` du journal (`equip …`, `on main=… off=…`, `off …`),
`/dump IsPlayerSpell(131474), IsPlayerSpell(7620), IsPlayerSpell(7731)` (lequel est le sort de pêche sur Forever),
les lignes `emote: …`, une capture de la fenêtre avec les onglets (les icônes conviennent-elles ?), les erreurs.

## T25 — L'or en bas de la fenêtre (2026-10-13)

**Livré** (branche `session/2026-10-13-queue-toggle`) : un bandeau en bas de la fenêtre, comme celui du sac à dos
(`ThinGoldEdgeTemplate`, sinon une bande sombre), sur toute la largeur (liste comprise) ; l'or du personnage à droite
(`GetMoney`, mis à jour par `PLAYER_MONEY`). La fenêtre grandit d'autant ; la flèche de la liste, la ligne d'info des
options et les boutons d'émote remontent au-dessus.

**Prérequis** : `/reload`.

| # | Action | Attendu |
|---|---|---|
| 1 | `/fs show` | Le bandeau en bas, le même cadre doré fin que sous le sac à dos ; l'or à droite (pièces d'or, d'argent, de cuivre). |
| 2 | Acheter ou vendre quelque chose | Le montant change aussitôt. |
| 3 | Fermer la liste, passer aux options | Le bandeau suit la largeur ; rien ne le chevauche (flèche, ligne d'info). |

**À relever** : la ligne `frame: footer ThinGoldEdgeTemplate=…` du journal, une capture du bas de la fenêtre.

## T26 — Niveau des quêtes, Féliciter, niveau et temps de jeu en bas de la fenêtre (2026-10-14)

**Livré** (branche `session/2026-10-14-quest-level`) :
- **titre de la quête** écrit comme dans le suivi d'objectifs : `[12] Titre`, dans la couleur de sa difficulté
  (gris, vert, jaune, orange, rouge). Niveau : celui du journal de quêtes (`C_QuestLog.GetInfo(index).level`), sinon
  celui de l'index (v7, la Forever Database). Couleur : la fonction du jeu `GetQuestDifficultyColor`, sinon les règles
  de Classic (rouge à +5, orange à +3, jaune de −2 à +2, vert jusqu'au niveau gris). Au niveau gagné, la couleur suit ;
- **Féliciter** (`CONGRATULATE`), quatrième bouton d'émote en bas à gauche, icône de feu d'artifice ;
- **bandeau du bas, à gauche** : « Niveau 12 », puis une montre et le **temps de jeu à ce niveau**, qui tourne
  (`RequestTimePlayed` à l'entrée en jeu et à chaque niveau gagné ; la réponse `TIME_PLAYED_MSG` n'est pas écrite dans
  le chat pour ces demandes-là ; un `/played` tapé s'affiche comme d'habitude). **Au niveau 60** (le dernier :
  `GetMaxPlayerLevel`, sinon 60), le niveau seul : plus de chrono ni de demande.

**Prérequis** : **redémarrage complet du jeu** (nouveau fichier `core/played.lua`) ; l'index régénéré (v7 : sans lui,
l'addon refuse l'index) ; `/fs debug on`.

| # | Action | Attendu |
|---|---|---|
| 1 | Ouvrir une quête dans la fenêtre (▶ du journal) | Le titre est `! [n] Titre`, coloré comme la même quête dans le suivi d'objectifs (comparer la couleur). |
| 2 | Parler à un PNJ, ouvrir une quête pas encore prise (« Accepter et lire ») | Le niveau entre crochets aussi (celui de l'index) ; la couleur cohérente avec l'écart de niveau. |
| 3 | Une quête bien plus haute et une quête grise du journal | Rouge ou orange pour la première, gris pour la seconde, comme dans le journal. |
| 4 | Une présentation de zone ou une réplique de niveau d'Elise | Le titre sans crochets. |
| 5 | Survoler les boutons en bas à gauche, cliquer Féliciter sans cible puis avec une cible | Quatre boutons, le dernier « Féliciter » ; « Vous félicitez tout le monde. », puis la cible (texte exact du jeu). |
| 6 | Se connecter, `/fs show` | Pas de message « Temps de jeu total » dans le chat ; en bas à gauche « Niveau n », une montre et un temps qui avance chaque seconde. |
| 7 | Taper `/played` | Le message du jeu s'affiche dans le chat comme d'habitude ; le temps du bandeau correspond à « Temps de jeu à ce niveau ». |
| 8 | Gagner un niveau, fenêtre ouverte | « Niveau n+1 » ; le temps repart de 0:00 (après la réponse du serveur) ; la couleur du titre suit le nouveau niveau. |
| 9 | Un personnage de niveau 60, `/fs show` | « Niveau 60 » seul, sans montre ni temps ; `/dump GetMaxPlayerLevel and GetMaxPlayerLevel()` (60 attendu). |

**À relever** : les lignes `frame: quest=… level=… source=… difficulty=…` et `played: …` du journal, une capture du
haut et du bas de la fenêtre, `/dump GetQuestDifficultyColor ~= nil, QuestDifficultyColors ~= nil`, les erreurs.

## T27 — Journal des compagnons (2026-10-15, D18)

**Livré** (branche `session/2026-10-14-companions`) : le temps passé en groupe avec chaque joueur (groupe, ou son
sous-groupe en raid ; jamais en champ de bataille ; seulement connecté ; compté après 5 min ensemble), une table de
100 par personnage, un palier d'amitié, des statistiques ; un **onglet sur le côté** (icône de Prière de robustesse)
ouvre le panneau « Compagnons » (top 10, clic sur un nom : ses statistiques) ; **deux lignes dans l'infobulle** d'un
compagnon ; une ligne dans le chat à chaque palier franchi ; **Elise** dit une réplique du palier (seulement avec son
audio, pas encore fait : `/fs friends say <palier>` la fait lire par la synthèse vocale). Critères :
[companions.md](companions.md).

**Prérequis** : **redémarrage complet du jeu** (nouveaux fichiers `core/companions.lua`, `ui/companions_panel.lua`) ;
l'index régénéré (v8) ; `/fs debug on` ; un ami pour grouper.

| # | Action | Attendu |
|---|---|---|
| 1 | `/fs show` | Un onglet de plus collé à gauche (sous la pêche si elle est là) ; survol : « Compagnons », « Les joueurs avec qui vous groupez le plus. » |
| 2 | Cliquer l'onglet | Le panneau « Compagnons » : « En groupe : 0 min · 0 compagnon(s) », le texte « Personne pour l'instant… » ; l'onglet allumé. Recliquer : retour à la quête. |
| 3 | Grouper avec un joueur, rester 6 min ensemble | Dans le chat : « Rencontre : <nom>. » ; `/fs friends` : « 1. <nom>, Rencontre, 5 min, 1 groups ». |
| 4 | Survoler le joueur (cadre de groupe et dans le monde) | Deux lignes de plus en bas de l'infobulle : « Rencontre · 6 min ensemble », « 1 groupe(s) · 0 % de votre temps de jeu ». |
| 5 | Panneau, cliquer sur son nom | Ses statistiques : temps, parts, groupes, plus longue session, première rencontre (date, zone, niveau), dernière fois, ensemble (donjons, quêtes, niveaux). |
| 6 | Rendre une quête ensemble ; entrer dans un donjon ensemble | « Ensemble : 1 donjon(s), 1 quête(s) rendue(s)… » |
| 7 | `/reload` en groupe, puis `/fs friends` | Toujours 1 groupe (le même groupe continue), le temps continue. |
| 8 | Le joueur se déconnecte 2 min sans quitter le groupe | Son temps n'avance pas pendant ces 2 min. |
| 9 | `/fs friends say good_friend` | Elise lit une réplique « Bon ami » (synthèse vocale) ; la fenêtre la titre « Bon ami » avec l'icône des compagnons. |

**À relever** : les lignes `companions: …` du journal (`joined`, `group counted`, `left`, `resumed`, `tooltip hook
…`), `/dump GetNumSubgroupMembers(), UnitGUID("party1"), UnitIsConnected("party1")`, une capture du panneau et d'une
infobulle, les erreurs.

## T28 — La présentation de zone attend 2 minutes dans la zone (2026-10-15)

**Livré** (branche `session/2026-10-15-zone-intro-delay`) : la présentation d'une zone par Elise ne part plus 3 s
après l'arrivée, mais **après 2 minutes passées dans la zone** (au sol) ; chaque nouvelle zone, connexion ou
atterrissage relance l'attente ; si une cinématique ou une vidéo joue encore à ce moment-là (`InCinematic`,
`CinematicFrame`, `MovieFrame` : non vérifiés), elle attend sa fin.

**Prérequis** : `/reload` ; `/fs debug on` ; un nouveau personnage (cinématique d'ouverture), ou `/fs zone reset`.

| # | Action | Attendu |
|---|---|---|
| 1 | Nouveau personnage : laisser la cinématique d'ouverture jusqu'au bout | Rien d'Elise pendant la cinématique ; sa présentation de la zone environ 2 min après l'entrée en jeu (ou dès la fin de la cinématique si elle dure plus). |
| 2 | `/fs zone reset`, entrer dans une autre zone, en ressortir avant 2 min | Rien. |
| 3 | Rester 2 min dans une zone jamais entendue | La présentation part. |
| 4 | Vol en griffon vers une zone jamais entendue | Rien en vol ; la présentation 2 min après l'atterrissage. |

**À relever** : les lignes `zones: …` du journal (`a cinematic plays, waiting for its end`, `first visit of …`),
`/dump InCinematic and InCinematic()` pendant la cinématique d'ouverture, les erreurs.

## T29 — La fenêtre d'options (2026-10-15)

**Livré** (branche `session/2026-10-15-options-window`) : les options quittent la fenêtre principale pour une fenêtre
à part, au cadre du jeu : **sept thèmes à gauche** (Général, Lecture des quêtes, Fenêtre de quête, Elise,
Compagnons, Confort, Avancé), leurs réglages à droite. Ouverte par l'engrenage, le clic droit sur l'icône de la
minimap ou `/fs options [thème]` ; déplaçable, position et dernier thème retenus. Nouveaux interrupteurs : niveau de
la quête dans le titre, bandeau du bas, cadrage du modèle (4 cadrages), suivi, infobulle et annonces des compagnons,
onglet de pêche, émotes, bouton de la carte ; boutons « Réentendre toutes les zones » et « Réinitialiser les options ».

**Prérequis** : **redémarrage complet du jeu** (nouveau fichier `ui/options_frame.lua`) ; `/fs debug on`.

| # | Action | Attendu |
|---|---|---|
| 1 | `/fs show`, cliquer l'engrenage | Une fenêtre « ForeverSpeech · Options » au cadre du jeu ; la fenêtre principale garde sa taille ; l'engrenage allumé. Recliquer : elle se ferme. |
| 2 | Cliquer chaque thème à gauche | Le thème surligné, ses réglages à droite ; les icônes des thèmes s'affichent (pas de carré vert). |
| 3 | Clic droit sur l'icône de la minimap ; `/fs options elise` | La fenêtre s'ouvre ; sur le thème Elise pour la commande. |
| 4 | Déplacer la fenêtre, la fermer, `/reload`, la rouvrir | Même place, même thème. |
| 5 | Fenêtre de quête : décocher « Niveau de la quête… », puis « Bandeau du bas… » | Le titre perd `[n]` aussitôt ; le bas gauche du bandeau se vide. |
| 6 | Fenêtre de quête : cliquer le cadrage plusieurs fois | Le modèle du PNJ passe du corps entier au visage. |
| 7 | Confort : décocher les boutons d'émote, puis le bouton de la carte | Les émotes disparaissent du bord gauche ; le bouton disparaît de la carte. |
| 8 | Général : décocher « Audio activé », puis clic gauche sur l'icône de la minimap | La fenêtre d'options s'ouvre (pas la fenêtre principale) ; recocher : l'audio revient. |
| 9 | Avancé : « Réinitialiser les options » une fois, attendre 4 s ; puis deux fois | Le bouton dit « Confirmer ? » puis revient ; au deuxième clic, les cases reviennent par défaut, l'icône de la minimap ne bouge pas. |

**À relever** : la ligne `options: PortraitFrameTemplate=… BackdropTemplate=…` du journal, une capture de la
fenêtre, les erreurs.

## T30 — Les icônes peintes des onglets sur le côté (2026-10-15)

**Livré** (branche `session/2026-10-15-tab-icons`) : les six onglets du bord gauche (Pêche, Compagnons, Saluer,
Remercier, S'asseoir, Féliciter) prennent des icônes peintes pour l'addon, à la manière des icônes du jeu, à la place
d'icônes du jeu qui ne disaient pas ce qu'elles font : `media/tabs/<clé>.tga` (64×64, TGA 32 bits non compressé,
origine en bas comme `media/icon.tga`). Originaux : `data/icons/tabs/*.png` (non versionnés ; Gemini 3 Pro Image par
OpenRouter), conversion : `tools/tab_icons.sh`.

**Prérequis** : **redémarrage complet du jeu** (nouveaux fichiers `.tga`, S2).

| # | Action | Attendu |
|---|---|---|
| 1 | `/fs show`, regarder le bord gauche de la fenêtre | Les onglets montrent les nouvelles icônes (main gantée, main sur le cœur, aventurier au feu de camp, mains qui applaudissent, poignée de main, canne et bouchon) ; aucun carré vert ni noir ; aucune image à l'envers. |
| 2 | Onglet de pêche éteint, puis allumé ; survoler chaque onglet | Grisé éteint, en couleur allumé, comme avant ; le reflet du survol et le cadre doré par-dessus l'icône. |
| 3 | Comparer à 32 px avec les onglets du grimoire | Les icônes s'accordent au jeu (lisibles, pas floues, pas de bord blanc). |

**À relever** : une capture du bord gauche, l'avis (à garder, à refaire), les erreurs.

## T31 — Le portrait d'Elise dans la fenêtre de lecture (2026-10-15)

**Livré** (branche `session/2026-10-15-elise-model`) : quand Elise parle (une quête qu'aucun PNJ ne dit, une
présentation de zone, une réplique de niveau ou de palier de compagnon), la fenêtre affiche **son portrait peint**
(`media/elise.tga`, 256×256, recadré au format du modèle) à la place de l'icône de quête ou de réplique. Si le client
refuse le fichier (`SetTexture` renvoie `false`), l'icône revient. La liste de lecture garde les icônes des répliques.

**Prérequis** : **redémarrage complet du jeu** (nouveau fichier `media/elise.tga`) ; `/fs debug on`.

| # | Action | Attendu |
|---|---|---|
| 1 | `/fs level 12` | La fenêtre s'ouvre sur la réplique du niveau 12 : le portrait d'Elise remplit le cadre du modèle, à l'endroit, non étiré, couleurs justes (pas de carré vert ni noir) ; dans la liste, la ligne garde l'icône de lumière sacrée. |
| 2 | `/fs zone 1429` | Même portrait pour la présentation de la Forêt d'Elwynn ; l'icône de carte reste dans la liste. |
| 3 | `/fs show 176` (« On recherche : « Lardeur » », donnée par l'affiche, lue par Elise) | Le portrait d'Elise, pas l'icône de quête ; sous le titre, « Elise » ou le nom de l'affiche. |
| 4 | `/fs show` sur une quête de PNJ ordinaire, juste après | Le modèle 3D du PNJ revient, le portrait disparaît. |
| 5 | `/dump ForeverSpeechDB.trace` (fin) | Une ligne `frame: portrait speaker=1000000 ok=true set=…` : noter la valeur de `set` (`true`, `nil` ou `false`). |

**À relever** : une capture de la fenêtre aux étapes 1 et 4, la valeur de `set`, les erreurs (BugSack).

## T32 — « Accepter et lire » et « Terminer et lire » vérifient le journal de quêtes (2026-10-15)

**Livré** (branche `session/2026-10-15-accept-in-log`) : la lecture ne part plus sur le seul identifiant de la quête.
Après « Accepter et lire » (et l'Accepter du jeu avec `/fs autoplay on`), elle attend que la quête soit **dans le
journal** ; après « Terminer et lire », que la quête l'ait **quitté**. Vérifié à 2 s, puis toutes les 0,5 s pendant
3 s ; sinon rien n'est lu et le chat affiche « quête absente du journal (non acceptée) » ou « quête toujours dans le
journal (non rendue) ».

**Prérequis** : `/reload` (aucun nouveau fichier) ; `/fs debug on`.

| # | Action | Attendu |
|---|---|---|
| 1 | « Accepter et lire » sur une quête ordinaire | La lecture démarre 2 s après, comme avant. |
| 2 | Journal plein (20 quêtes), puis « Accepter et lire » sur une nouvelle quête | Le jeu refuse ; rien n'est lu ; dans le chat, « quête absente du journal (non acceptée) : pas de lecture. » |
| 3 | « Terminer et lire » sur une quête rendue normalement | La fin est lue 2 s après le rendu. |
| 4 | Sacs pleins, une récompense d'objet obligatoire, « Terminer et lire » | Le jeu refuse le rendu ; rien n'est lu ; dans le chat, « quête toujours dans le journal (non rendue) … ». |

**À relever** : les lignes `accept: quest=… inLog=… wanted=… after …s` du journal (`/dump ForeverSpeechDB.trace`),
ce qui est lu ou non à chaque étape, les erreurs. Pour le cas qui t'a montré le bogue : la quête et ce que le jeu a
affiché.

## T33 — En groupe, annoncer les quêtes terminées (2026-10-17)

**Livré** (branche `session/2026-10-17-quest-announce`, `core/announce.lua`, idée reprise de Questie, sans son code) :
en groupe seulement, quand **tous les objectifs** d'une quête du journal passent de « à faire » à « faits » pendant la
session, une ligne dans le chat : `{rt1} J'ai terminé « Titre » : Objectif 1 : 6/6 ; Objectif 2 : 1/1.` (255 octets au
plus). Une seule fois par quête et par session ; jamais pour une quête déjà faite à la connexion. Canal **Groupe** par
défaut (groupe, raid ou instance : la bulle s'affiche aux membres du groupe, réglage du jeu « bulles du groupe »), ou
**Dire (/s)** pour la bulle visible de tous. Options > Confort ; `/fs announce [questID|on|off|party|say]` (sans
argument : la quête suivie, tout de suite).

**Hypothèse** : un addon peut écrire en `/s` hors instance sans clic du joueur ? Sur Classic depuis 1.13.3, non (le jeu
bloque l'envoi). Questie n'écrit que dans le canal de groupe, sans doute pour cette raison.

**Prérequis** : **redémarrage complet du jeu** (nouveau fichier `core/announce.lua`) ; `/fs debug on` ; un ami pour
grouper.

| # | Action | Attendu |
|---|---|---|
| 1 | Seul, `/fs announce` | Dans le chat de l'addon : « announce (not in a group, shown here only) : {rt1} J'ai terminé « … » : … » ; rien d'envoyé. |
| 2 | En groupe, finir le dernier objectif d'une quête | Dans le canal de groupe, l'étoile puis « J'ai terminé « Titre » : … » ; une bulle au-dessus de ton personnage chez ton ami. |
| 3 | Continuer à tuer ou ramasser pour la même quête, `/reload` | Pas de deuxième annonce, même après le `/reload` (la quête est déjà faite à la connexion). |
| 4 | Options > Confort, canal « Dire (/s) », puis finir une autre quête en groupe, dehors | Soit la ligne en `/s` avec sa bulle pour tous, soit le message « annonce en /s bloquée par le jeu … » (et rien d'envoyé). |
| 5 | Décocher « En groupe, annoncer les quêtes terminées… », finir une quête | Rien d'envoyé. |

**À relever** : les lignes `announce: …` du journal (`/dump ForeverSpeechDB.trace`), le texte exact reçu par ton ami et
s'il voit la bulle, le résultat de l'étape 4 (envoyé ou bloqué), les erreurs.

## T34 — Mettre en avant les quêtes dont je suis dans la zone (2026-10-18)

**Livré** (branche `session/2026-10-18-quest-area`, `core/quest_area.lua`) : chaque seconde, si tu as bougé, l'addon
demande au jeu de quelles quêtes tu es dans la zone (la tache des objectifs sur la minimap et la carte ; méthode
vérifiée en H16). Ces quêtes ressortent **dans le suivi d'objectifs** (barre dorée derrière le titre, fond doré sur les objectifs, trait doré foncé à droite ; renforcé le 2026-10-18 : la barre seule était trop pâle) et **dans le journal de quêtes** (barre dorée sur la ligne du titre). Options > Confort, « Mettre en avant les
quêtes dont je suis dans la zone », activé par défaut ; `/fs area` dit dans le chat les quêtes trouvées.

**Prérequis** : **redémarrage complet du jeu** (nouveau fichier `core/quest_area.lua`) ; plusieurs quêtes dans le
journal, dont au moins deux avec une zone dans la même région.

| # | Action | Attendu |
|---|---|---|
| 1 | Entrer dans la zone d'une quête (tache sur la minimap) | Dans la seconde, son bloc dans le suivi a le fond doré et le trait à droite ; `/fs area` donne son titre. |
| 2 | Ouvrir le journal (L) | La ligne de cette quête a la barre dorée ; les autres non. |
| 3 | Sortir de la zone | La mise en avant disparaît dans la seconde (suivi et journal). |
| 4 | Là où deux zones se chevauchent | Les deux quêtes ressortent. |
| 5 | Options > Confort, décocher la case | Plus rien ne ressort ; recochée : la mise en avant revient. |
| 6 | Courir quelques minutes en jouant normalement | Pas de saccade, pas d'erreur. |

**À relever** : les lignes `quest area: …` du journal (`/dump ForeverSpeechDB.trace`), l'aspect de la barre et de la
flèche (une capture d'écran), les erreurs.

**Résultat (2026-10-18)** : la mise en avant marche dans le suivi et dans le journal (Forêt d'Elwynn, « L'échange de
poussière d'or » et « Les bougies de kobolds » dans leur zone). Rendu du suivi réglé avec le joueur en trois essais :
la barre seule était trop pâle ; trait jaune foncé à droite, sans flèche ; validé après `/reload`. Étapes 4 à 7 non
relevées.

## T35 — Blason de niveau de la quête (2026-10-18)

**Livré** (branche `session/2026-10-18-quest-level-badge`) : à la place de `[10]` dans le titre, un **blason** (108 pixels)
centré dans l'espace libre à droite des boutons Lecture / Avancer / Stop (2026-10-18 ; essayé d'abord à gauche du
titre en 40 pixels, puis collé aux boutons en 64 : trop petit), un par difficulté (gris : écu de bois ; vert : écu de fer ; jaune : épées croisées ;
orange : cornes et ailes ; rouge : crâne, haches et flammes), plus grand et plus orné à mesure que la quête est
dangereuse ; le **niveau** écrit au centre, dans la couleur de la difficulté, contour noir épais. Le titre reste dans
sa couleur dorée et à sa place. Images : `media/difficulty/*.tga` (128 × 128,
découpées par `tools/difficulty_badges.ts` dans la planche peinte). Si le jeu refuse l'image : `[10]` coloré dans le
titre, comme avant.

**Aussi** : le bandeau du bas n'affiche plus que « Niveau n » : plus de montre ni de temps de jeu (retirés le
2026-10-18, l'addon sert à profiter de l'histoire) ; le temps de jeu total est toujours demandé à la connexion, hors
du chat, pour le journal des compagnons.

**Prérequis** : **redémarrage complet du jeu** (images `media/difficulty/*.tga` refaites) ; `/fs debug on`.

| # | Action | Attendu |
|---|---|---|
| 1 | Ouvrir une quête du journal dans la fenêtre (▶) | Le blason à gauche du titre, détouré (pas de carré ni de liseré rose), le niveau lisible au centre, de la même couleur que la quête dans le suivi d'objectifs. |
| 2 | Comparer une quête grise, verte, jaune, orange et rouge (journal, ou `/fs show <questID>`) | Cinq blasons différents, du plus simple (gris, plus petit) au plus menaçant (rouge, crâne). |
| 3 | Une quête de niveau 10 ou plus | Les deux chiffres tiennent sur la plaque sombre, lisibles. |
| 4 | Une présentation de zone ou une réplique de niveau d'Elise, puis revenir à une quête | Pas de blason pour Elise ; il revient avec la quête. Le blason ne touche ni l'état (« À l'arrêt ») ni le texte de la quête sous le modèle. |
| 5 | Options > Fenêtre de quête, décocher « Niveau de la quête » | Plus de blason ; recoché, il revient. |
| 6 | Gagner un niveau, fenêtre ouverte | Le blason et la couleur du chiffre suivent (ex. orange → jaune) ; en bas, « Niveau n+1 », sans temps. |
| 7 | Se connecter | En bas à gauche « Niveau n » seul ; pas de message « Temps de jeu total » dans le chat. |

**À relever** : une capture d'écran du haut de la fenêtre pour deux ou trois couleurs, les lignes `frame: quest=…
difficulty=…` du journal (`/dump ForeverSpeechDB.trace`), les erreurs.

## T36 — Onglets du sac à dos : le désenchantement (2026-10-18)

**Livré** (branche `session/2026-10-18-disenchant-tab`) : une barre d'onglets sur le côté gauche du sac à dos, comme
celle de la fenêtre. Premier onglet : **Désenchanter** (icône du sort), seulement pour un personnage qui connaît le
désenchantement. **Clic : le sort est lancé comme depuis le grimoire** (le curseur attend l'objet) ; tant qu'il attend,
une **bordure dorée** sur chaque objet des sacs qui se désenchante (selon son infobulle : « Peut être désenchanté »
ou « Désenchantement : … requis ») et l'onglet est allumé. Le clic sur l'objet est celui du jeu.
Retiré en combat. Réglage dans Options > Confort ; `/fs disenchant` dit combien d'objets se désenchantent.

**Prérequis** : `/reload` ; `/fs debug on` ; un enchanteur avec, dans ses sacs, un objet vert à sacrifier (une
récompense de quête de Forever convient), un objet blanc et, si possible, un objet marqué « Ne peut pas être
désenchanté ».

| # | Action | Attendu |
|---|---|---|
| 1 | Ouvrir le sac à dos (B) | Un onglet carré collé à gauche du sac, icône de désenchantement grisée ; survol : « Désenchantement », « Clic : lancer le sort… », « N objet(s) à désenchanter dans vos sacs. » Sur un personnage sans enchantement : pas d'onglet. |
| 2 | `/fs disenchant` | « N objet(s) à désenchanter dans vos sacs. » |
| 3 | Cliquer l'onglet | Le curseur attend un objet (comme après un clic sur le sort du grimoire) ; l'onglet allumé ; une bordure dorée sur les seuls objets dont l'infobulle dit « Peut être désenchanté » (ou une compétence requise) ; pas sur le blanc, ni sur « Ne peut pas être désenchanté ». |
| 4 | Cliquer un objet en surbrillance | Le personnage le désenchante (barre d'incantation, butin) ; les bordures disparaissent, l'onglet se regrise. |
| 5 | Recliquer l'onglet, puis Échap | Les bordures apparaissent, puis disparaissent à Échap. |
| 6 | Entrer en combat | L'onglet disparaît ; il revient après le combat. Le sac s'ouvre et se ferme normalement en combat (pas d'erreur « action bloquée »). |
| 7 | Fermer le sac, rouvrir, ouvrir aussi les autres sacs ; cliquer l'onglet | L'onglet reste sur le sac à dos ; les bordures dans tous les sacs ouverts. |
| 8 | Options > Confort, décocher « Onglet du désenchantement » | L'onglet disparaît ; recoché, il revient. |

**À relever** : après `/reload`, je lis `ForeverSpeechDB.disenchantCheck` (chaque objet, sa qualité, ce que dit son
infobulle) et `disenchantCheckSource` ; une capture du sac pendant la visée, les erreurs (BugSack).

## T37 — Le détail des compagnons à la place de la liste de lecture (2026-10-18)

**Livré** (branche `session/2026-10-18-disenchant-tab`) : dans la vue Compagnons, le cadre de droite (celui de la liste
de lecture) montre le compagnon cliqué ; la liste des compagnons a toute la hauteur ; de retour à la quête, la liste de
lecture revient comme avant.

**Prérequis** : `/reload` ; au moins deux compagnons dans le journal (`/fs friends`).

| # | Action | Attendu |
|---|---|---|
| 1 | Fenêtre ouverte sur une quête, liste de lecture ouverte (flèche en bas à droite) | La liste de lecture à droite, comme avant. |
| 2 | Clic sur l'onglet Compagnons | À gauche, le top 10 sur toute la hauteur, rien sur le bandeau « Niveau … » ; à droite, à la place de la liste, un cadre « Compagnons » avec « Cliquez sur un nom pour voir vos statistiques ensemble. » ; plus de flèche en bas à droite. |
| 3 | Clic sur le 1er compagnon | Sa ligne surlignée en doré ; à droite : son nom (couleur de classe), son palier en doré, puis une statistique par ligne (temps ensemble, parts du temps de jeu et du temps en groupe, groupes, plus longue session, rencontre, dernière fois, donjons/quêtes/niveaux) ; les lignes longues passent à la ligne sans déborder. |
| 4 | Clic sur le 2e compagnon | Le détail passe au 2e ; seule sa ligne est surlignée. |
| 5 | Recliquer l'onglet Compagnons (retour à la quête) | La liste de lecture revient à droite, la flèche aussi. |
| 6 | Fermer la liste (flèche), rouvrir Compagnons, revenir à la quête | Dans Compagnons, le détail du 2e est toujours là (même liste fermée) ; de retour à la quête, la liste reste fermée. |
| 7 | Rouvrir la liste (flèche) | La liste revient, la fenêtre s'élargit. |

**À relever** : une capture de la vue Compagnons avec un compagnon choisi, les erreurs (BugSack).

## T38 — Le sac à dos déplaçable (2026-10-20)

**Livré** (branche `session/2026-10-20-bag-frame-move`) : le sac combiné se déplace en le faisant glisser par son bord
ou son titre (clic gauche maintenu ; les objets gardent leur propre glisser). Sa place est retenue (`ForeverSpeechDB.bagPos`,
pour tout le compte) et remise chaque fois que le jeu range ses sacs ; l'onglet Désenchanter le suit. **Les métiers ont leurs onglets sur le sac** : la pêche, puis la cuisine et la couture (seulement si le métier est appris : un clic ouvre sa fenêtre), puis Désenchanter. `/fs bag` dit où il
est, `/fs bag reset` (ou Options > Confort, « Remettre le sac à dos à sa place ») le rend au jeu.
**Une ligne par sac** (réglage dans Options > Confort, activé par défaut) : le sac à dos en haut, chaque sac à partir
d'une nouvelle ligne, un fin trait entre deux sacs, pour voir la taille de chacun.
Nouveau fichier `ui/bag_frame.lua` : **redémarrage complet du jeu**, un `/reload` ne suffit pas.

**Prérequis** : redémarrage complet ; `/fs debug on`.

| # | Action | Attendu |
|---|---|---|
| 1 | Ouvrir le sac (B), `/fs bag` | Le sac à sa place habituelle ; « Sac à dos : à la place du jeu… ». |
| 2 | Glisser le sac par son titre ou son bord vers le milieu de l'écran | Il suit la souris et reste où on le lâche ; l'onglet Désenchanter (enchanteur) suit le sac pendant le déplacement. |
| 3 | Glisser un objet du sac | L'objet se prend en main comme d'habitude, le sac ne bouge pas. |
| 4 | Fermer et rouvrir le sac ; ouvrir aussi un autre sac (sac de la barre) | Le sac reste à sa nouvelle place. |
| 5 | `/reload`, rouvrir le sac | Toujours à sa nouvelle place. |
| 6 | Entrer en combat, ouvrir et fermer le sac, essayer de le déplacer | Pas d'erreur « action bloquée » ; le sac s'ouvre à sa place. |
| 7 | `/fs bag reset` | « Sac à dos remis à la place du jeu. » ; le sac revient en bas à droite. |
| 8 | Avec plusieurs sacs équipés, ouvrir le sac (B) ; `/fs bag slots` | **Une ligne par sac** : le sac à dos en haut, puis chaque sac à partir d'une nouvelle ligne ; au-dessus de chaque sac, son nom, ses cases et ses cases libres (« Sac à dos · 20 cases  3 libre(s) ») ; un fin trait doré entre deux sacs ; **le cadre est plus haut d'autant** : la dernière ligne ne touche pas l'or. La commande dit la taille de chaque sac et la hauteur (« height: … (game …, added …) »). |
| 9 | Ramasser un objet, en déplacer un d'un sac à l'autre, changer un sac de la barre | Toujours une ligne par sac, les objets à leur case ; la bordure dorée du désenchantement (T36) sur les bonnes cases. |
| 10 | Options > Confort, décocher « Sac à dos : une ligne par sac… » | La grille du jeu revient (les sacs à la suite) et la hauteur d'avant ; recoché, une ligne par sac. |
| 11 | Un personnage qui pêche, une canne dans les sacs : ouvrir le sac ; ouvrir la fenêtre ForeverSpeech | L'onglet de la pêche est **sur le côté du sac**, au-dessus de Désenchanter (enchanteur) ; plus sur la fenêtre ForeverSpeech (les émotes y restent). Clic : la canne équipée, l'onglet allumé ; reclic : les armes reviennent. |
| 12 | Un personnage qui a appris la cuisine (ou la couture) : ouvrir le sac ; cliquer l'onglet du métier | Sous la pêche, un onglet par métier appris (cuisine, couture ; aucun pour un métier non appris), puis Désenchanter ; survol : nom du métier, « Clic : ouvrir la fenêtre du métier. » ; clic : la fenêtre du métier s'ouvre comme depuis le grimoire ; reclic : elle se ferme. En combat, les onglets disparaissent. |

**À relever** : les lignes `bag: moved to …` et `bag: movable, layout hooks: …` de la trace, les erreurs (BugSack), une capture si le sac saute ailleurs
(à l'ouverture, au changement de sacs, après le combat).

**Résultat (2026-10-20, en partie)** : le sac se déplace et garde sa place (trace `bag: moved to …`, étapes 1-2) ;
une ligne par sac validée à l'œil après réglages (sac à dos de 20 cases, sac de 6 : `/fs bag slots`), titres, hauteur
et marges (premier titre remonté de 11 pixels, 6 de plus sous le dernier sac) (étape 8) ; l'onglet de la pêche sur le
sac, la canne équipée puis les armes rendues (trace `fishing: equip`, étape 11) ; les onglets de la cuisine et de la
couture affichés sous la pêche (étape 12, le clic n'est pas relevé). Le jeu redonne sa hauteur au sac et place ses
cases depuis le bas du cadre : corrigé (hauteur remise à chaque redimensionnement, haut de la grille mesuré à la
hauteur du jeu). Non relevé : étapes 3-7, 9, 10, le clic des onglets de métier.

## T39 — Livres et plaques lus par Elise (2026-10-21, D19)

**Livré** (branche `session/2026-10-21-books-ui`, `core/books.lua`, `core/text.lua`, index v9) : chaque page d'un livre
ou d'une plaque est **capturée** (`ForeverSpeechCaptures.books`) puis **lue** : la voix d'Elise si la page a son audio
dans l'index (`books`, retrouvée par le titre et l'empreinte du texte), sinon la synthèse vocale du jeu sur le texte de
la page (comme une quête sans audio, réglage `/fs fallback`). Tourner la page coupe la lecture et lit la suivante ;
fermer le livre coupe la lecture. Une **lettre** (d'un joueur, ou lue à la boîte aux lettres) n'est ni lue ni capturée.
Réglage « Lire les livres et les plaques » (Options > Lecture des quêtes, activé par défaut) ; `/fs books [on|off]`.
Pas encore d'audio d'Elise pour les livres (275 livres dans l'index, empreintes seulement) : on entend la synthèse vocale.

**Prérequis** : **redémarrage complet du jeu** (nouveaux fichiers) ; `/fs debug on` ; un livre de plusieurs pages (un
livre des sacs, ou un livre posé dans une bibliothèque : Stormwind, Ironforge…) et une plaque.

| # | Action | Attendu |
|---|---|---|
| 1 | Ouvrir le livre | La première page est lue (voix de synthèse française, ou Elise) ; la fenêtre de l'addon montre « Titre — page 1 », Elise et son portrait, le texte de la page **sans balises HTML** ; dans la liste, l'icône d'un livre. |
| 2 | Tourner la page pendant la lecture | La page 1 s'arrête aussitôt, la page 2 est lue. |
| 3 | Fermer le livre pendant la lecture | La lecture s'arrête. |
| 4 | Lancer une quête (▶), puis ouvrir le livre pendant qu'elle est lue | La page attend son tour dans la liste ; tourner la page remplace la page en attente. |
| 5 | Ouvrir une plaque | Lue comme un livre. |
| 6 | Lire une lettre de la boîte aux lettres | Rien n'est lu. |
| 7 | `/fs books off`, ouvrir le livre ; `/fs books on` ; `/fs books` | Rien n'est lu ; puis « books read by Elise: on. N book(s), M page(s) captured; 275 book(s) in the index. » |

**À relever** : les lignes `books: …` du journal (`/dump ForeverSpeechDB.trace`), le titre affiché (`ItemTextGetItem`),
et, après `/reload`, un extrait de `ForeverSpeechCaptures.books` (un livre : titre, numéros de page, début du texte : le
texte est-il en HTML ?) ; les erreurs (BugSack).

## T40 — Dialogues des PNJ lus dans leur voix (2026-10-21, D14)

**Livré** (branche `session/2026-10-21-books-ui`, `core/dialogues.lua`, index v9) : à l'ouverture de la fenêtre de
discussion d'un PNJ (icône de bulle), 0,1 s après, son texte est comparé aux pages du PNJ dans l'index (`dialogues`) :
mêmes mots une fois retirés le nom, la classe et la race du personnage, sinon au moins 70 % des mots de la page ; la
page trouvée est lue **dans la voix du PNJ** (variante féminine si besoin). La page suivante remplace la précédente ;
fermer la fenêtre coupe la lecture. **Pas de synthèse vocale** pour un dialogue sans audio. La salutation du jeu de ces
PNJ est coupée, comme pour un PNJ à quête (§9.9). Réglage « Lire les dialogues des PNJ » (Options > Lecture des
quêtes, activé par défaut) ; `/fs gossip [on|off]`.

**Prérequis** : redémarrage complet ; `/fs debug on` ; Stormwind (gardes de la ville, 68 : 31 pages avec audio).

| # | Action | Attendu |
|---|---|---|
| 1 | Parler à un garde de Stormwind | Pas de salutation du jeu ; « Où voulez-vous aller ? » dans la voix du garde ; la fenêtre de l'addon montre son nom et **son modèle 3D** ; dans la liste, l'icône de bulle. |
| 2 | Cliquer « La banque » (ou une autre option) | La réponse du garde est lue, la première page s'arrête si elle jouait encore. |
| 3 | Fermer la fenêtre pendant la lecture | La lecture s'arrête. |
| 4 | Parler à un PNJ dont le dialogue n'a pas d'audio (un marchand) | Rien n'est lu ; sa salutation du jeu reste. |
| 5 | Parler à un PNJ à quête qui a aussi un dialogue, puis cliquer une quête | Le dialogue s'arrête au passage à la page de quête. |
| 6 | `/fs gossip off`, parler au garde ; `/fs gossip on` | Rien n'est lu, la salutation du jeu revient ; « NPC dialogues read in their voice: on (index: … NPC(s), … page(s) with audio) ». |

**À relever** : les lignes `dialogues: npc … page … score …` et `dialogues: npc …, no page (best score …)` du journal, le
texte exact d'un dialogue non retrouvé (`/fs gossip` le montre), les erreurs.

## T41 — Baisse du son du jeu pendant une lecture et raccourcis clavier (2026-10-21)

**Livré** (branche `session/2026-10-21-books-ui`, `core/ducking.lua`, `core/bindings.lua`, `Bindings.xml`) :
- pendant une lecture de l'addon (quête, Elise, livre, dialogue), **la musique, l'ambiance et les effets baissent en
  0,8 s** (musique à 30 %, ambiance à 40 %, effets à 60 % de ton réglage ; jamais le canal de l'addon, « Dialog » par
  défaut) et remontent 1,2 s après la fin de la liste (pas entre deux quêtes). Un curseur que tu bouges pendant la
  baisse n'est plus touché. Remise immédiate au `/reload` et à la déconnexion ; à la connexion, ce qu'un plantage a laissé
  baissé est remis. Réglage « Pendant une lecture, baisser la musique… » (Options > Lecture des quêtes, activé) ;
  `/fs duck on|off` ;
- **raccourcis** : Options > Raccourcis > AddOns > ForeverSpeech : « Lecture / Stop (quête affichée) », « Avancer
  (quête suivante) », « Stop ».

**Prérequis** : **redémarrage complet** (`Bindings.xml` n'est lu qu'au lancement) ; `/fs debug on` ; musique et
ambiance du jeu audibles ; noter tes volumes (Options du jeu > Son).

| # | Action | Attendu |
|---|---|---|
| 1 | Lancer une quête (▶) | La musique et l'ambiance baissent en moins d'une seconde ; la voix reste au même volume. |
| 2 | Attendre la fin de la lecture | 1,2 s après, la musique remonte ; Options du jeu > Son : **tes volumes d'origine**. |
| 3 | Pendant une lecture, bouger le curseur de la musique dans les options du jeu ; laisser finir | Après la lecture, la musique reste où tu l'as mise ; l'ambiance revient à son volume. |
| 4 | Pendant une lecture, `/reload` | Après le rechargement, tes volumes d'origine. |
| 5 | `/fs duck off`, lancer une quête | Rien ne baisse. `/fs duck on` ensuite. |
| 6 | Options > Raccourcis > AddOns | L'en-tête « ForeverSpeech » et ses trois actions en français ; leur poser trois touches. |
| 7 | La fenêtre ouverte sur une quête : touche Lecture / Stop ; encore ; touche Avancer avec deux quêtes dans la liste ; touche Stop | Lecture de la quête affichée ; arrêt ; passage à la suivante ; arrêt. |

**À relever** : les lignes `ducking: …` du journal, `/dump C_CVar.GetCVar("Sound_MusicVolume")` pendant et après une
lecture, si les raccourcis apparaissent (capture), les erreurs.

## T42 — Champs de bataille silencieux, donjons sans erreur (2026-10-21)

**Livré** (branche `session/2026-10-21-books-ui`, `core/silence.lua`, valeurs secrètes dans `core/*`) :
- en **champ de bataille ou en arène**, l'addon ne lance rien de lui-même (présentations de zone, niveaux et compagnons
  d'Elise, lecture à l'ouverture de « Terminer », lecture au bouton « Accepter » du jeu, livres, dialogues) ; ce que tu
  demandes (▶, « Accepter et lire », `/fs play`) est lu ; en entrant, ce que l'addon avait mis lui-même dans la liste
  en est retiré. Réglage « Lire en champ de bataille et en arène » (Options > Général, désactivé) ;
- en **donjon et en combat**, Forever donne aux addons certaines valeurs « secrètes » (nom et GUID du PNJ, titre et ID
  de la quête) : l'addon les traite comme inconnues, sans erreur.

**Prérequis** : redémarrage complet ; `/fs debug on` ; BugSack ; un niveau qui permet un champ de bataille et un donjon.

| # | Action | Attendu |
|---|---|---|
| 1 | `/dump issecretvalue` | Une fonction (ou `nil` : à noter). |
| 2 | Avec une quête dans la liste lancée par l'addon (fin de quête lue à l'ouverture de « Terminer », réglage activé), entrer dans un champ de bataille ; `/dump IsInInstance()` | `true, "pvp"` ; la quête automatique n'est plus dans la liste ; trace `silence: battleground, … automatic line(s) dropped`. |
| 3 | Dans le champ de bataille, ▶ sur une quête du suivi | Elle est lue. |
| 4 | Options > Général, cocher « Lire en champ de bataille et en arène » | Ce que l'addon lance de lui-même est de nouveau lu. Décocher ensuite. |
| 5 | En donjon : parler à un PNJ, ouvrir une quête, la rendre, combattre avec un PNJ ciblé, survoler des PNJ | **Aucune erreur Lua** de ForeverSpeech (BugSack) ; `/dump issecretvalue(UnitGUID("target"))` en combat. |
| 6 | Si une arène est possible : `/dump IsInInstance()` dedans | `true, "arena"`. |

**À relever** : les valeurs des `/dump`, les lignes `silence: …` du journal, toute erreur de BugSack (le message complet).

## T43 — La nouvelle apparence : boutons ronds, barres et cases du jeu (2026-10-21)

> **Remplacé par T55** (2026-10-21) : la fenêtre a changé depuis ; faire T55, qui reprend tout ce qui reste vrai.

**Livré** (branche `session/2026-10-21-books-ui`, `ui/style.lua`, textures `media/ui/*.tga` peintes pour l'addon par
Codex, `tools/ui_icons.ts`) :
- **boutons ronds** (anneau bronze et or, disque sombre, pictogramme doré) pour Lecture / Avancer / Stop de la
  fenêtre, et sur la carte du monde ; le pictogramme s'éclaire au survol, s'enfonce d'un pixel au clic, se grise
  désactivé ; petit son du jeu au clic ; infobulles en trois niveaux (action, aide dorée, astuce grise) ;
- **suivi d'objectifs et journal** : le pictogramme doré sur la petite case du jeu (`checkbox-minimal`) ;
- **objectifs de la fenêtre** : barres du jeu (`widgetstatusbar-*`, bord arrondi, remplissage doré) et cases
  `checkbox-minimal` / `checkmark-minimal`, sinon l'ancien rendu ;
- **nouvelle icône** de l'addon (minimap, menu des addons, titre de la fenêtre), et le ▶ doré d'« Accepter et lire ».

**Prérequis** : **redémarrage complet** (nouveaux fichiers de texture) ; BugSack.

| # | Action | Attendu |
|---|---|---|
| 1 | `/dump C_Texture.GetAtlasInfo("checkbox-minimal") ~= nil, C_Texture.GetAtlasInfo("widgetstatusbar-fill-yellow") ~= nil, C_Texture.GetAtlasInfo("Options_HorizontalDivider") ~= nil` | Trois `true` (sinon : le repli est utilisé, à noter). |
| 2 | Ouvrir la fenêtre sur une quête qui a des objectifs chiffrés | Trois boutons ronds sous l'état ; barres d'objectifs à bord arrondi, remplissage doré ; cases fines. |
| 3 | Survoler, cliquer, attendre la fin de la liste | Pictogramme plus lumineux au survol, petit son au clic ; Lecture grisé quand il n'y a rien. |
| 4 | Suivi d'objectifs et journal de la carte | Petit ▶ doré dans une case fine ; ■ (Stop) teinté de vert pendant la lecture. |
| 5 | Minimap, menu des addons, bouton « Accepter et lire » | Nouvelle icône (livre ouvert et ondes) ; ▶ doré dans le bouton. |

**À relever** : les trois valeurs du `/dump`, une capture de la fenêtre et du suivi, toute erreur de BugSack.

## T44 — Le récit du lieu à côté de la carte du monde (2026-10-21, D16)

**Livré** (branche `session/2026-10-21-books-ui`, `ui/map_panel.lua`, peintures `media/zones/<mapID>.tga` par Codex,
`tools/zone_pictures.ts`) : carte ouverte sur une zone qu'Elise présente, une page de parchemin contre le bord droit
de la carte : nom de la zone, « Raconté par Elise », un trait d'encre, la peinture de la zone, son texte, un bouton
rond Lecture / Stop. Zone pas encore découverte : peinture grisée, texte et voix gardés pour plus tard. Carte en
plein écran : la page se pose à l'intérieur, contre le bord droit. Le bouton rond aux lignes dorées, à gauche du
bouton de lecture dans le coin de la carte, l'affiche ou la masque (réglage « Récit du lieu… », Options > Confort).

**Prérequis** : **redémarrage complet** (nouveaux fichiers) ; BugSack.

| # | Action | Attendu |
|---|---|---|
| 1 | Ouvrir la carte sur la Forêt d'Elwynn | La page à droite de la carte : titre en encre, peinture, texte d'Elise. |
| 2 | Bouton rond de la page | Elise lit la présentation ; le bouton passe en Stop. |
| 3 | Afficher une zone jamais visitée (Tanaris) | Peinture grisée, « Elise vous racontera ce lieu… », bouton grisé. |
| 4 | Afficher un continent ou une ville sans présentation | Pas de page. |
| 5 | Bouton aux lignes dans le coin de la carte, puis à nouveau | La page disparaît, puis revient ; la croix de la page la masque aussi. |
| 6 | Agrandir la carte en plein écran | La page reste visible, à l'intérieur de la carte, à droite. |
| 7 | `/dump DefaultPanelFlatTemplate ~= nil, QuestTitleFont ~= nil` | Deux `true` (sinon le cadre sombre de secours). |

**À relever** : une capture de la carte avec la page (zone découverte et non découverte), le `/dump`, toute erreur.

## T45 — Deuxième passe graphique : cadre, titres, liste, récompenses, options (2026-10-21)

> **Remplacé par T55** (2026-10-21) : la fenêtre a changé depuis ; faire T55, qui reprend tout ce qui reste vrai.

**Livré** (branche `session/2026-10-21-ui-polish`, `ui/style.lua`, `ui/player_frame.lua`, `ui/options_frame.lua` ;
textures `media/ui/frame.tga` et `media/ui/divider_gold.tga` peintes par Codex, `tools/ui_icons.ts`) :
- **cadre bronze et or** autour du modèle 3D ou du portrait d'Elise ;
- **titres de section** (« Objectifs », « Récompenses », « Liste de lecture », titres des répliques d'Elise) dans la
  police des titres de quête du jeu, en or, suivis d'un **trait doré** sur le reste de la ligne ;
- **liste de lecture** dans le cadre creusé du jeu (`InsetFrameTemplate`), icônes plus grandes, **croix rouge du jeu**
  pour retirer une ligne, **barre dorée** sur la ligne affichée (à la place du « < ») ;
- **récompenses** entourées du cadre d'icône du jeu, à la couleur de leur qualité (vert, bleu, violet) ;
- **options** : les cases fines du jeu (`checkbox-minimal`), si le client les a.

**Prérequis** : **redémarrage complet** (nouvelles textures) ; à faire avec T43 et T44.

| # | Action | Attendu |
|---|---|---|
| 1 | Fenêtre sur une quête avec des récompenses d'objets verts ou bleus | Cadre doré autour du modèle ; titres en or dans la police des quêtes avec un trait doré ; icônes de récompense bordées de vert / bleu. |
| 2 | Une réplique d'Elise (`/fs level 5`) | Son portrait dans le cadre ; le titre de section en or. |
| 3 | Ouvrir la liste de lecture avec 3 quêtes | Cadre creusé, titre en or et trait ; la ligne affichée surlignée en or ; croix rouge sur les lignes à venir. |
| 4 | Vue Compagnons | Le cadre de droite a le même aspect. |
| 5 | Options | Cases fines (sinon les anciennes, à noter). |
| 6 | `/dump InsetFrameTemplate ~= nil, QuestTitleFont ~= nil` | Deux `true`. |

**À relever** : une capture de la fenêtre (quête avec récompenses, liste ouverte), une des options, toute erreur.

## T46 — Les options dans le menu du jeu (2026-10-21)

**Livré** (branche `session/2026-10-21-ui-polish`, `ui/options_frame.lua`) : les options de l'addon sont dans le menu
du jeu, **Échap > Options > AddOns > ForeverSpeech** : la catégorie ForeverSpeech (thème Général) et une sous-catégorie
par thème (Lecture des quêtes, Fenêtre de quête, Elise, Compagnons, Confort, Avancé). L'engrenage de la fenêtre, le
clic droit sur l'icône de la minimap et `/fs options [thème]` ouvrent ce menu sur le thème demandé (sinon le dernier).
Sans ce menu (API absente), l'ancienne fenêtre d'options s'ouvre comme avant. En combat : un message, rien ne s'ouvre.

**Prérequis** : `/reload` suffit (pas de nouveau fichier) ; BugSack.

| # | Action | Attendu |
|---|---|---|
| 1 | `/dump Settings ~= nil, Settings and Settings.RegisterCanvasLayoutCategory ~= nil, SettingsPanel ~= nil` | Trois `true`. |
| 2 | Échap > Options > AddOns | « ForeverSpeech » dans la liste, avec ses sous-thèmes dessous. |
| 3 | Cliquer chaque thème | Ses réglages à droite, les mêmes qu'avant ; une case cochée change bien le réglage. |
| 4 | L'engrenage de la fenêtre, puis à nouveau | Le menu s'ouvre sur le dernier thème, puis se ferme. |
| 5 | `/fs options elise` | Le menu s'ouvre sur Elise. |
| 6 | En combat, l'engrenage | Message « Les options du jeu s'ouvriront après le combat… », rien ne s'ouvre, aucune erreur. |

**À relever** : le `/dump`, une capture du menu sur un thème, et si le thème demandé s'ouvre bien (sinon : lequel).

## T47 — Troisième passe : proportions et légèreté de la fenêtre (2026-10-21)

> **Remplacé par T55** (2026-10-21) : la fenêtre a changé depuis ; faire T55, qui reprend tout ce qui reste vrai.

**Livré** (branche `session/2026-10-21-ui-polish`, `ui/player_frame.lua`, `ui/style.lua`) : échelle d'espacement
4 / 8 / 12 / 16 ; portrait 96 × 112 ; boutons ronds de 22 px le long du bas du portrait, puis un trait fin et le bouton
de la liste de lecture (il n'est plus en bas à droite) ; blason de 60 px en haut à droite du titre ; titres de section
petits, en or atténué, frises pâles ; texte en blanc cassé ; objectifs sans bande vide ; récompenses en 24 px.

**Prérequis** : `/reload` (pas de nouveau fichier).

| # | Action | Attendu |
|---|---|---|
| 1 | Fenêtre sur une quête avec texte et récompenses | Le titre domine ; boutons petits alignés sur le bas du portrait, le bouton ≡ à leur suite ; blason en haut à droite ; rien ne se chevauche. |
| 2 | Une quête au titre long (deux lignes) | Le titre passe à la ligne sans toucher le blason ni les boutons. |
| 3 | Une quête avec 3 objectifs chiffrés | Lignes fines, barres lisibles, la fenêtre grandit juste ce qu'il faut. |
| 4 | Le bouton ≡ | La liste s'ouvre à droite, puis se ferme. |

**À relever** : une capture de la fenêtre (quête avec objectifs chiffrés, liste ouverte), et ce qui paraît encore lourd.

## T48 — Quatrième passe : plus de débordement, objectifs épurés, récompenses en ligne (2026-10-21)

> **Remplacé par T55** (2026-10-21) : la fenêtre a changé depuis ; faire T55, qui reprend tout ce qui reste vrai.

**Livré** (branche `session/2026-10-21-ui-polish`, `ui/player_frame.lua`) : la hauteur de la fenêtre est mesurée sur la
vraie mise en page (la troisième passe oubliait la barre de titre : les récompenses passaient sur le bandeau) ;
fenêtre de 450 px ; 16 px entre deux blocs ; objectifs en liste à puces, coche dorée une fois faits, une fine ligne de
progression seulement pour un compteur ; argent et XP au bout de la ligne « Récompenses », icônes d'objets dessous
seulement s'il y en a.

**Prérequis** : `/reload`.

| # | Action | Attendu |
|---|---|---|
| 1 | La quête de ta capture (Introduction au camping : l'enchantement), texte affiché | Rien ne déborde sur le bandeau du bas ; « 270 XP » au bout de la ligne « Récompenses ». |
| 2 | Une quête à objectifs chiffrés (Masque rouge en lin : 3/6) | Puces, texte, une fine ligne dorée sous l'objectif chiffré ; coche dorée sur un objectif fait. |
| 3 | Une quête avec un objet en récompense | Les icônes sous la ligne « Récompenses », bordées à la couleur de leur qualité. |
| 4 | Une réplique d'Elise (`/fs level 5`) | Pas de section Récompenses, la fenêtre se resserre. |

**À relever** : une capture pour 1 et 2.

## T49 — Le chiffre du blason centré sur sa plaque (2026-10-21)

> **Remplacé par T55** (2026-10-21) : la fenêtre a changé depuis ; faire T55, qui reprend tout ce qui reste vrai.

**Livré** (branche `session/2026-10-21-ui-polish`) : le niveau est centré dans tout le blason puis décalé sur le centre
optique de la plaque (un chiffre : 2 px à droite, 2 px plus bas ; deux chiffres : 1 px à droite, 2 px plus bas),
constantes `BADGE_NUDGE` en tête de `ui/player_frame.lua`.

| # | Action | Attendu |
|---|---|---|
| 1 | Une quête de niveau à un chiffre (9) | Le chiffre au centre de la plaque sombre. |
| 2 | Une quête de niveau à deux chiffres (10 ou plus) | Les deux chiffres centrés. |

**À relever** : un zoom sur le blason dans les deux cas (une capture suffit), et le décalage restant s'il y en a.

## T50 — Disposition « médaillon » et fenêtre compacte (2026-10-21)

> **Remplacé par T55** (2026-10-21) : la fenêtre a changé depuis ; faire T55, qui reprend tout ce qui reste vrai.

**Livré** (branche `session/2026-10-21-ui-polish`, `ui/player_frame.lua`) : en tête, le PNJ dans un médaillon rond
(portrait 2D du jeu masqué rond, sinon le modèle 3D cadré sur la tête dans l'anneau ; Elise : son portrait recadré sur
son visage) ; à côté le titre, « PNJ · état », les contrôles et le bouton de la liste ; le blason en haut à droite ;
dessous le texte, les objectifs et les récompenses en pleine largeur. **Fenêtre compacte** (`/fs compact`) : sans la
description de la quête ; les objectifs et les récompenses restent (2026-10-21).

**Prérequis** : `/reload`.

| # | Action | Attendu |
|---|---|---|
| 1 | `/dump SetPortraitTextureFromCreatureDisplayID ~= nil, UIParent.CreateMaskTexture ~= nil` | Deux `true` (sinon : modèle 3D dans l'anneau, carré). |
| 2 | Une quête (Articles rouges en lin) | Le visage de Sara dans le médaillon, bien rond, ni déformé ni coupé ; titre, « Sara Timberlain · En lecture », contrôles dessous. |
| 3 | Une quête au titre long | Le titre sur deux lignes, l'en-tête un peu plus haut, rien ne se chevauche. |
| 4 | `/fs level 5` (Elise) | Le visage d'Elise dans le médaillon. |
| 5 | `/fs compact`, puis `/fs compact` à nouveau | Sans la description (objectifs et récompenses toujours là), puis avec. |

**À relever** : le `/dump`, une capture en complet et en compact, une avec Elise.

## T51 — Sans frises, et la fenêtre qui reste ouverte (2026-10-21)

> **Remplacé par T55** (2026-10-21) : la fenêtre a changé depuis ; faire T55, qui reprend tout ce qui reste vrai.

**Livré** (branche `session/2026-10-21-ui-polish`) : plus de frise à côté de « Objectifs », « Récompenses » ni sous
« Liste de lecture » ; la fenêtre ouverte au moment d'un `/reload` ou d'une déconnexion se rouvre d'elle-même (une
seconde après l'entrée dans le monde), fermée elle reste fermée.

| # | Action | Attendu |
|---|---|---|
| 1 | Fenêtre ouverte, `/reload` | Elle revient ouverte, sur la quête suivie ou la dernière affichée. |
| 2 | Fenêtre ouverte, quitter le jeu, relancer | Elle s'ouvre à l'arrivée en jeu. |
| 3 | Fermer la fenêtre (croix), `/reload` | Elle reste fermée. |
| 4 | Fenêtre ouverte, Alt+Z deux fois, `/reload` | Elle revient ouverte (Alt+Z ne la ferme pas pour l'addon). |
| 5 | Regarder les titres de section | Plus de frises. |

## T52 — Compagnons dans la barre de titre, hauteur minimale (2026-10-21)

> **Remplacé par T55** (2026-10-21) : la fenêtre a changé depuis ; faire T55, qui reprend tout ce qui reste vrai.

**Livré** (branche `session/2026-10-21-ui-polish`) : l'icône des compagnons est dans la barre de titre, à gauche de
l'engrenage (elle s'allume dans la vue Compagnons) ; le côté gauche ne garde que les émotes ; la fenêtre n'est jamais
plus basse que ce qu'il faut aux émotes (258 px avec les quatre).

| # | Action | Attendu |
|---|---|---|
| 1 | `/fs compact` | La fenêtre reste assez haute : les quatre émotes ne se chevauchent pas. |
| 2 | L'icône des compagnons dans la barre de titre | La vue Compagnons ; l'icône allumée ; reclic : retour à la quête. |
| 3 | Le côté gauche de la fenêtre | Seulement les émotes, en bas. |

**À relever** : une capture en compact.

## T53 — Les compagnons dans leur fenêtre, la quête cliquée affichée (2026-10-21)

> **Remplacé par T55** (2026-10-21) : la fenêtre a changé depuis ; faire T55, qui reprend tout ce qui reste vrai.

**Livré** (branche `session/2026-10-21-ui-polish`) : la liste des compagnons s'ouvre dans sa propre fenêtre (icône de
la barre de titre, ou `/fs friends`) ; la quête ouverte dans le journal de la carte, ou dont on clique le titre dans
le suivi, s'affiche dans la fenêtre de ForeverSpeech si elle est ouverte.

| # | Action | Attendu |
|---|---|---|
| 1 | L'icône des compagnons dans la barre de titre | Une fenêtre « Compagnons » à part : la liste à gauche, un clic sur un nom montre ses statistiques à droite ; la fenêtre de quête ne change pas. |
| 2 | La déplacer, la fermer, `/fs friends` | Elle revient au même endroit, le compagnon choisi gardé. |
| 3 | Fenêtre de quête ouverte, cliquer une autre quête dans le journal de la carte | La fenêtre affiche cette quête. |
| 4 | Cliquer le titre d'une quête dans le suivi d'objectifs | Idem (ou via la carte qui s'ouvre). |

**À relever** : le journal de diagnostic (`/fs debug on`) : les lignes `frame: clicked quest=… (questlog|tracker)`.

## T55 — La fenêtre telle qu'elle est : récapitulatif de la refonte (2026-10-21)

**Livré** (PR « session/2026-10-21-ui-polish », CLAUDE.md §9.19) : reprend T43, T45, T47 à T53, qui décrivaient des
étapes intermédiaires. **Prérequis** : redémarrage complet (nouvelles textures depuis la dernière fusion) ; BugSack.

| # | Action | Attendu |
|---|---|---|
| 1 | Une quête avec texte, objectifs chiffrés et un objet vert en récompense | En tête : le PNJ dans un médaillon rond, le titre (or), « PNJ · état », les boutons ronds dorés et le bouton de la liste ; le blason en haut à droite, chiffre centré. Dessous : la description, les objectifs (puces, fine ligne dorée sous l'objectif chiffré), les récompenses (XP au bout de la ligne, icône bordée de vert). Rien ne déborde sur le bandeau du bas. |
| 2 | Survoler, cliquer les boutons ronds | Pictogramme plus lumineux au survol, petit son au clic, infobulle ; Lecture grisé sans rien à lire. |
| 3 | Le bouton aux trois barres | La liste s'ouvre à droite (cadre creusé, ligne affichée surlignée en or, croix rouge), puis se ferme. |
| 4 | `/fs compact`, puis à nouveau | Sans la description (objectifs et récompenses restent), puis avec ; la fenêtre ne descend pas sous la hauteur des émotes. |
| 5 | Une réplique d'Elise (`/fs level 5`) | Son visage dans le médaillon, pas de section Récompenses. |
| 6 | Cliquer une autre quête dans le journal de la carte, puis un titre du suivi | La fenêtre affiche la quête cliquée. |
| 7 | L'icône des compagnons (barre de titre) | Leur fenêtre à part ; un nom cliqué montre ses statistiques ; la fenêtre de quête ne change pas. |
| 8 | Fenêtre ouverte, `/reload` ; fermée, `/reload` | Elle revient ouverte ; elle reste fermée. |
| 9 | Suivi d'objectifs et journal de la carte | Le petit pictogramme doré sur la case fine ; Stop teinté de vert pendant la lecture. |
| 10 | `/dump SetPortraitTextureFromCreatureDisplayID ~= nil, InsetFrameTemplate ~= nil, C_Texture.GetAtlasInfo("checkbox-minimal") ~= nil` | Trois `true` (sinon le repli, à noter). |

**À relever** : deux captures (étape 1 avec la liste ouverte, étape 7), toute erreur de BugSack.

## T56 — Lecture automatique avec Dialogue UI (2026-10-21)

**Livré** (branche `session/2026-10-21-dialogueui-autoplay`, CLAUDE.md §9.1, H29) : l'option « Lire chaque quête
acceptée ou rendue » lit 2 s après les événements du jeu `QUEST_ACCEPTED` et `QUEST_TURNED_IN`, et non plus au clic
sur le bouton Accepter du jeu, que Dialogue UI ne montre jamais. **Prérequis** : `/reload` ; Dialogue UI activé ;
dans ses options, la synthèse vocale (« TTS ») et sa lecture automatique **désactivées** (sinon deux voix) ;
`/fs debug on`.

| # | Action | Attendu |
|---|---|---|
| 1 | `/fs autoplay on` | « read every quest accepted or turned in (game buttons, Dialogue UI...): on » ; dans Options > Lecture des quêtes, la case « Lire chaque quête acceptée ou rendue » cochée. |
| 2 | Accepter une quête dans la fenêtre de Dialogue UI | 2 s après, la voix du PNJ (ou la synthèse du client sans audio) ; la fenêtre de l'addon montre la quête. |
| 3 | Rendre une quête dans Dialogue UI | 2 s après le rendu, le texte de fin (**?** dans la liste de lecture). |
| 4 | Dialogue UI désactivé, accepter puis rendre avec les boutons du jeu | Même chose, une seule lecture ; « Accepter et lire » ne lit qu'une fois. |
| 5 | `/fs autoplay off`, accepter dans Dialogue UI | Rien n'est lu. |

**À relever** : les lignes `accept: QUEST_ACCEPTED quest=…` et `turn-in: QUEST_TURNED_IN quest=…` du chat de debug
(l'ID doit être celui de la quête, pas `nil`), toute erreur de BugSack.

**Résultat (2026-10-21)** : ça marche avec Dialogue UI, à l'acceptation comme au rendu.

## T57 — Une seule option : la lecture automatique (2026-10-21)

**Livré** (branche `session/2026-10-21-dialogueui-autoplay`, CLAUDE.md §9.1) : les boutons « Accepter et lire » et
« Terminer et lire » et la lecture à l'ouverture de « Terminer » sont retirés ; reste l'option « Lecture automatique
des quêtes acceptées et rendues », remise à activée pour tous (réglages v4). **Prérequis** : **redémarrage complet du
jeu** (nouveau fichier `core/autoplay.lua`) ; BugSack.

| # | Action | Attendu |
|---|---|---|
| 1 | Dialogue UI désactivé, ouvrir une quête chez un PNJ | Seuls Accepter et Refuser du jeu ; plus de « Accepter et lire ». |
| 2 | Accepter | La quête est lue 2 s après. |
| 3 | Ouvrir l'onglet « Terminer la quête » d'une quête finie | Rien n'est lu à l'ouverture ; plus de « Terminer et lire ». |
| 4 | Terminer la quête | Sa fin est lue 2 s après. |
| 5 | Dialogue UI réactivé, accepter puis rendre une quête | Comme 2 et 4. |
| 6 | Options > Lecture des quêtes | Une case « Lecture automatique des quêtes acceptées et rendues », cochée ; plus de case pour « Terminer ». Décochée : rien n'est lu. |

**À relever** : toute erreur de BugSack.

## T58 — Quêtes triées par niveau dans le suivi et le journal (2026-10-21)

**Livré** (branche `session/2026-10-21-dialogueui-autoplay`, CLAUDE.md §9.20, H31). **Prérequis** : **redémarrage
complet** (nouveau fichier `ui/quest_sort.lua`) ; au moins trois quêtes suivies de niveaux différents ; BugSack ;
`/fs debug on`.

| # | Action | Attendu |
|---|---|---|
| 1 | `/fs sort probe`, puis `/reload` | « sort probe: N lines stored… ». Rien d'autre à faire : je lis `ForeverSpeechDB.sortProbe` sur le disque. |
| 2 | Regarder le suivi d'objectifs | Les quêtes de la plus basse à la plus haute (le blason de la fenêtre donne le niveau d'une quête cliquée). |
| 3 | Accepter une quête de bas niveau ; en rendre une ; faire progresser un objectif | Le suivi reste trié à chaque fois (la nouvelle quête prend sa place, pas à la fin). |
| 3 bis | Le petit bouton à liste sur l'en-tête « Tous les objectifs », à gauche du bouton de réduction | Infobulle « Trier les quêtes par niveau » ; au clic, « quêtes triées par niveau. » dans le chat, même avec `/fs sort off`. |
| 4 | Ouvrir le journal (carte, M) | Dans chaque zone, les quêtes de la plus basse à la plus haute ; chaque quête garde ses objectifs sous son titre ; les en-têtes ne bougent pas. |
| 5 | Replier puis déplier une zone du journal, cliquer une quête | Toujours trié ; la quête cliquée s'ouvre (pas une autre). |
| 6 | Accepter une quête pendant un combat | Le suivi se trie à la sortie du combat ; aucune erreur. |
| 7 | `/fs sort off` | Le journal reprend l'ordre du jeu à sa prochaine mise à jour ; le suivi garde l'ordre actuel. |

**À relever** : les lignes `sort: tracker …` et `sort: quest log …` du chat de debug (`kept by the game` = le jeu
impose son ordre), toute erreur de BugSack (surtout « action bloquée »).

**Résultat (2026-10-21)** : le tri marche en jeu (« ça marche »).

## T59 — Sens du tri (2026-10-21)

**Livré** (branche `session/2026-10-21-dialogueui-autoplay`, CLAUDE.md §9.20). **Prérequis** : `/reload` ; quelques
quêtes suivies de niveaux différents.

| # | Action | Attendu |
|---|---|---|
| 2 | Survoler le bouton à liste de « Tous les objectifs » | Infobulle : « Trier les quêtes par niveau », « Ordre : niveau croissant… », « Clic droit : inverser l'ordre ». |
| 3 | Clic droit sur ce bouton | « tri par niveau décroissant. » : la quête la plus haute en haut, dans le suivi et le journal. Clic droit à nouveau : croissant. |
| 4 | Options > Confort : « Ordre du tri » | L'ordre suit le réglage. |

**À relever** : toute erreur de BugSack.

**Résultat (2026-10-21)** : le sens du tri marche.

## T60 — Roue d'émotes (2026-10-21)

**Livré** (branche `session/2026-10-21-dialogueui-autoplay`, CLAUDE.md §9.21, H32 à H35 ; conception : session « Roue
d'émotes façon roue des pings »). **Prérequis** : **redémarrage complet** (nouveau fichier `ui/emote_wheel.lua`, une
ligne de plus dans `Bindings.xml`) ; BugSack ; `/fs debug on`.

D'abord les relevés, à coller tels quels :
```
/run for _,n in ipairs({"Radial_Wheel_BG","Radial_Wheel_Select_Pointer","Radial_Wheel_Select_Close","Radial_Wheel_Icon_Close","gamepad-xb-32x-rstick"}) do local i=C_Texture.GetAtlasInfo(n) print(n, i and (i.width.."x"..i.height) or "ABSENT") end
/run local t={} for n=2,12 do if C_Texture.GetAtlasInfo("Radial_Wheel_Frame_Count_"..n) then t[#t+1]="F"..n end if C_Texture.GetAtlasInfo("Radial_Wheel_Select_Wedge_Count_"..n) then t[#t+1]="W"..n end end print("counts:", table.concat(t," "))
/dump C_GamePad.IsEnabled(), GetCVar("GamePadEnable")
```

| # | Action | Attendu |
|---|---|---|
| 1 | Options > Confort, « Touche de la roue d'émotes » : clic, puis une touche (ex. `G`, ou Maj+G) | Le bouton affiche la touche ; le chat : « roue d'émotes : touche G. » (ou ce qu'elle remplaçait). Aussi visible dans Options > Raccourcis > AddOns > ForeverSpeech. |
| 2 | Maintenir la touche | La roue s'ouvre au curseur : fond et quartiers de la roue des pings (ou l'anneau de l'addon et des traits), 8 icônes avec leur nom, croix au centre. |
| 3 | Viser chaque quartier sans relâcher | Le quartier s'éclaire (et le pointeur tourne vers lui), l'icône grossit, le nom s'écrit sous la roue. **La surbrillance tombe-t-elle sur le bon quartier ?** |
| 4 | Relâcher sur Saluer, avec puis sans cible | Le personnage salue (la cible, puis tout le monde). |
| 5 | Relâcher au centre ; appui très bref | Rien. |
| 6 | Clic gauche pendant la roue ; clic droit | L'émote tout de suite ; la roue se ferme sans rien. |
| 7 | En combat contre un mob facile | Même chose, aucune « action bloquée ». |
| 8 | Clic droit maintenu (vue souris), puis la touche | La roue au centre de l'écran. |
| 9 | À la manette, si le mode manette du jeu est actif : la touche sur un bouton (Options > Raccourcis), stick droit | Le quartier suit le stick ; relâcher le bouton lance l'émote. |
| 10 | Clic droit sur le bouton de la touche (Options) | « roue d'émotes : plus de touche. » |

**À relever** : les trois lignes des relevés, une capture de la roue ouverte avec un quartier éclairé (étape 3), la
ligne `emote wheel: built, atlases …` du chat de debug, toute erreur de BugSack, et comment ta manette parle au jeu
(mode manette du jeu, ou un outil comme Steam).

**Résultat (2026-10-21, premier essai)** : la roue s'affiche, mais aucun quartier ne s'éclaire au survol et relâcher ne
lance rien. Cause probable : le mode manette du jeu actif (manette branchée), où la première version n'écoutait que le
stick. Corrigé : la souris et le stick visent tous les deux. **À refaire** : `/fs debug on`, étapes 2 à 6, puis
`/reload` (je lis les lignes `emote wheel: open … gamepad=…` et `emote wheel: wedge …` dans les sauvegardes).

**Résultat (2026-10-21, deuxième essai)** : « ça marche bien ». Les boutons d'émote du bord de la fenêtre sont retirés
(la roue les remplace) : au prochain `/reload`, plus rien sur le bord gauche de la fenêtre.

**Retour (2026-10-21, capture)** : le pointeur doré n'était ni centré ni dans la bonne direction, et rien n'éclairait
le quartier visé. Corrigé comme la roue du jeu : pointeur centré sur la roue et tourné vers la direction visée ; sans
surbrillance à 8 quartiers dans le client, un disque doré derrière l'icône visée. **À refaire** (`/reload`) : viser
chaque quartier, le pointeur doit pointer vers la souris depuis le centre et le disque suivre l'icône visée.

**Retour (2026-10-21, deuxième capture)** : pointeur bon, mais l'aspect ne ressemble pas à la roue des pings. Refait dans
son style : disque sombre, fines séparations grises, **cône doré** sur le quartier visé, bouton central rond (images
dessinées par `tools/wheel_art.ts`), **nouvelles icônes** : émojis « World of Warcraft » simples sur fond transparent
(`tools/wheel_icons.ts`), noms en blanc à l'extérieur des icônes. **À refaire** : **redémarrage complet** (nouvelles
textures), une capture de la roue avec un quartier visé.

## T61 — Jour de sortie : la vérification du jeu et un tour complet (2026-11-03)

**Livré** (branche `session/2026-11-03-release-cleanup`, H36). Le client est passé à la build **1.60.1.70755** le
2026-11-03 (toujours l'interface `16001`). **Prérequis** : le dossier du projet sur `main` à jour (le jeu lit
`addon/ForeverSpeech` par le lien de `tools/link_addon.sh`) ; **redémarrage complet** (nouveau fichier
`core/check.lua`, 945 pages de livres et nouvelles répliques d'Elise) ; les erreurs Lua visibles : BugSack n'est pas
installé dans `_forever_`, donc `/console scriptErrors 1` une fois (le réglage reste).

| # | Action | Attendu |
|---|---|---|
| 1 | Se connecter, attendre 10 s | Rien dans le chat (tout est trouvé), ou une ligne « game check (build 1.60.1.…) : N of M names missing (/fs check for the list) ». |
| 2 | `/fs check` | La même ligne, puis un nom manquant par ligne (`global …`, `event …`, `template …`, `atlas …`, `texture …`). |
| 3 | Accepter une quête qui a son audio (Elwynn, Dun Morogh, Teldrassil…) | 2 s après, la voix du donneur ; la fenêtre s'ouvre sur la quête. |
| 4 | Rendre une quête | 2 s après, le texte de fin dans la voix du PNJ de rendu. |
| 5 | Ouvrir un livre ou une plaque (une stèle, un livre sur une table) | Elise lit la page ; page suivante : la lecture suit ; fermé : arrêt. |
| 6 | Parler à un garde de Hurlevent (bulle de dialogue) | Sa page de dialogue dans sa voix. |
| 7 | Ouvrir la carte du monde | Le récit du lieu contre le bord droit, son bouton de lecture marche. |
| 8 | `/reload` | Rien à coller : je lis `ForeverSpeechDB.check` et la trace dans les sauvegardes. |

**À relever** : la ligne de l'étape 1 (ou « rien »), toute erreur Lua affichée, et ce qui ne s'est pas passé comme
attendu.

## T62 — Un onglet par métier sur le sac, grisé loin du feu (2026-11-05)

**Livré** (branche `session/2026-11-05-profession-tabs`, H37). Sur le sac, sous la pêche, un onglet par métier appris
qui a une fenêtre : alchimie, forge, enchantement, ingénierie, travail du cuir, couture, fonte (le minage), cuisine,
secourisme ; un clic ouvre la fenêtre du métier. La cuisine, la fonte et la forge sont **grisées quand le jeu dit que
leur lieu n'est pas à proximité** (un feu, une forge, une enclume), et s'ouvrent quand même. **Prérequis** : `/reload`
(aucun nouveau fichier) ; un personnage qui a appris la cuisine (et si possible le minage ou la forge).

| # | Action | Attendu |
|---|---|---|
| 1 | `/reload`, ouvrir le sac | Sous la pêche, un onglet par métier appris, puis Désenchanter (s'il est connu). Aucun onglet pour un métier non appris, ni pour l'herboristerie ou le dépeçage. |
| 2 | Loin de tout feu, survoler l'onglet de la cuisine | Icône grise ; infobulle : « Cuisine », « Clic : ouvrir la fenêtre du métier. », puis en rouge « Pas de feu de cuisine à proximité : les recettes en demandent un. » |
| 3 | Cliquer l'onglet de la cuisine | La fenêtre de la cuisine s'ouvre quand même (ses recettes demandent un feu). |
| 4 | Sac ouvert, s'approcher d'un feu (feu de camp allumé, feu d'une auberge) | En moins d'une seconde, l'icône reprend ses couleurs ; plus de ligne rouge. |
| 5 | S'éloigner du feu | L'icône redevient grise. |
| 6 | Avec le minage ou la forge : même chose près de la forge ou de l'enclume d'une ville | Même comportement. |
| 7 | `/fs check` | Ni `global C_TradeSkillUI.IsNearProfessionSpellFocus` ni `global Enum.Profession` dans la liste. |
| 8 | `/reload` | Rien à coller : je lis la trace (`bag: cooking near=…`) dans les sauvegardes. |

**Si l'icône ne grise jamais** : l'étape 7 dit si la fonction manque sur Forever ; sinon la trace dit ce que le jeu
répond. Les onglets ouvrent leur métier dans tous les cas.

**À relever** : ce qui ne s'est pas passé comme attendu, toute erreur Lua.

**Résultat (2026-11-05)** : tout marche (« Tout marche ») : un onglet par métier appris, la fenêtre du métier à
chaque clic, l'icône grisée loin du feu et en couleur tout près. `C_TradeSkillUI.IsNearProfessionSpellFocus` existe
donc sur Forever (build 1.60.1.70790). Les lignes `bag: … near=…` de la trace n'y étaient plus : elle ne garde que
400 lignes, remplies par celles du journal de quêtes.

## T63 — Compatibilité avec FlareUI : le suivi des quêtes et le sac (2026-11-05)

**Livré** (branche `session/2026-11-05-profession-tabs`, H38). FlareUI 2.7.0 remplace le suivi des quêtes du jeu par
le sien : l'addon y remet son bouton Lecture / Stop, le lavis doré des quêtes de la zone, la quête cliquée affichée
dans la fenêtre, et le journal de bord suit sa première quête. Le tri par niveau est celui de FlareUI. Les onglets du
sac suivent le sac quand FlareUI le déplace. **Prérequis** : `/reload` (aucun nouveau fichier) ; le suivi des quêtes
de FlareUI allumé.

| # | Action | Attendu |
|---|---|---|
| 1 | `/reload`, regarder le suivi de FlareUI | Au bout du titre de chaque quête, dans la marge de droite, le petit bouton rond de lecture ; rien sur les objectifs ni sur les noms de zone. |
| 2 | Cliquer le bouton d'une quête qui a son audio, puis le recliquer | La quête est lue (le bouton passe à Stop) ; reclic : arrêt. |
| 3 | Fenêtre de l'addon ouverte : clic gauche sur le titre d'une quête du suivi | FlareUI ouvre la quête dans le journal, et la fenêtre de l'addon montre cette quête. |
| 4 | Entrer dans la zone d'objectif d'une quête (la tache sur la minicarte) | En une seconde environ, la quête est dorée dans le suivi (lavis sur ses lignes, barre sur le titre, trait doré à droite) ; en sortant, plus rien. |
| 5 | Options de FlareUI > Suivi des quêtes > Trier par « Par niveau », puis `/fs sort` | Le suivi se trie par niveau ; le chat dit que le journal est trié et que le suivi de FlareUI se trie lui-même. |
| 6 | Rien en lecture, fenêtre ouverte, aucune quête suivie en priorité | La fenêtre montre la première quête du suivi de FlareUI. |
| 7 | Ouvrir le sac et le faire glisser par son titre | Tous les onglets (pêche, métiers, Désenchanter) suivent le sac pendant le déplacement. |
| 8 | `/reload` | Rien à coller : je lis la trace (`tracker: installed on FlareUI`, `tracker: FlareUI … quest(s)`). |

**À relever** : où le bouton tombe (chevauche-t-il le texte, la barre de défilement ?), ce qui ne s'est pas passé comme
attendu, toute erreur Lua.

**Résultat (2026-11-05)** : tout marche (« Tout marche »). La trace le confirme en partie : `tracker: installed on
FlareUI` à 09:37:48, ses redessins (4 quêtes, la première suivie), le tri laissé à FlareUI (`sort: tracker FlareUI`).
Le doré n'y apparaît pas : aucune quête dans sa zone pendant les deux minutes qu'elle couvre.

## T64 — Les fenêtres de l'addon à l'apparence de FlareUI (2026-11-05)

**Livré** (branche `session/2026-11-05-profession-tabs`, H39). Quand FlareUI tourne, la fenêtre principale, les
options et les Compagnons prennent l'apparence de sa fenêtre d'options ; sans lui, les cadres du jeu, comme avant.
**Prérequis** : `/reload` (aucun nouveau fichier) ; FlareUI activé.

| # | Action | Attendu |
|---|---|---|
| 1 | `/reload`, ouvrir la fenêtre de l'addon | Le cadre de FlareUI : bordure fine bronze, fond sombre en tuiles, un filet bronze sous la barre de titre, « ForeverSpeech » à gauche, la croix dans le coin. Plus de cadre de pierre ni de barre de titre du jeu. |
| 2 | Ouvrir la liste de lecture (bouton rond aux trois barres) | Son cadre : un fond un peu plus sombre dans un filet bronze, à la place du cadre creusé du jeu. |
| 3 | Ouvrir les options (engrenage) | Même cadre ; la ligne entre les thèmes et les réglages est bronze. |
| 4 | Ouvrir les Compagnons (icône de la barre de titre) | Même cadre ; le détail à droite comme la liste de lecture. |
| 5 | Désactiver FlareUI (liste des addons), `/reload`, rouvrir les trois fenêtres, puis réactiver FlareUI et `/reload` | Sans FlareUI : les cadres du jeu, comme avant. |
| 6 | `/reload` | Rien à coller : je lis la trace (`style: FlareUI look on the main window`, `… options …`, `… companions …`). |

**À relever** : ce qui se chevauche (le titre, les icônes de l'en-tête, la croix), le filet sous la barre de titre trop
haut ou trop bas, un fond trop sombre ou trop clair, toute erreur Lua. Une capture d'écran aide.

**Résultat (2026-11-05)** : tout marche (« Tout marche »). La trace le confirme pour la fenêtre principale :
`frame: PortraitFrameTemplate=true` puis `style: FlareUI look on the main window` à 15:50:16.

## T65 — Le nom Alliance Épique dans le jeu (2026-11-05)

**Livré** (branche `session/2026-11-05-profession-tabs`). Le nom que le joueur voit devient « Alliance Épique » (`H.TITLE`) ;
le dossier, les sauvegardes et `/fs` restent `ForeverSpeech`. **Prérequis** : **redémarrage complet** du jeu (le titre
de la liste des addons vient du TOC, lu au lancement).

| # | Action | Attendu |
|---|---|---|
| 1 | À la sélection du personnage, « AddOns » | L'addon s'appelle « Alliance Épique », avec sa nouvelle description ; il est toujours coché. |
| 2 | Entrer en jeu | Dans le chat : « Alliance Épique: chargé. /fs pour les commandes. » ; réglages et captures intacts. |
| 3 | `/fs`, puis l'engrenage | Les fenêtres s'appellent « Alliance Épique » et « Alliance Épique · Options ». |
| 4 | Échap > Options > AddOns ; Options > Raccourcis > AddOns | La catégorie et l'en-tête des raccourcis s'appellent « Alliance Épique » ; les touches choisies sont gardées. |
| 5 | Survoler l'icône de la minicarte | L'infobulle dit « Alliance Épique ». |

**À relever** : un réglage, une touche ou une capture perdus ; le nom mal affiché (accent).

**Résultat (2026-11-05)** : tout marche (« Tout marche »), après un redémarrage complet.

## T66 — La fenêtre accrochée au suivi de FlareUI, et l'avancement du groupe (2026-11-05)

**Livré** (branche `session/2026-11-05-profession-tabs`, H40). **Prérequis** : `/reload` (aucun nouveau fichier) ; FlareUI et
son suivi des quêtes allumés ; pour les étapes 6 à 8, un groupe avec quelqu'un qui a une quête en commun.

| # | Action | Attendu |
|---|---|---|
| 1 | `/reload`, ouvrir la fenêtre (`/fs`) | Collée contre le suivi de FlareUI, du côté du centre de l'écran, à quelques pixels ; les hauts alignés ; la fenêtre au moins aussi haute que le suivi. |
| 2 | La faire glisser ailleurs, puis cliquer la flèche ronde apparue à gauche des icônes de la barre de titre | Glissée : elle se décolle et reste où tu la lâches ; la flèche ronde apparaît. Clic : elle se recolle au suivi, la flèche disparaît. |
| 3 | Ouvrir la liste de lecture (bouton aux trois barres) | La fenêtre s'élargit en restant collée au suivi ; la liste entre la quête et le suivi. |
| 4 | Réduire ou déplier le suivi de FlareUI, ou le faire grandir en suivant d'autres quêtes | La fenêtre reste collée en haut ; sa hauteur suit au moins celle du suivi. |
| 5 | Options > Fenêtre de quête, décocher « Accrocher la fenêtre au suivi des quêtes de FlareUI », puis la recocher | Décochée : la fenêtre revient là où tu l'avais laissée et se déplace à nouveau ; recochée : elle se recolle. |
| 6 | En groupe, afficher une quête que l'autre a aussi | Sous les objectifs, « Le groupe » : son nom, puis ses objectifs avec leur avancement ; ceux qu'il a finis, cochés en gris. |
| 7 | L'autre avance sur un objectif | La ligne se met à jour en une seconde environ. |
| 8 | Quitter le groupe | Le bloc « Le groupe » disparaît. |
| 9 | `/reload` | Rien à coller : je lis la trace (`frame: docked right` ou `left`). |

**À relever** : un écart ou un chevauchement entre la fenêtre et le suivi, la fenêtre qui saute ailleurs, les lignes du
groupe (noms, couleurs, coches) qui ne ressemblent pas à l'infobulle de quête, toute erreur Lua. Une capture d'écran aide.

## T67 — Le thème FlareUI : polices, bronze, boutons (2026-11-05)

**Livré** (branche `session/2026-11-05-profession-tabs`, H41). Quand FlareUI tourne, le décor de la fenêtre suit FlareUI ; le
contenu peint ne change pas ; sans FlareUI, rien ne change. Le bandeau du bas (niveau et or) est retiré dans tous les
thèmes. **Prérequis** : **redémarrage complet** du jeu (nouveaux fichiers : les pictogrammes blancs).

| # | Action | Attendu |
|---|---|---|
| 1 | Ouvrir la fenêtre | Les boutons Lecture, Avancer, Stop et Liste : le pictogramme seul, en bronze frappé (pas gris), sans anneau ; plus clair au survol ; Liste plus claire tant que la liste est ouverte. Plus de bandeau en bas. |
| 2 | Regarder la barre de titre | L'engrenage et l'icône des compagnons sont ceux de FlareUI (ceux de son chat et de son compteur de dégâts), en bronze ; plus clairs au survol ou quand leur fenêtre est ouverte. La croix : un petit carré au contour bronze, comme le « − » du suivi. |
| 3 | Regarder les titres « Objectifs », « Récompenses » et l'anneau du médaillon | En bronze. Le portrait (PNJ ou Elise) et le blason de difficulté inchangés. |
| 4 | Options de FlareUI > Suivi des quêtes > Polices : changer la police des objectifs (ex. Roboto Condensed), `/reload` | Le texte de la fenêtre dans cette police, à la même taille qu'avant ; même chose pour la police des titres et des en-têtes. Remettre ensuite tes polices. |
| 5 | Regarder le suivi de FlareUI | Le bouton de lecture au bout de chaque titre : le pictogramme seul, en bronze. |
| 6 | Ouvrir la carte du monde | Les boutons en haut à droite et la page du récit du lieu : inchangés (avec leur anneau). |
| 7 | Désactiver FlareUI, `/reload`, rouvrir la fenêtre, puis réactiver FlareUI | Sans FlareUI : tout comme avant (anneaux, or, polices, croix rouge du jeu), sans le bandeau du bas ; la fenêtre glissée ailleurs, la flèche ronde la remet à sa place par défaut. |
| 8 | `/reload` | Rien à coller : je lis la trace (`style: FlareUI fonts on the main window (N)`). |

**À relever** : un bouton trop pâle ou trop sombre, un texte qui déborde avec une autre police, toute erreur Lua. Une
capture d'écran aide.

## T68 — L'interface s'efface pendant les déplacements (2026-11-05)

**Livré** (branche `session/2026-11-05-profession-tabs`, H42). **Prérequis** : **redémarrage complet** du jeu (nouveau fichier
`ui/fade.lua`).

| # | Action | Attendu |
|---|---|---|
| 1 | Hors combat, marcher tout droit 4 secondes | L'interface (barres, chat, mini-carte, suivi, fenêtre de l'addon) s'efface doucement ; au bout de 3 secondes, elle n'est plus qu'à 20 % ; la mini-carte reste affichée. Les noms au-dessus des personnages ne bougent pas. |
| 2 | S'arrêter | Elle revient à 100 % en une demi-seconde. |
| 3 | Marcher, la souris posée sur une barre d'action (ou le chat, la mini-carte) | Cet élément reste à 100 %, le reste s'efface ; la souris retirée, il s'efface à son tour. |
| 4 | Marcher en survolant un PNJ ou un joueur | Son infobulle reste lisible. |
| 5 | Marcher puis engager un combat | L'interface revient d'un coup et ne s'efface plus pendant le combat. |
| 6 | Marcher avec la carte du monde ouverte, puis en tapant dans le chat | Rien ne s'efface. |
| 7 | Prendre un griffon | L'interface s'efface pendant le vol et revient à l'atterrissage. |
| 8 | `/fs fade off`, marcher, puis `/fs fade on` | Éteint : rien ne s'efface ; rallumé : l'effet revient. |

**À relever** : un élément qui ne s'efface pas (ou ne revient pas), un clignotement, l'interface restée effacée après un
combat ou un `/reload`, toute erreur Lua (la trace dirait `fade: stopped after an error`).

**Premier essai (2026-11-05)** : l'effacement marche (« Ça marche bien »). Demandé : 20 % au lieu de 10 % pour
l'interface, la mini-carte arrêtée à 40 % pour rester un peu visible. Deuxième essai : la mini-carte « saute » ; elle ne s'efface plus
du tout, l'addon ne touche plus à son opacité (fait le même jour ; à revoir en jeu).
