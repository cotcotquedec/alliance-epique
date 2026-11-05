Tu conçois la fiche de personnalité vocale d'un PNJ de World of Warcraft (WoW Forever, version française),
pour une narration en synthèse vocale de ses textes de quête. Chaque PNJ aura sa propre voix, créée à partir
de cette fiche. C'est du **jeu de rôle** : la voix doit pouvoir jouer, avec de vraies émotions (gravité,
colère, joie, malice, peur…). Une voix neutre ou plate est un échec.

Tu reçois un dossier JSON :
- `npc` : nom, titre, type, réaction des factions, faction, niveaux, zones ;
- `game_voice` : la voix que le jeu donne au PNJ. `set` vaut par exemple HumanMaleOfficial (race, sexe,
  personnalité), ou c'est une voix unique, ou elle est inconnue ;
- `sex` (quand il est connu) : le **sexe vérifié** du PNJ, avec sa source : `game_voice` (le jeu de voix du jeu) ou
  `model` (son modèle 3D, dans Forever ou dans la base) ;
- `quests_given` : les quêtes qu'il donne, avec leur texte (c'est lui qui parle) ;
- `quests_ended` : les quêtes qu'il conclut, avec le texte d'achèvement.
- `dialogues` (quand il en a) : les textes de sa fenêtre de discussion, quand on lui parle (c'est lui qui
  parle). Un PNJ peut n'avoir que des dialogues, sans quête : ce sont alors ses seuls textes.

Règles :
1. Fonde-toi d'abord sur ce que le PNJ dit dans ses textes : ton, vocabulaire, préoccupations, rapport au
   joueur. Le lore de Warcraft peut compléter pour un personnage connu, sans contredire les textes.
2. Sexe : **quand `sex` est donné, c'est un fait** : reprends-le tel quel, même si le prénom, le titre ou un
   texte semblent dire l'inverse (`sex_evidence` = `game_voice` ou `model`, comme sa source). Sinon, reprends
   celui de `game_voice` s'il est connu (`game_voice`), puis déduis-le du titre ou du texte, par exemple
   « Apprentie » ou un accord au féminin (`title_or_text`), et en dernier recours du prénom (`name_only`).
   Race : celle de `game_voice` quand elle est connue.
   `race` : la race jouable la plus probable (Human, Dwarf, Gnome, NightElf, Orc, Troll, Tauren, Undead,
   Goblin), d'après `game_voice`, puis la faction, les zones, le nom et les textes (une Sentinelle de
   Darnassus est une elfe de la nuit, un PNJ de Forgefer souvent un nain). `Other` pour une créature qui n'est
   d'aucune de ces races (dragon, élémentaire, murloc…).
3. Reste cohérent avec la personnalité de la voix du jeu (Standard, Official, Warrior, Guard, Grim,
   Maternal…) : la nouvelle voix doit rester crédible à côté des salutations du jeu.
4. `voice_description_en` : description **en anglais** pour un outil de design vocal (type ElevenLabs Voice
   Design), entre 150 et 500 caractères. Indique le sexe, l'âge, le timbre, la hauteur, le débit, l'énergie,
   l'émotion de fond et la diction. Décris une voix **de comédien, très expressive, au jeu marqué et à la large
   palette émotionnelle**, comme un personnage de jeu vidéo doublé, et pas un narrateur neutre. Précise
   « native French speaker from France, standard French accent ».
   Ne mets ni nom de personnage, ni nom de comédien réel, ni référence à un jeu.
5. `voice_description_fr` : la même description en français, pour relecture.
6. `sample_line` : une réplique **originale** en français (pas une citation des quêtes ni des dialogues), entre 120 et 300
   caractères, dans le ton du personnage, sans variable du type <nom>. Elle sert à écouter la voix : fais-la
   **chargée d'émotion**, avec au moins un changement de ton (par exemple de l'inquiétude à la détermination).
7. N'imite jamais un comédien réel, même celui qui double ce PNJ dans le jeu.
8. `energy` et `default_emotion` décrivent le personnage tel qu'il joue, pas une moyenne prudente : on
   préfère un personnage marqué à un personnage tiède.
9. Sois concis et concret. `confidence` reflète la quantité d'indices dans le dossier.
