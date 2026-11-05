# Spikes — Phase 0

| # | Fichier | Mode | Statut |
|---|---|---|---|
| S1 | [S1-playsoundfile.md](S1-playsoundfile.md) | en jeu | **validé** : son OK, fichier absent = aucun retour |
| S2 | [S2-new-files.md](S2-new-files.md) | en jeu | **validé** : fichier neuf lisible après `/reload` ; fichier écrasé lu seulement après redémarrage |
| S3 | [S3-savedvariables.md](S3-savedvariables.md) | en jeu | **validé** : persistance OK au reload et au redémarrage |
| S4 | [S4-hooks.md](S4-hooks.md) | en jeu | **validé** : frames de style Retail 11.x, hooks identifiés |
| S5 | [S5-sound-end-tts.md](S5-sound-end-tts.md) | en jeu | **validé** : fin via `C_Sound.IsPlaying`, `StopSound` OK, TTS FR disponible |
| S6 | [S6-wowhead-coverage.md](S6-wowhead-coverage.md) | pipeline | fait : 90 % de descriptions FR, 76 % FR + PNJ donneur |
| S7 | [S7-wowhead-crawl.md](S7-wowhead-crawl.md) | pipeline | fait : faisable, bibliothèque standard, UA honnête ; crawler retiré le 2026-11-01 (403 à tout non-navigateur) |
| S8 | [S8-npc-model.md](S8-npc-model.md) | en jeu | **validé** : `SetDisplayInfo` OK partout ; `SetCreature` seulement en cache |

## Principe

L'addon embarque un module de test (`addon/ForeverSpeech/dev/spikes.lua`) qui exécute chaque spike
via `/fs spike …`. Chaque résultat est **affiché dans le chat** et **enregistré dans
`ForeverSpeechDB.spikes`**.

**Tu n'as pas besoin de recopier le chat.** Le fichier
`/Applications/World of Warcraft/_classic_beta_/WTF/Account/<COMPTE>/SavedVariables/ForeverSpeech.lua`
est sur ce Mac et je peux le lire directement. Le client l'écrit au `/reload` et à la déconnexion.
Ce que toi seul peux me dire, c'est ce que tu **entends** et ce que tu **vois**. La fiche de retour
en bas de page sert à ça.

En secours, si le fichier n'est pas écrit (voir S3) : `/fs spike dump` ouvre une fenêtre de texte
déjà sélectionné. Fais Cmd+C, puis colle-le ici.

## Mise en place (une fois)

1. Le lien symbolique est déjà créé : `…/_classic_beta_/Interface/AddOns/ForeverSpeech → addon/ForeverSpeech`.
   Pour le recréer : `tools/link_addon.sh`.
2. **Jeu fermé** : `tools/spike_s2.sh prepare` (prépare les fichiers de S2 ; script retiré le 2026-10-07, historique git).
3. Lance le jeu. Sur l'écran de sélection du personnage, ouvre **AddOns** et vérifie que **ForeverSpeech** est
   listé.
   - S'il est marqué « périmé » (out of date), coche « Charger les addons périmés ». Note-le : cela veut
     dire que `## Interface: 16001` est faux.
   - S'il n'est pas listé du tout : le client ne suit pas les liens symboliques. Dis-le-moi, je passerai
     par une copie.
4. En jeu, sans BugSack : `/console scriptErrors 1` pour afficher les erreurs Lua.
5. `/fs` doit afficher la liste des commandes. `/dump select(4, GetBuildInfo())` donne la version
   d'interface.

## Déroulé conseillé (deux lancements du jeu, ~25 min)

**Lancement 1** (après `tools/spike_s2.sh prepare`) :
S1 → S2 étapes 1 à 4 → S3 étapes 1 à 3 → S4 → S5 → S8 → `/fs spike api` → `/reload` → envoie-moi la
fiche de retour.

**Quitte complètement le jeu**, puis **lancement 2** : S2 étape 5 et S3 étapes 4 et 5. Dis-moi « fait ».

## Fiche de retour (à copier-coller et compléter)

```
Installation : addon listé ? oui/non | marqué périmé ? oui/non | interface = .....
S1 : entendu A ? B ? C ? D ? E ?   (E = fichier absent, normalement silence)
S2 : run 1-initial      new = silence/un/deux   slot = un/deux
     run 2-after-change new = ...               slot = ...
     run 3-after-reload new = ...               slot = ...
     run 4-after-restart new = ...              slot = ...
S3 : rien à dire si les étapes ont été faites (je lis le fichier)
S4 : captures d'écran faites ? oui/non ; remarques sur l'emplacement du bouton
S5 : A joué jusqu'au bout ? | B coupé après ~2 s ? | phrase TTS entendue ? (voix, langue)
S8 : A (SetCreature) = modèle/vide/erreur | B (SetDisplayInfo) = ... | C (SetUnit) = ...
Erreurs Lua vues : ...
```

## Résultats de l'installation (2026-10-05)

- L'addon est chargé via le lien symbolique : le client suit les symlinks.
- `/fs` répond.
- Interface : `select(4, GetBuildInfo())` → `16001, "", " "`. La valeur `## Interface: 16001` est donc
  correcte. `GetBuildInfo` renvoie au moins 6 valeurs.
- Le chat interprète `|` comme un échappement (`|h`, `|r`…). Tout texte littéral affiché doit avoir ses
  `|` doublés (`ForeverSpeech.Escape`).
- `QUEST_WATCH_LIST_CHANGED` se déclenche avec une charge `(nil, nil)` sur Forever.
- Sondes d'API (`ForeverSpeechDB.spikes.env`) : l'API de quêtes est **de type Retail**.
  - Absents : `GetQuestLogTitle`, `SelectQuestLogEntry`, `GetQuestLogSelection`, `GetNumQuestWatches`,
    `GetMouseFocus`, `LoadAddOn`, `Enum.VoiceTtsDestination`.
  - Présents : `C_QuestLog.*`, `GetMouseFoci`, `C_AddOns.LoadAddOn`, `C_Sound.IsPlaying`,
    `C_VoiceChat.SpeakText`, `C_TTSSettings`.
  - `WOW_PROJECT_ID = 18`.
