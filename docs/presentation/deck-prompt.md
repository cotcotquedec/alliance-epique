# Prompt : deck de présentation de ForeverSpeech

À coller tel quel dans l'agent de design.

---

Crée un deck de présentation (16:9, en français, environ 18 slides) sur mon projet personnel **ForeverSpeech**.

**Public** : des développeurs ou des personnes techniques qui n'ont **jamais travaillé avec des boucles d'agents
autonomes**. À la fin, ils doivent comprendre comment une boucle de génération peut tourner seule toute une nuit sans
dériver, et pourquoi chaque rôle existe. Ton sobre et pédagogique, pas marketing. Une idée par slide, peu de texte,
des schémas dès que possible. Ajoute des notes d'orateur courtes sous chaque slide, avec le contenu détaillé
ci-dessous que la slide n'affiche pas.

**Fil conducteur** : une analogie d'examen, introduite slide 9 et reprise ensuite. L'élève passe l'examen (acteur), le
correcteur note chaque copie (juge), le secrétariat recompte les diplômes dans les registres (oracle), le tableau des
records ne fait que monter (cliquet), le proviseur décide de la suite (arbitre), le professeur principal écrit les
appréciations (critique), le règlement est sous scellés (constitution et sceau).

Pas de logos, d'images ni de captures officielles de World of Warcraft ou de Blizzard.

## Partie 1 : le projet

### Slide 1 : titre
ForeverSpeech : les quêtes de World of Warcraft lues à voix haute, en français, avec une voix propre à chaque
personnage.

### Slide 2 : à quoi ça sert
Dans le jeu, une quête est un bloc de texte qu'on lit rarement. Avec ForeverSpeech, quand on accepte une quête, le
personnage qui la donne la raconte, avec une voix cohérente avec sa race, son sexe, son âge et son caractère. Quand
on la rend, le personnage qui la reçoit dit le texte de fin.
Visuel : un parcours en 3 temps : j'accepte la quête → le personnage parle → je peux réécouter depuis le journal.

### Slide 3 : les trois briques
Trois colonnes, avec pour chacune une ligne de rôle et la techno :
1. **Addon** : ce qui tourne dans le jeu (Lua).
2. **Data** : la génération des textes, des voix et des audios (Python, Claude, Qwen3-TTS en local).
3. **Contrôle** : le banc d'écoute, une page web locale pour écouter et vérifier ce que la génération produit.
Flèche : Data produit les fichiers audio → Addon les joue ; Contrôle regarde Data.

### Slide 4 : brique Addon (rapide)
- Bouton « Accepter et lire », lecteur avec liste de lecture (Lecture, Avancer, Stop).
- Réécoute depuis le suivi des objectifs et le journal de quêtes.
- Capture du texte exact affiché en jeu, qui sert ensuite à la génération.
- Pas encore d'audio pour une quête : synthèse vocale du jeu en secours.
Message : la partie simple ; une contrainte forte (un addon n'a ni réseau ni écriture de fichiers), donc tout le
travail lourd se fait hors du jeu.

### Slide 5 : brique Data, la chaîne de production
Frise de 4 étapes, chacune étant une boucle autonome :
1. **Base** : construit la base des quêtes et des personnages, rangée par catégorie (zone, classe, donjon…).
2. **Texte** : une fiche de personnalité par personnage (écrite par Claude) et le script de chaque quête.
3. **Voix** : une voix modèle par personnage, 15 à 20 s, inventée par Qwen3-TTS depuis sa fiche et l'accent de sa
   race.
4. **Lectures** : l'audio de chaque quête, lu en clonant la voix modèle du personnage.
Chiffres (7 octobre 2026) : 117 catégories, 3 580 quêtes, 1 159 personnages qui parlent, environ 5 200 textes à
lire. Première zone complète : la Forêt d'Elwynn, 41 voix et 129 lectures sur 129.

### Slide 6 : brique Contrôle, le banc d'écoute
Une page web locale (http://127.0.0.1:8765) branchée sur les données en direct : elle suit les boucles pendant qu'elles
tournent.
- Une catégorie à la fois ; deux vues : les lectures des quêtes, ou les voix modèles.
- Pour chaque lecture : son état (en place, à faire, pas trouvée, attend sa voix), l'audio, les notes du juge et la
  voix modèle à côté pour comparer.
- Filtres par état, par personnage, début ou fin de quête.
Message : la machine juge ce qui se mesure ; l'oreille humaine juge le reste, ici.
Visuel : maquette simple d'un tableau de lectures avec un bouton lecture, des scores et un badge d'état.

## Partie 2 : pourquoi des boucles

### Slide 7 : le problème
- Des milliers d'audios à produire, plusieurs essais pour chacun : des nuits entières de calcul.
- Une IA générative ne réussit pas à tous les coups : accent anglais, mots sautés, voix qui ne ressemble pas au
  personnage.
- Personne ne surveille la nuit.
Question à afficher : comment laisser une machine travailler seule des heures, sans qu'elle s'arrête au premier
échec, ni qu'elle déclare victoire à tort, ni qu'elle casse ce qui marchait ?

### Slide 8 : l'idée en une phrase
**Une boucle répète un petit travail jusqu'à ce qu'un contrôle indépendant dise que le but est atteint.**
Et la règle n° 1 : **la boucle n'écrit jamais son propre critère de succès.**
Note d'orateur : sinon, le moyen le plus simple de « réussir » serait de baisser la barre.

## Partie 3 : exemple détaillé, la boucle Lectures

### Slide 9 : les sept rôles
Schéma : les sept rôles autour de la boucle, chacun avec son équivalent dans l'analogie d'examen.

| Rôle | Ce qu'il fait | Analogie |
|---|---|---|
| Constitution | le but, les interdits, écrits une fois pour toutes | le règlement de l'examen |
| Acteur | fait le travail, une catégorie à la fois ; le seul qui écrit les données | l'élève |
| Juge | note chaque essai audio, garde ou jette | le correcteur |
| Oracle | recompte ce qui est fait, dit si le but est atteint | le secrétariat qui recompte les diplômes |
| Cliquet | le niveau le plus haut atteint ; il ne peut que monter | le tableau des records |
| Arbitre | décide : continuer, attendre, revenir en arrière ou arrêter | le proviseur |
| Critique | note ce qui manque et pourquoi ; ne valide jamais | le professeur principal |

### Slide 10 : le but (la constitution)
Chaque texte de quête dont le personnage a sa voix modèle a son audio : le début (dit par le donneur), la fin (dite
par le personnage qui reçoit la quête), et deux versions quand le texte s'accorde au sexe du joueur.
Interdits affichés en 4 icônes :
- jamais régénérer une lecture déjà validée ;
- jamais perdre de données ;
- jamais réutiliser une graine pour une même lecture, pour que chaque nouvel essai soit vraiment différent ;
- ne jamais toucher aux autres boucles (voix, fiches, scripts) ni au réseau.

### Slide 11 : un tour de boucle
Grand schéma en cycle :
**PLANIFIER → AGIR → ARBITRER → CRITIQUER → (retour à PLANIFIER)**
- Planifier : l'oracle désigne la catégorie suivante ; les données que l'essai peut modifier sont sauvegardées.
- Agir : l'acteur traite cette catégorie.
- Arbitrer : on vérifie le sceau, l'oracle recompte, l'arbitre compare au cliquet.
- Critiquer : le critique écrit ce qui manque dans un backlog.
Chaque tour est un nouveau processus : rien ne traîne d'un tour à l'autre.

### Slide 12 : l'acteur et le juge, un essai à la fois
Schéma en entonnoir :
1. Pour chaque lecture à faire, **un seul essai** par tour, avec une graine jamais utilisée : Qwen3-TTS clone la voix
   modèle du personnage et lit le script, paragraphe par paragraphe.
2. Le juge écoute l'essai :
   - Whisper (reconnaissance vocale) vérifie que c'est du français bien lu : anglais ≤ 0,15 %, mots mal lus ≤ 15 %,
     débit de 7 à 22 caractères par seconde ;
   - ECAPA (empreinte de voix) vérifie que c'est la même voix que la voix modèle : ressemblance ≥ 0,75.
3. Bon : l'essai devient l'audio de la quête, dans l'addon. Mauvais : supprimé, sauf s'il est le meilleur raté,
   gardé pour l'écoute humaine.
Détail : la génération tourne sur la carte graphique pendant que le juge tourne sur le processeur, en parallèle.

### Slide 13 : comment on a choisi les seuils du juge
- **Ressemblance 0,75** : mesurée, pas devinée. Sur 16 essais d'un même personnage (l'Adjoint Willem), la même voix
  donne 0,80 à 0,94 ; une autre voix donne 0,19 à 0,31. Le seuil est placé dans le trou entre les deux.
- **Anglais et mots mal lus** : réglés à l'oreille ; assouplis le 7 octobre (de 0,10 % à 0,15 % et de 12 % à 15 %)
  après écoute d'essais rejetés qui étaient bons.
- **Limite assumée** : le juge mesure la diction et le timbre, pas le jeu d'acteur. Ça, c'est le banc d'écoute.
Visuel : une réglette avec deux nuages de points (même voix, autre voix) et le seuil entre les deux.

### Slide 14 : l'oracle, comment on l'a choisi
- Il **ne fait que lire** et ne croit pas l'acteur sur parole : il recompte depuis les fichiers.
- Une lecture compte comme faite seulement si le fichier audio existe vraiment **et** si ses notes enregistrées
  passent encore les seuils du juge (revérifiées à chaque fois, sans réécouter).
- Il répond trois choses : le but est-il atteint ? quel est le niveau ? quelle catégorie ensuite ?
- Une lecture dont le personnage n'a pas encore de voix modèle n'est pas « à faire » : elle attend la boucle Voix.
Principe à afficher : un oracle doit pouvoir dire **non**.

### Slide 15 : le cliquet, comment on l'a choisi
- Deux compteurs : **lectures en place** et **essais jugés**. Ils ne peuvent que monter.
- Pourquoi compter les essais jugés ? Sur une catégorie difficile, un tour peut ne valider aucune lecture tout en ayant
  fait son travail (des essais jugés et rejetés). Sans ce compteur, la boucle croirait n'avoir rien fait et
  s'arrêterait.
- Un compteur qui baisse = perte de données → retour arrière, mise en quarantaine, arrêt.
- Le contrôle se fait aussi au démarrage, pour détecter une perte entre deux lancements.
Exemple vécu (7 octobre au soir, boucle Texte) : au lancement, la boucle refuse de démarrer, un compteur est passé de
30 à 29. Enquête : aucune donnée perdue, c'est la règle de comptage qui avait changé. Un humain l'a constaté et a
relancé avec `--reset-ratchet`. La machine s'arrête, l'humain tranche.

### Slide 16 : l'arbitre, ce qu'il décide
Tableau de décision, en fonctions pures (mêmes entrées → même décision) :

| Situation après un tour | Décision |
|---|---|
| un compteur sous le cliquet | retour arrière, quarantaine, arrêt |
| l'oracle dit « but atteint » | fin |
| progrès | tour suivant dans 1 min |
| pas de progrès | nouvel essai dans 5 min ; deux fois de suite : arrêt avec la fin du journal |
| limite d'usage du service | attente jusqu'à la reprise (sinon 30 min, 1 h, 2 h), ce n'est pas un échec |
| environnement des voix absent | arrêt, avec la commande à lancer |
| 1 000 tours | arrêt de sécurité |

### Slide 17 : jamais d'abandon, et le sceau
Deux blocs côte à côte :
- **Jamais d'abandon** : une lecture a 5 essais par exécution. Après 5 échecs, elle est « pas trouvée » pour cette
  nuit, ce qui laisse avancer les autres. L'exécution suivante la rouvre avec 5 nouveaux essais. Rien n'est jamais
  abandonné.
- **Le sceau** : la constitution, l'oracle, le juge, l'arbitre et le cliquet sont relus par un humain, puis leur
  empreinte (SHA-256) est enregistrée et commitée. Si un seul de ces fichiers change, la boucle refuse de démarrer, et
  s'arrête avant chaque arbitrage. C'est la règle n° 1 rendue concrète.

### Slide 18 : ce que l'humain garde
Ce que la machine fait seule : générer, juger, recompter, réessayer, attendre, revenir en arrière.
Ce que l'humain décide : relire et sceller les règles, régler les seuils, accepter une baisse du cliquet, refaire la
voix modèle d'un personnage qui se clone mal (le critique la signale), écouter au banc.
Conclusion : le même schéma (but fixe, acteur, juge, oracle, cliquet, arbitre, critique, sceau) vaut pour toute
génération par IA longue et sans surveillance. Ici, quatre boucles l'appliquent : Base, Texte, Voix et Lectures.
