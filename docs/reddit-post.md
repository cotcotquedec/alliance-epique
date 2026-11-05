**Titre :** ForeverSpeech : WoW Forever entièrement voisé en français (Alliance)

Je voulais aborder WoW Forever de la manière la plus simple, la plus pure et la plus immergée possible. Alors je me suis développé un petit addon, parti d'une seule idée : entendre toutes les quêtes lues en français, avec une voix pour chacun des PNJ. De fil en aiguille, d'autres petites choses s'y sont ajoutées pour rendre l'aventure plus agréable. **Côté Alliance.**

**🎙️ Voix générées**

- **1 151 voix de PNJ** : chaque PNJ identifié a sa propre voix, créée d'après sa race, son sexe, sa région, son rôle et son histoire, avec l'accent de son peuple.
- **5 717 lectures de quêtes** : le début, lu par le donneur, et la fin, lue par le PNJ de rendu, sur plus de 3 500 quêtes (zones, donjons, raids, classes, métiers, événements).
- **388 variantes au féminin**, quand le texte s'accorde au personnage.
- **3 396 pages de dialogue de PNJ**, prêtes (lues en jeu prochainement).
- **Elise, la narratrice** (elfe de la nuit, voix à part) :
  - les quêtes qu'aucun PNJ ne donne (objet, lieu) ;
  - **50 présentations de zone**, à la première visite ;
  - **59 répliques de niveau**, du niveau 2 au niveau 60 : une seule histoire, jusqu'à la fin du jeu ;
  - **70 répliques de compagnons** (voir plus bas).
- Dans l'addon : **plus de 6 000 fichiers audio, environ 2 Go**, tirés de près de 10 Go de données générées en **plusieurs jours de génération**.
- Synthèse vocale libre (Qwen3-TTS), sur une machine locale ; chaque enregistrement est vérifié automatiquement.
- Sans audio, la synthèse vocale du jeu prend le relais.

**⚙️ Qualité de vie**

- Une fenêtre de lecture : modèle 3D du PNJ, blason de niveau, objectifs en direct, récompenses, liste de lecture (Lecture / Suivante / Stop).
- Boutons « Accepter et lire » et « Terminer et lire » ; réécoute depuis le suivi d'objectifs et le journal.
- Les voix d'origine des PNJ à quête sont coupées, pour que les deux voix ne se chevauchent pas.
- Les quêtes dont on est dans la zone sont mises en avant dans le suivi et le journal.
- Les métiers ont leurs onglets sur le sac : pêche (la canne équipée en un clic), cuisine, couture, désenchantement (les objets désenchantables s'allument).
- Un sac plus lisible : une ligne par sac, avec son nom et ses cases libres ; déplaçable.
- En groupe, annonce automatique des quêtes terminées.
- Émotes rapides : saluer, remercier, s'asseoir, féliciter.
- Réécoute de la présentation d'une zone depuis la carte du monde.

**🤝 Compagnons**

- Un compteur du temps passé en groupe avec chaque joueur (champs de bataille exclus).
- Des statuts selon le temps cumulé : **Rencontre**, **Compagnon de route** (30 min), **Camarade** (3 h), **Bon ami** (10 h), **Ami proche** (30 h), **Frère d'armes** (75 h), et **Meilleur ami** pour le n° 1.
- Des statistiques : part du temps de jeu, nombre de groupes, première rencontre…
- Le statut affiché dans l'infobulle du joueur ; Elise salue chaque palier franchi.

**🛠️ Tout est configurable**

- Une fenêtre d'options à part, en sept thèmes : Général, Lecture des quêtes, Fenêtre de quête, Elise, Compagnons, Confort, Avancé.
- La lecture : automatique ou non à l'acceptation et au rendu, pause entre deux quêtes, canal audio, ce qui se passe sans audio (voix du jeu, son, rien).
- La fenêtre : texte de la quête, niveau, cadrage du modèle 3D, retour à la quête suivie.
- Elise : présentations de zone, répliques de niveau, répliques de compagnons, chacune activable à part.
- Chaque confort s'active ou se coupe : onglets du sac, mise en avant des quêtes de la zone, annonce en groupe, bouton de la carte, sac en lignes.
- Un bouton pour tout remettre par défaut.

**🧰 Stack technique**

- **Développement** : Claude Code avec Claude Opus 5.5 (addon en Lua, pipeline de données en Python).
- **Textes** : Claude Opus pour les fiches de personnalité des PNJ (qui choisissent leur voix), les présentations de zone et les répliques de niveau d'Elise.
- **Voix des PNJ** : Qwen3-TTS, en local : VoiceDesign crée la voix de chaque PNJ depuis sa fiche et l'accent de sa race, puis le modèle Base (1,7B) la reprend pour lire chaque quête et chaque dialogue.
- **Voix d'Elise** : ElevenLabs.
- **Contrôle qualité**, à chaque essai, dans des boucles qui recommencent jusqu'à ce que ça passe :
  - Whisper large-v3 (faster-whisper) : mots mal lus, anglais égaré, débit ;
  - ECAPA (SpeechBrain) : ressemblance de chaque lecture avec la voix du PNJ.
- **Images** : Gemini (par OpenRouter) pour le portrait d'Elise et les icônes des onglets, ChatGPT pour les blasons de niveau.
- **Données** : Forever Database (QuestieDB, VMaNGOS, AzerothCore), complétée par Wowhead.
- **Machines** : un Mac Apple Silicon (MLX) et un PC avec une RTX 4090 (CUDA).
- **Audio** : ffmpeg et oggenc (Ogg Vorbis, lu par le jeu).

---

Tout est en français, et pour l'instant seulement côté Alliance. Pas de publication sur les sites d'addons, mais l'archive (environ 2 Go) est partagée volontiers sur demande, en message privé.

Et surtout : l'envie de trouver des joueurs avec qui profiter de Forever tranquillement, en prenant le temps de lire les quêtes et de découvrir le monde. Si ça vous parle, faites signe !
