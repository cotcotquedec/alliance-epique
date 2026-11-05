# S10 — Couper les voix du jeu des PNJ (`MuteSoundFile`)

**Question.** Sur Forever 1.60.1, `MuteSoundFile(fileID)` coupe-t-il les salutations et adieux des PNJ (CLAUDE.md
§9.9) ? Les identifiants de fichiers de Classic (liste Wowhead « NPC Greetings ») sont-ils ceux que Forever joue ?

**Impact.** En cas d'échec, les voix du jeu restent ; autre piste : couper le canal « Dialogue » pendant
l'interaction avec un PNJ (CVar `Sound_EnableDialog`) et jouer nos lectures sur un autre canal.

## Premier essai (2026-10-10, T16)

- Le journal dit `game voices: muted 1035 of 1035 files` au chargement : `MuteSoundFile` existe et ne lève pas
  d'erreur.
- Pourtant les PNJ saluent et disent au revoir comme avant.
- La liste n'est pas en cause côté Classic : les 304 salutations, adieux et répliques agacées des pages PNJ Wowhead
  Classic **en français** du cache y sont toutes (les identifiants de fichiers ne dépendent pas de la langue).

Trois hypothèses :
1. `MuteSoundFile` existe mais ne fait rien sur Forever ;
2. le jeu annule les coupures après le chargement de l'addon (écran de chargement, entrée dans le monde) ;
3. Forever joue d'autres fichiers que Classic pour ces voix.

## Procédure

Voix de l'Adjoint Willem, `HumanMaleStandard` (189 PNJ) : salutation `552196`
(`HumanMaleStandardNPCGreetings01`), jeu de sons des salutations `5974`. Canal Master pour être sûr d'entendre.

`/fs npcvoices test` (2026-10-10) fait le test tout seul, une étape toutes les 3 s, numérotée dans le chat :

| Étape | Son joué | État |
|---|---|---|
| 1, 2 | le fichier, puis le jeu de sons | coupé au chargement de l'addon |
| 3, 4 | le fichier, puis le jeu de sons | coupé de nouveau, à l'instant |
| 5, 6 | le fichier, puis le jeu de sons | rétabli |

À la fin, le réglage est réappliqué ; parler alors à un garde humain dit si une coupure faite après l'entrée dans le
monde tient. Les réponses du client (`PlaySoundFile` / `PlaySound` : `willPlay`, `handle`, `C_Sound.IsPlaying`)
vont dans le journal (`S10 step …`), lu après `/reload`. À me dire : entendu ou silence pour chaque étape, et si le
garde salue.

## Lecture des résultats

| Étapes 1-2 | Étapes 3-4 | Étapes 5-6 | Conclusion |
|---|---|---|---|
| silence | — | entendu | La coupure marche sur ces fichiers ; si les PNJ parlent encore, Forever joue **d'autres fichiers** (3). |
| entendu | silence | entendu | Les coupures sont **annulées après le chargement** (2) : les refaire à l'entrée dans le monde. |
| entendu | entendu | entendu | `MuteSoundFile` **ne fait rien** sur Forever (1) : autre piste (canal Dialogue). |
| silence | silence | silence | Le fichier `552196` **n'existe pas** dans Forever (3). |

Si le fichier est silencieux mais le jeu de sons entendu : le jeu de sons `5974` de Forever joue d'autres fichiers (3).

## Résultat

**2026-10-10** (`/fs npcvoices test`) : silence aux étapes 1 à 4, entendu aux étapes 5 et 6. Donc :
- `MuteSoundFile` **marche** sur Forever, et la coupure faite au chargement de l'addon **tient** ;
- le fichier `552196` et le jeu de sons `5974` existent dans Forever et jouent les fichiers de la liste.

Les voix encore entendues sont celles des **PNJ ajoutés par Forever** : Falorne Fallwind (251371), Yala Windwatcher
(249363), Rorian the Dayseeker (251361), quêtes 92xxx. Ils n'ont pas de données de voix Classic
(`game_voice.reason = no_game_voice_data` dans les registres), et Wowhead n'a pas de liste de sons Forever. La liste
Classic ne peut donc pas les couper.

## Décision (2026-10-10)

**Garder la coupure par fichier** (les PNJ de Classic se taisent, ceux ajoutés par Forever continuent de parler), et
**ne couper qu'avec les PNJ qui ont une quête pour le joueur** (demandé le 2026-10-10 ; CLAUDE.md §9.9). Pistes écartées pour l'instant :
- couper le volume « Dialogue » pendant chaque interaction avec un PNJ (nos lectures sur le canal Principal) ;
- lire la liste exacte des voix de Forever dans les données du jeu installé (archives CASC, tables `NPCSounds` et
  `SoundKitEntry`) : nouvelle dépendance, à refaire à chaque mise à jour du jeu.
