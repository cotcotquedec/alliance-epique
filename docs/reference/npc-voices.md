# Référence — Voix des PNJ dans le jeu

Constaté le 2026-10-05 sur Wowhead **Classic**, catégorie de sons « NPC Greetings » (`type 17`) :
- 275 jeux de sons (*soundkits*) ;
- environ 1 470 fichiers.

Ces voix servent au registre des voix (CLAUDE.md §11). La question de les **remplacer** ou de les **imiter**
reste ouverte : voir [Q-VOIX-1](#question-ouverte-q-voix-1--remplacer-ou-prolonger-les-voix-du-jeu-).

> Ce sont les données de Classic. Forever a pu ajouter des voix pour ses PNJ 1.60 : **non vérifié.**
> Les fichiers audio sont des assets Blizzard, joués par des comédiens de doublage. On lit leurs
> métadonnées ; on **ne télécharge et ne redistribue** pas les fichiers.

## Structure

Une voix de PNJ est un **jeu de répliques courtes** défini par trois critères : **race × sexe ×
personnalité**. La classe n'entre pas en compte. Le nom du jeu suit le motif
`<Race><Male|Female><Personnalité>NPC<Activité>`, par exemple `HumanMaleStandardNPCGreetings`.

- **58 voix distinctes** : 30 masculines, 28 féminines.
- **12 races** :
  - les 8 races jouables de Classic ;
  - plus Gobelin, Haut-elfe, Nain Sombrefer et Gnome lépreux.
- **3 activités par voix**, soit 12 à 19 fichiers au total :
  - *Greetings* (salutation) ;
  - *Farewells* (adieu) ;
  - *Pissed* (agacé, quand on clique plusieurs fois sur le PNJ).
- **Une variante « Vendor » par voix** : environ 7 à 10 salutations propres aux marchands.
- **Partage massif** : une voix couvre beaucoup de PNJ. `HumanMaleStandard`, la voix de l'Adjoint
  Willem (823), est utilisée par **189 PNJ**, selon la liste `used-by-npc` de
  `/classic/sound=5974`.

### Personnalités par race et sexe

| Race | Masculin | Féminin |
|---|---|---|
| Human | Standard, Warrior, Official | Standard, Warrior, Official |
| Dwarf | Standard, Guard, Grim | Guard, Maternal, Young |
| Gnome | Standard, Young, Zany | Standard, Happy, Nerdy |
| NightElf | Standard, Warrior, Official | Standard, Priestess, Sentinel |
| Orc | Standard, Guard, Shady | Standard, Warrior, Shaman |
| Tauren | Elder, Shaman, Warrior | Standard, Official, Shaman |
| Troll | Standard, Dark, Shaman | Standard, LaidBack, Old |
| Undead | Standard, Dark, Warrior | Standard, Warrior, Magic |
| Goblin | Gruff, Guard, Zany | Zany |
| HighElf, DarkIronDwarf, LeperGnome | Standard | Standard |

### Voix uniques (hors archétypes)

Une quarantaine de jeux sont à part.

| Catégorie | Exemples |
|---|---|
| **Personnages du lore** | Thrall, Jaina Proudmoore, Sylvanas Windrunner, Cairne Bloodhoof, Vol'jin, Magni Bronzebeard, Anduin Wrynn, Tyrande Whisperwind, Fandral Staghelm, Magatha Grimtotem, High Tinker Mekkatorque, Gazlowe, Baron Revilgaz, Archbishop Benedictus, Varimathras |
| **Types de PNJ** | Peon, Peasant, Abomination Guard, Druid of the Claw, Raider |
| **Créatures** | Dryad, Satyr, Wisp, Ancient Protector, Kodo, Thunder Lizard |
| **Mascottes** | — |

Pour ces personnages, seules les salutations sont uniques. Les cris de combat restent génériques : Thrall
utilise `OrcMale…`.

## Où lire l'information

| Besoin | Source | Marqueur |
|---|---|---|
| Voix d'un PNJ | `https://www.wowhead.com/classic/fr/npc=<id>` (la page Forever n'a **pas** cet onglet) | `new Listview({template: 'sound', id: 'sounds', …})` : `activity` (Salutation, Adieu, En colère, Attaque…), `name` (nom du jeu), `files[].url` (`wow.zamimg.com/sound-ids/classic/frfr/…`, **VF**) |
| Toutes les voix | `/classic/sounds/type:17`, qui redirige vers `/classic/sounds/npc-greetings` | `new Listview({"id":"sounds", … "data":[…]})` : JSON strict, avec des URL enUS |
| PNJ d'une voix | `/classic/sound=<soundkitID>` | `new Listview({template: 'npc', id: 'used-by-npc', …})` |

Déduire du nom du jeu de voix la race, le sexe et la personnalité d'un PNJ répond à la méthode « à
établir » de CLAUDE.md §11 pour la race des PNJ donneurs.

## Question Q-VOIX-1 : remplacer ou prolonger les voix du jeu ?

Notée le 2026-10-05. **Option A retenue** : une voix propre par PNJ (2026-10-05, dans les faits), et les
salutations et adieux du jeu **coupés** le 2026-10-10 (« pénibles maintenant que je lis les quêtes ») :
`MuteSoundFile` sur les 1 035 fichiers de la liste « NPC Greetings » ci-dessus (CLAUDE.md §9.9). Pas de
salutations de remplacement pour l'instant. Reste à vérifier en jeu que `MuteSoundFile` existe sur Forever
(`docs/ingame-tests.md`, T16).

**Option A : remplacer.** Chaque PNJ reçoit sa propre voix, qui lui donne de « l'âme ». Par exemple,
l'Adjoint Willem a sa voix à lui, utilisée pour ses quêtes et éventuellement adaptée au type de quête. Les
répliques d'origine du jeu (salutations, adieux) seraient elles aussi remplacées pour rester cohérentes.

**Option B : prolonger.** On garde les voix du jeu. Les audios générés reprennent une voix proche de
l'archétype du PNJ (race × sexe × personnalité ci-dessus), pour qu'on n'entende pas de rupture entre la
salutation du jeu et la lecture de la quête.

Éléments à instruire le moment venu :

| Point | Option A | Option B |
|---|---|---|
| Nombre de voix à concevoir | Une par PNJ nommé, plus des archétypes pour les PNJ génériques | Environ 58 archétypes, plus les voix uniques du lore |
| Cohérence avec le jeu | Il faut couper les sons d'origine, sinon le PNJ change de voix entre « Salutations » et la quête | Native, si la voix générée est proche |
| Faisabilité technique | **À vérifier** : un addon peut-il couper un son du jeu ? `MuteSoundFile(fileID)` existe en Retail, mais il est absent de la doc d'API Forever, comme `PlaySoundFile` qui existe pourtant. Il faut une sonde `type(MuteSoundFile)`. Il faut ensuite rejouer nos propres salutations sur interaction (`GOSSIP_SHOW`, `QUEST_DETAIL`, `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`). | Aucune contrainte nouvelle |
| Matière de référence | Libre : création | Les répliques du jeu, une quinzaine de fichiers courts en VF par voix |
| Droits | Création originale | Imiter ou cloner la voix d'un comédien de doublage pose une question de droits, même pour un usage personnel non distribué |

Vérification en jeu de la coupure (`MuteSoundFile` sur Forever) : `docs/ingame-tests.md`, T16.
