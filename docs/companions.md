# Journal des compagnons (D18, critères validés le 2026-10-14)

Un registre des joueurs avec qui le personnage a groupé, le temps passé ensemble, un palier d'amitié, quelques
statistiques, et une réplique d'Elise à chaque palier franchi. Critères validés le 2026-10-14, **codé le
2026-10-15** : `core/companions.lua` (suivi, paliers, statistiques, Elise), `ui/companions_panel.lua` (onglet,
panneau, infobulle), index v8 (`pipeline/build_index.py`) ; test en jeu : T27 (`docs/ingame-tests.md`). Les
répliques d'Elise : [`data/zones/@elise/companions/scripts.json`](../data/zones/@elise/companions/scripts.json).

**Audio** (2026-10-15) : la boucle Elise fait les 70 répliques (`tools/elise/run.sh --all --kind companion`, machine
du PC, environ 6 350 caractères ElevenLabs) : section `companion` de `data/zones/@elise/companions/audio.json`,
clé = ID de la réplique (`401`), fichier `audio/1000000/<ID>_companion.ogg` ; l'index est refait à chaque tour
(`pipeline/companion_lines/`). **Reste à faire** : lancer la boucle sur le PC. Sans audio, Elise ne dit rien d'elle-même
(`/fs friends say <palier>` lit une réplique par la synthèse vocale du client).

## 1. Ce qui compte comme temps ensemble

- **Groupe** : tous les membres. **Raid** : seulement le sous-groupe du joueur (5 personnes au plus), sinon un raid
  de 40 remplit la table d'inconnus. **Champs de bataille exclus** (groupes de hasard).
- Le temps ne compte que pour un membre **connecté**.
- Un groupe compte (nombre de groupes, palier « Rencontre ») à partir de **5 minutes ensemble** : une invitation pour
  un échange ou une invocation ne gonfle rien.
- **Table de 100 compagnons par personnage**. Pleine, celui qui a le moins de temps cède sa place.
- Un compagnon est reconnu par l'identifiant du personnage (`UnitGUID`), pas par son nom ; le dernier nom vu, sa
  classe et son sexe (`UnitSex`, pour le palier au féminin) sont gardés.
- Les compteurs en cours sont repliés dans le total à chaque départ, à la fin du groupe, à la déconnexion et chaque
  minute (un plantage du jeu ne perd qu'une minute au plus).
- Le groupe ouvert est enregistré : après un `/reload` ou une courte déconnexion (10 min au plus), c'est le même
  groupe qui continue (pas un groupe de plus).

## 2. Les paliers d'amitié

Le temps cumulé ensemble donne le palier. Clés et seuils dans le JSON des répliques (`tiers`).

| Palier (clé) | À partir de |
|---|---|
| Rencontre (`encounter`) | 5 min (un groupe compté) |
| Compagnon de route (`travel_companion`) | 30 min |
| Camarade (`comrade`) | 3 h |
| Bon ami / Bonne amie (`good_friend`) | 10 h |
| Ami proche / Amie proche (`close_friend`) | 30 h |
| Frère d'armes / Sœur d'armes (`brother_in_arms`) | 75 h |
| **Meilleur ami / Meilleure amie** (`best_friend`) | le n° 1 de la table, avec au moins 10 h |

« Meilleur ami » est unique : il change de main quand un autre compagnon passe devant.

## 3. Les statistiques

Par compagnon :
- temps ensemble, et **part du temps de jeu total** (« 17 % de votre temps de jeu » ; le total vient de
  `TIME_PLAYED_MSG`, demandé à l'entrée en jeu, `core/played.lua`) ;
- part du temps passé en groupe ;
- nombre de groupes, plus longue session ensemble ;
- première rencontre : date, zone, niveau du joueur ; dernière fois vu ;
- ensemble : donjons faits (entrée dans une instance de groupe), quêtes rendues, niveaux gagnés.

Global : temps en groupe et en solo, nombre de compagnons.

## 4. L'affichage

- **A. Infobulle** d'un joueur (cadres de groupe, monde, cible) : deux lignes de plus, « Bon ami · 12 h 40
  ensemble » et « 23 groupes · 17 % de votre temps ». Rien de posé à l'écran.
- **B. Journal** : un onglet sur le côté de la fenêtre (comme la pêche) ; le top 10 (rang, nom en couleur de classe,
  palier, temps) ; un clic sur un nom ouvre ses statistiques.
- **C. Insigne sur les cadres de groupe** (cœur, étoile selon le palier) : **plus tard**, après un test en jeu des
  cadres de groupe de Forever (d'autres addons s'y greffent).
- Option : à l'arrivée d'un compagnon connu, une ligne dans le chat (« Arthas rejoint le groupe — Bon ami, 12 h
  ensemble »).

## 5. Elise à chaque palier franchi

- Quand un compagnon franchit un palier, Elise dit **une des 10 répliques de ce palier, au hasard** ; elle passe dans
  la liste de lecture comme une réplique de niveau (D17), avec le nom du compagnon et son palier dans la fenêtre.
- Au hasard **sans redite** : les 10 répliques d'un palier passent toutes avant qu'une revienne (tirage retenu par
  personnage).
- **Plusieurs paliers à la fois** (deux compagnons, ou « Bon ami » et « Meilleur ami » au même moment) : une seule
  réplique, celle du palier le plus haut.
- **Rencontre** : au plus une réplique par groupe (un groupe de cinq inconnus ne la déclenche qu'une fois).
- Automatique seulement avec son audio ; `/fs friends on|off` et une case dans les options.
- **Écriture** (pour l'audio enregistré une fois pour toutes) : jamais le nom du compagnon, jamais d'accord selon
  son sexe ni celui du joueur (ni « il », ni « elle », ni « ami », ni « réunis ») ; vouvoiement ; aucun mot de jeu
  ni chiffre ; chaleur en crescendo d'un palier à l'autre, le fil d'Elise (la sentinelle du Mur du scarabée, celui
  qu'elle aimait) seulement aux paliers les plus hauts. 70 répliques, environ 6 000 caractères ElevenLabs.
- Audio par la boucle Elise (`--kind companion`), comme les répliques de niveau.
- Dans l'index (v8), une réplique a pour ID la place de son palier × 100 + sa variante (401 : « Bon ami »,
  réplique 1) ; la fenêtre la titre « Bon ami · Arthas ».

## 6. À vérifier en jeu (non garanti sur Forever)

`GROUP_ROSTER_UPDATE`, `GetNumGroupMembers`, `IsInRaid`, `UnitGUID("partyN")` (format `Player-…`),
`GetRaidRosterInfo` (sous-groupe), `UnitIsConnected`, `IsInInstance` (type `party`, `pvp`), l'ajout de lignes à
l'infobulle d'un joueur (`TooltipDataProcessor` de Retail, ou `OnTooltipSetUnit` de Classic). Une demande de la file
en jeu, avant ou avec la première version.
