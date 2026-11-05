# Constitution de la boucle livres

**Lecture seule pour la boucle.** Un humain la relit puis la scelle (`tools/loop/seal.sh books`). La boucle refuse
de tourner si elle, l'oracle, le juge, le cadre, l'arbitre, le cliquet ou les objets qu'elle réutilise (le cadre
d'Elise, le juge des voix) ont changé depuis le sceau.

## But

Chaque **page de chaque livre** du périmètre de l'Alliance (D19, 2026-10-21 : livres, lettres, plaques, stèles, tout
texte qu'on lit dans le monde, le « texte d'objet » du jeu ; **jamais le courrier**) a son **audio**, lu par
**Elise**, la narratrice (D9), avec **sa voix ElevenLabs, qui ne change pas** (`FS Elise`, `tools/elise/voice.py`),
le modèle et les réglages de ses propres répliques (`tools/elise/frame.py`). Les textes viennent de la base
(`pipeline/books/extract.py`, VMaNGOS en français), puis des scripts (`pipeline/books/scripts.py`, section `pages` de
`data/zones/@books/scripts.json`) : **le livre est lu tel qu'il est écrit**, une page = un audio, et pour une page
accordée (D8) une lecture par sexe du joueur. Les livres ne sont dans aucun groupe : un lancement les couvre avec
`--all` seulement.

L'oracle dit oui quand aucune page n'attend dans cette exécution : chacune est en place, ou n'a pas été trouvée après
5 essais ratés dans cette exécution. **Aucune page n'est abandonnée** : chaque exécution (`tools/books/run.sh`) rouvre
les pages pas trouvées (`reopen.py`).

**Un texte changé est refait** : l'audio d'une page est lié à son texte (empreinte `text_hash`), comme les répliques
d'Elise (sa voix ne change pas : pas de décision humaine).

## Un tour de boucle

1. **Acteur** (`tools/books/actor.sh`) : il juge d'abord les essais laissés par un tour interrompu. Ensuite, jusqu'à
   100 pages à faire (`--round`) reçoivent **un seul** essai : ElevenLabs lit la page en entier avec sa voix, avec
   une graine qu'elle n'a jamais eue. **Avant chaque essai** : les crédits restants du compte doivent couvrir son
   texte, sinon le tour s'arrête (code 75) et la boucle attend que les crédits reviennent ; le **budget de
   l'exécution** (`--budget N` caractères, facultatif) doit le couvrir aussi, sinon le tour s'arrête (code 76) et la
   boucle s'arrête. Puis les pages refusées sont mises en jeu quand même (D15) et l'index de l'addon est régénéré.
2. **Juge** (`tools/books/judge.py`) : Whisper large-v3 écoute chaque essai une fois. L'essai est bon si l'anglais est
   à **0,15 % au plus**, les mots mal lus à **15 % au plus**, le débit de **7 à 22 caractères par seconde** (les seuils
   du juge des voix, comme pour Elise). Bon : il devient l'audio de la page
   (`addon/ForeverSpeech/audio/1000000/book_<page>[_f].ogg`, master FLAC dans `data/audio/@books/`, entrée dans la
   section `book` de `data/zones/@books/audio.json`, avec ses scores, sa voix et l'empreinte du texte). Mauvais : il
   est supprimé, sauf s'il est le meilleur essai raté de la page (`data/voices/samples/elise/book_review/`). Après
   **5 essais ratés dans l'exécution**, la page est **pas trouvée** jusqu'à l'exécution suivante. L'état est dans
   `data/books/state.json` ; chaque verdict va dans `data/cache/loops/books/tries.jsonl`.
3. **Oracle** : il ne fait que lire ; il ne compte que les audios faits avec sa voix actuelle, pour le texte actuel,
   dont le fichier existe et dont les scores passent les seuils du juge (ou validés à la main ; refusés à la main :
   refaits).
4. **Cliquet** : pages en place et essais jugés ; ils ne peuvent que monter. `--reset-ratchet` repart du niveau du
   lancement.
5. **Critique** : le backlog dit les pages qui attendent, les caractères restants et pourquoi leurs essais échouent.

## Interdits

- Changer sa voix : seul un humain le fait, à la main.
- Écrire un texte : la boucle lit les scripts, elle ne les écrit pas (l'extraction et les scripts se lancent à la
  main, avant).
- Lire le courrier.
- Tourner à côté de la boucle Elise : mêmes crédits ElevenLabs (`run.sh` refuse, et celui d'Elise aussi).
- Dépenser au-delà des crédits du compte ElevenLabs, ou du budget de l'exécution.
