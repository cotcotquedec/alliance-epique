# Constitution de la boucle Elise

**Lecture seule pour la boucle.** Un humain la relit puis la scelle (`tools/loop/seal.sh elise`). La boucle refuse
de tourner si elle, l'oracle, le juge, le cadre, l'arbitre ou le cliquet ont changé depuis le sceau.

## But

Chaque **réplique d'Elise**, la narratrice de l'addon (D9), a son **audio**, lu par ElevenLabs avec **sa voix, qui ne
change plus** (`FS Elise`, `tools/elise/voice.py`, 2026-10-10). Pour l'instant, ses répliques sont les textes de
quête qu'aucun PNJ ne dit : début et fin de quête, une réplique par sexe du joueur pour un texte accordé (D8), tels
que les scripts les donnent (`pipeline/scripts.py`). Depuis le 2026-10-11, aussi **sa présentation de chaque zone**,
dite la première fois que le joueur y pose le pied : une réplique par zone, écrite par Claude
(`pipeline/zone_intros/`), rangée dans les dossiers de présentations (`data/zones/<groupe>/@intros/`, section
`zones` de leur `scripts.json`, audio dans la section `zone` de leur `audio.json`). Les présentations d'abord, puis
catégorie par catégorie, dans l'ordre des niveaux, sur ce que le lancement couvre : `--all` (les présentations ne
sont dans aucune catégorie : avec `--all`, ou `--group G` sans `--category`), ou `--group G [--category C]…`.
Aussi **ses répliques de niveau** (2026-10-11) : une par niveau gagné (2 à 60), qui racontent une seule histoire
(`pipeline/level_lines/`, `data/zones/@elise/levels/`, section `levels`, audio dans la section `level` ; avec
`--all` seulement). Aussi **ses répliques de compagnon** (D18, 2026-10-15) : dix par palier d'amitié, l'une d'elles
dite quand un compagnon franchit ce palier, écrites à la main (`pipeline/companion_lines/`,
`data/zones/@elise/companions/`, section `lines`, audio dans la section `companion`, fichier
`1000000/<ID>_companion.ogg`, ID = place du palier × 100 + variante ; avec `--all` seulement). `--kind zone` ne fait
que les présentations de zone, `--kind level` que les répliques de niveau, `--kind companion` que les répliques de
compagnon, `--kind quest` que les répliques de quête. En jeu, sa voix remplace la synthèse vocale au `/reload`
suivant.

L'oracle dit oui quand aucune réplique couverte n'attend dans cette exécution : chacune est en place, ou n'a pas été
trouvée après 5 essais ratés dans cette exécution. **Aucune réplique n'est abandonnée** : chaque exécution
(`tools/elise/run.sh`) rouvre les répliques pas trouvées, qui repartent avec 5 essais (`reopen.py`).

**Un texte changé est refait** : l'audio d'une réplique est lié à son texte (empreinte `text_hash`). Sa voix ne
change pas, donc refaire l'audio d'un texte modifié ne demande pas de décision humaine (décidé le 2026-10-10).

## Un tour de boucle : quelques catégories

1. **Acteur** (`tools/elise/actor.sh`) : il juge d'abord les essais laissés par un tour interrompu. Ensuite, chaque
   réplique à faire reçoit **un seul** essai : ElevenLabs (`eleven_v4`) la lit en entier avec sa voix, avec une
   graine qu'elle n'a jamais eue. **Avant chaque essai**, les crédits restants doivent couvrir son texte ; sinon le
   tour s'arrête (code 75) et la boucle attend que les crédits reviennent. Puis l'index de l'addon est régénéré.
2. **Juge** (`tools/elise/judge.py`) : Whisper large-v3 écoute chaque essai une fois. L'essai est bon si l'anglais
   est à **0,15 % au plus**, les mots mal lus à **15 % au plus**, le débit de **7 à 22 caractères par seconde** (les
   seuils du juge des voix). Pas de ressemblance : sa voix est toujours la même. Bon : il devient l'audio de la quête
   (`addon/ForeverSpeech/audio/1000000/<quête>_<detail|complete>[_f].ogg`, master FLAC dans `data/audio/`, entrée
   dans `audio.json` avec ses scores, sa voix et l'empreinte du texte). Mauvais : il est supprimé, sauf s'il est le
   meilleur essai raté de la réplique (`data/voices/samples/elise/review/`). Après **5 essais ratés dans
   l'exécution**, la réplique est **pas trouvée** jusqu'à l'exécution suivante. L'état de chaque réplique est dans
   `data/elise/state.json` ; chaque verdict va dans `data/cache/loops/elise/tries.jsonl`.
3. **Oracle** : il ne fait que lire ; il ne compte que les audios d'Elise faits avec sa voix actuelle, pour le texte
   actuel, dont le fichier existe et dont les scores passent les seuils du juge.
4. **Cliquet** : répliques en place et essais jugés ; ils ne peuvent que monter. Un tour qui ne fait monter aucun
   compteur est un échec (deux de suite : arrêt). `--reset-ratchet` repart du niveau du lancement.
5. **Critique** : le backlog dit les répliques qui attendent et pourquoi leurs essais échouent.

## Interdits

- Changer sa voix : seul un humain le fait, à la main.
- Écrire un texte : la boucle lit les scripts, elle ne les écrit pas. Seule exception, **avant** la boucle : le
  lancement (`run.sh`) fait écrire par Claude les présentations de zone qui n'ont pas encore de texte
  (`pipeline/zone_intros`, 2026-10-11) et l'histoire de ses répliques de niveau si elle n'existe pas
  (`pipeline/level_lines`) ; un texte déjà écrit n'est jamais réécrit par la boucle (seulement à la main,
  `generate --zone <id>` ou `--force`).
- Tourner à côté de la boucle lectures : les deux écrivent les `audio.json` des catégories (`run.sh` refuse).
- Dépenser au-delà des crédits du compte ElevenLabs.
