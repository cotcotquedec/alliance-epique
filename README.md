# Alliance Épique

**Ton compagnon pour l'Alliance, sur World of Warcraft Forever.**

C'est mon setup personnel pour jouer à WoW Forever côté Alliance, en français : un addon fait sur mesure, et quelques
addons d'autres auteurs autour. Je le mets à disposition de ceux qui veulent une expérience proche de la mienne :
**fluide, tournée vers l'aventure, avec peu de modifications** du jeu. L'interface reste celle de Blizzard ; ce qui
s'ajoute accompagne le joueur sans le distraire. C'est un travail en cours.

Dans le jeu, l'addon s'appelle Alliance Épique ; son dossier garde son premier nom, `ForeverSpeech`, et sa
commande est `/fs`.

## Le compagnon

Les quêtes prennent vie : chaque texte est lu à voix haute, en français, par le personnage qui le dit.

- **Une voix par PNJ**, accordée à sa race, son sexe, son âge, son rôle dans le lore et l'accent de son peuple (les
  nains roulent les r). Le début d'une quête est lu quand on l'accepte, sa fin quand on la rend, avec les fenêtres
  du jeu comme avec Dialogue UI. Les dialogues des PNJ (la fenêtre de discussion) sont lus aussi.
- **Elise, la narratrice** : une sentinelle elfe de la nuit, calme et douce, qui t'accompagne du premier pas
  jusqu'à Naxxramas.
  - Elle dit les textes qu'aucun PNJ ne dit (une quête donnée par un objet ou par un lieu).
  - Elle présente chaque zone la première fois que tu y passes du temps (48 zones) ; sur la carte du monde, son récit
    du lieu, avec une peinture de la zone.
  - Elle a un mot à chaque niveau gagné : une seule histoire, du niveau 2 au niveau 60.
  - Elle lit les livres, les lettres et les plaques du monde (945 pages).
  - Elle salue tes liens avec tes compagnons de groupe.
- **La fenêtre de lecture** : le PNJ en médaillon, le titre et la difficulté de la quête, ses objectifs suivis en
  direct, ses récompenses, une liste de lecture ; un bouton ▶ dans le suivi des objectifs et dans le journal pour
  réécouter une quête.
- **Le journal des compagnons** : les joueurs avec qui tu as groupé, classés au temps passé ensemble, de la rencontre
  au frère d'armes.
- **Le confort, sans bouleverser le jeu** :
  - le son du jeu baisse pendant une lecture, et les voix d'origine des PNJ à quête se taisent ;
  - les quêtes triées par niveau, et celles dont tu es dans la zone en doré ;
  - l'annonce au groupe des quêtes terminées ;
  - une roue d'émotes : maintenir une touche, viser, relâcher ;
  - le sac à dos d'un seul tenant, déplaçable, une ligne par sac, avec des onglets pour la pêche, les métiers et le
    désenchantement ;
  - le silence en champ de bataille et en arène.

Tout se règle ou se coupe dans Échap > Options > AddOns > Alliance Épique, ou avec `/fs options`. Une quête sans
audio est lue par la synthèse vocale du jeu.

Pour le client français (frFR) et les quêtes de l'Alliance.

## Le setup complet

Les addons que j'utilise avec, tous d'autres auteurs, chacun à télécharger sur sa page. Aucun n'est obligatoire :
Alliance Épique marche seul.

| Addon | Pour quoi |
|---|---|
| [Dialogue UI](https://www.curseforge.com/wow/addons/dialogueui) | les quêtes et les dialogues dans une grande fenêtre, la caméra sur le PNJ ; Alliance Épique lit les quêtes acceptées depuis sa fenêtre |
| [FlareUI](https://www.curseforge.com/wow/addons/flareui) | une interface plus sobre et plus lisible, dans l'esprit de celle de Blizzard ; Alliance Épique s'installe dans son suivi des quêtes et prend l'apparence de ses fenêtres |
| [OpenMap](https://www.curseforge.com/wow/addons/openmap) | une carte du monde d'un seul tenant, les zones cousues entre elles |
| DungeonJournal (dossier `ForeverDungeonJournal`) | le journal des donjons : les boss, leur butin et les quêtes |
| [GTFO](https://www.curseforge.com/wow/addons/gtfo) | un son d'alerte quand tu restes dans ce qui fait mal |
| Wago App Companion | le lien avec l'application Wago |

## L'audio

Tout l'audio de l'addon a été généré : 10 632 fichiers, 3,1 Go.

- **Les PNJ** : 1 545 voix, une par PNJ, créées puis clonées en local avec Qwen3-TTS ; 2 654 débuts de quête,
  2 877 fins de quête et 3 396 pages de dialogue.
- **Elise** : sa voix ElevenLabs, pour 365 débuts et 209 fins de quête, 50 présentations de zone, 59 répliques de
  niveau, 950 pages de livres et 70 répliques sur les compagnons.

**L'audio n'est pas dans ce dépôt** : il est distribué à part, dans une archive des voix (3,2 Go) partagée par lien.
L'addon publié marche sans elle : la synthèse vocale du jeu lit alors les textes.

**Le dépôt contient tout le code pour le refaire** : l'import des données, les fiches de personnalité des PNJ, les
textes, la création des voix, les lectures, le juge automatique qui garde ou rejette chaque essai (Whisper, ECAPA)
et l'index de l'addon. La chaîne complète, étape par étape : [docs/pipeline.md](docs/pipeline.md).

**La configuration utilisée** :

- un PC Windows avec une **NVIDIA RTX 4090**, sous WSL2 (Ubuntu, PyTorch, CUDA 12.6), pour les voix des PNJ :
  **environ 72 heures** de calcul pour tout générer ;
- un Mac (Apple Silicon) pour le jeu, les tests et la voix d'Elise (API ElevenLabs) ; il peut aussi faire tourner
  Qwen3-TTS (MLX) ;
- Claude Code pour les fiches des PNJ et les textes d'Elise.

## Installer

1. Fermer le jeu.
2. Copier le dossier `ForeverSpeech` de l'archive de l'addon (`AllianceEpique-<version>.zip`, 18 Mo) dans
   `World of Warcraft/_forever_/Interface/AddOns/`.
3. Les voix, facultatives : décompresser l'archive des voix (`AllianceEpique-audio-<version>.zip`, partagée à part) dans
   le même dossier `AddOns`. Elle y ajoute le dossier `AllianceEpique_Voix`, à côté de `ForeverSpeech` : une mise à jour
   de l'addon (par CurseForge ou à la main) n'y touche pas. Sans elle, les textes sont lus par la synthèse vocale du jeu.
   Elle sert aussi aux versions suivantes de l'addon.
4. Lancer le jeu ; à la sélection du personnage, dans « AddOns », cocher Alliance Épique.
5. En jeu : `/fs` ouvre la fenêtre, `/fs options` les options.

FlareUI est une dépendance facultative : conseillé pour le setup complet (Alliance Épique en prend l'apparence quand il
est là), l'addon garde l'apparence du jeu sans lui.

Une copie du dépôt ne suffit pas : l'index de l'addon (`data/index.lua`) est généré ; il est dans l'archive de l'addon.

## Pour aller plus loin

- [docs/pipeline.md](docs/pipeline.md) : la fabrication de l'audio, étape par étape.
- [CLAUDE.md](CLAUDE.md) : les règles du projet et ses décisions ; il est développé avec Claude Code.
- [docs/ingame-tests.md](docs/ingame-tests.md) : les tests faits en jeu.

## Licence, crédits et données

- Le code de ce dépôt est sous licence MIT ([LICENSE](LICENSE)). Elle ne couvre ni les textes des quêtes, ni les
  données de la Forever Database, ni l'audio, qui ne sont pas dans ce dépôt.
- Données des quêtes et des PNJ : la Forever Database
  ([Stein-N/WoW-Quest-Database](https://github.com/Stein-N/WoW-Quest-Database), GPL-3.0), d'après QuestieDB
  (GPL-3.0), VMaNGOS (GPL-2.0) et AzerothCore. Elle est construite en local et n'est pas dans ce dépôt.
- Voix : Qwen3-TTS (génération locale) ; Elise : ElevenLabs.
- Quelques idées viennent de Spoken et de Questie, sans leur code.
- Textes des quêtes : Blizzard Entertainment. World of Warcraft est une marque de Blizzard Entertainment ; Alliance
  Épique est un projet de fan, sans lien avec Blizzard.
