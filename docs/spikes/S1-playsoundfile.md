# S1 — `PlaySoundFile` sur un .ogg de l'addon

**Question.** `PlaySoundFile` lit-il un .ogg du dossier de l'addon sur Forever ? Que renvoie-t-il
(`willPlay`, `handle`) ? Quels séparateurs de chemin et quels canaux fonctionnent ?

**Impact si échec.** Projet bloqué (D2).

## Fichiers

Les fichiers sont générés par `tools/make_test_sounds.sh` (voix `say` « Thomas », Ogg Vorbis 44,1 kHz
stéréo).

| Fichier | Contenu | Durée |
|---|---|---|
| `audio/test/test_1.ogg` | « ForeverSpeech. Test numéro un. » | 2,54 s |
| `audio/test/test_2.ogg` | « Test numéro deux. Ceci est un son plus long… Fin du test numéro deux. » | 9,38 s |

L'encodeur Vorbis natif de ffmpeg est utilisé, car celui de Homebrew n'inclut pas libvorbis. Le fichier
est valide (vérifié avec ffprobe), mais rien ne garantit que le décodeur du client l'accepte. Si rien ne
sort à l'étape A, c'est le premier suspect.

## Procédure

Prérequis :
- volume général et volume « Dialogues » non nuls ;
- son actif ;
- de préférence, réglage « Son en arrière-plan » activé si tu changes de fenêtre.

1. Tape `/fs spike s1`. Ne touche à rien pendant 20 s. Cinq lectures s'enchaînent, espacées de
   4 s. Chacune est annoncée dans le chat (`[S1] step X …`) :

   | Étape | Appel | Attendu |
   |---|---|---|
   | A | `PlaySoundFile("Interface\\AddOns\\ForeverSpeech\\audio\\test\\test_1.ogg", "Dialog")` | « Test numéro un » |
   | B | même fichier, chemin avec `/` | « Test numéro un » (non garanti) |
   | C | même fichier, canal `"Master"` | « Test numéro un » |
   | D | même fichier, sans canal (SFX par défaut) | « Test numéro un » |
   | E | fichier inexistant, canal `"Dialog"` | silence, `willPlay` = false |

2. Le module enregistre aussi les CVars de son (`Sound_EnableDialog`, volumes…) pour diagnostiquer un
   éventuel silence.

**Commande de secours** si l'addon ne se charge pas :
`/run print(PlaySoundFile("Interface\\AddOns\\ForeverSpeech\\audio\\test\\test_1.ogg", "Dialog"))`

## À me renvoyer

- La liste des étapes entendues (A à E).
- Je lis les valeurs de retour dans le fichier SavedVariables après le `/reload` final.

## Résultat (2026-10-05, client 1.60.1.70205)

Le son est confirmé à l'oreille. Les valeurs de retour viennent de `ForeverSpeechDB.spikes.s1` :

| Étape | Retour |
|---|---|
| A, `\\` + Dialog | `true, 1293` |
| B, `/` + Dialog | `true, 1306` |
| C, `\\` + Master | `true, 1311` |
| D, sans canal | `true, 1331` |
| E, fichier absent | **aucune valeur** (`ret=()`), et non `false` |

- Les CVars son sont toutes actives, volumes à 1.0, son en arrière-plan activé.
- Le handle est un entier croissant.

## Décision

- **S1 validé : D2 tient.** `PlaySoundFile` lit les .ogg de l'addon, encodés avec le Vorbis natif de
  ffmpeg. Les chemins avec `\` comme avec `/` passent, et les canaux Dialog comme Master.
- Le code utilisera `\` et le canal `"Dialog"` par défaut (§9.7).
- **Fichier manquant = aucun retour.** Le lecteur doit donc tester `if not willPlay` et non
  `willPlay == false`, puis basculer sur le fallback (§8).
