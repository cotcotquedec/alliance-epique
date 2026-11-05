# Constitution de la boucle lectures

**Lecture seule pour la boucle.** Un humain la relit puis la scelle (`tools/loop/seal.sh readings`). La boucle
refuse de tourner si elle, l'oracle, le juge, le cadre, l'arbitre ou le cliquet ont changé depuis le sceau.

## But

Chaque texte de quête dont le PNJ a une **voix modèle** (boucle voix) a son **audio** : le début de quête (dit par
le donneur), la fin de quête (dite par le PNJ de rendu) et, pour un texte accordé (D8), une lecture par sexe du
joueur. Catégorie par catégorie, dans l'ordre des niveaux, sur ce que le lancement couvre : `--all`, ou
`--group G [--category C]…`, et `--npc` en plus. En jeu, la voix remplace la synthèse vocale au `/reload` suivant.

L'oracle dit oui quand aucune lecture couverte n'attend dans cette exécution : chacune est en place, ou n'a pas été
trouvée après 5 essais ratés dans cette exécution. **Aucune lecture n'est abandonnée** : chaque exécution
(`tools/readings/run.sh`) commence par rouvrir les lectures pas trouvées, qui repartent avec 5 essais
(`reopen.py`). Une lecture dont le PNJ n'a pas encore de voix modèle attend la boucle voix.

## Un tour de boucle : une catégorie

1. **Acteur** (`tools/readings/actor.sh`) : il juge d'abord les essais laissés par un tour interrompu (ceux d'une
   lecture déjà en place sont jetés), puis récupère les meilleurs essais gardés qui passent les seuils du moment
   (seuils assouplis). Ensuite, chaque lecture à faire reçoit **un seul** essai, avec une graine qu'elle n'a jamais
   eue : Qwen3-TTS 1.7B **Base** clone la voix modèle du PNJ et lit le script, paragraphe par paragraphe. La
   génération (puce graphique) et le juge (processeur) tournent côte à côte. Puis l'index de l'addon est régénéré.
2. **Juge** (`tools/readings/judge.py`) : Whisper large-v3 écoute chaque essai une fois, ECAPA compare son timbre à
   la voix modèle. L'essai est bon si
   - l'anglais est à **0,15 % au plus**, les mots mal lus à **15 % au plus**, le débit de **7 à 22 caractères par
     seconde** (les seuils du juge des voix) ;
   - la **ressemblance avec la voix modèle est d'au moins 0,75** (même voix : 0,80 à 0,94 ; une autre : 0,2 à 0,3).
   - **un essai court** (2026-10-12, décidé par l'utilisateur) : ressemblance d'au moins **0,65 sous 3 s** et **0,70
     de 3 à 5 s**, anglais jusqu'à **0,5 % sous 5 s** (sur quelques secondes, ECAPA et la langue de Whisper ne sont
     pas fiables) ; au-delà de 5 s, rien ne change.

   Bon : il devient l'audio de la quête (`addon/ForeverSpeech/audio/<pnj>/<quête>_<detail|complete>[_f].ogg`, master
   FLAC dans `data/audio/`, entrée dans `audio.json` avec ses scores). Mauvais : il est supprimé, sauf s'il est le
   meilleur essai raté de la lecture, gardé dans `reading_review/`. Après **5 essais ratés dans l'exécution**, la
   lecture est **pas trouvée** jusqu'à l'exécution suivante. L'état de chaque lecture est dans le `readings.json` de
   sa catégorie ; chaque verdict (et chaque essai gardé récupéré) va dans `data/cache/loops/readings/tries.jsonl`.
3. **Oracle** : il ne fait que lire ; il ne compte que les lectures Qwen3 dont le fichier existe et dont les scores
   passent les seuils du juge.
4. **Cliquet** : lectures en place et essais jugés (archives comprises) ; ils ne peuvent que monter. Un tour qui ne
   fait monter aucun compteur est un échec (deux de suite : arrêt). `--reset-ratchet` repart du niveau du lancement.
5. **Critique** : le backlog dit les lectures qui attendent et pourquoi leurs essais échouent, celles qui attendent
   une voix modèle, et le taux d'échec par PNJ. Un PNJ dont les lectures échouent sur la ressemblance : sa voix
   modèle se clone mal, la refaire est une décision humaine (`tools/voices/redo.py`).

## Le cadre (scellé)

`tools/readings/frame.py` : le texte lu (script de la quête en texte simple, formes « masculin/féminin » résolues),
le modèle (Qwen3-TTS 1.7B Base), la langue, le découpage en paragraphes et 0,35 s de silence entre eux, le volume
(-20 LUFS). Le changer est une décision humaine ; les lectures en place sont gardées.

## Interdits

- **Jamais de régénération** d'une lecture en place.
- **Jamais de perte** : le niveau ne baisse jamais.
- **Jamais de graine réutilisée** pour une même lecture.
- **Ne pas toucher** aux voix modèles (boucle voix), aux fiches ni aux scripts (boucle texte). **Pas de réseau**,
  hors premier téléchargement des modèles.
- **Écriture limitée** aux `audio.json` et `readings.json` des catégories, à l'index de l'addon, aux fichiers audio
  (`addon/ForeverSpeech/audio/`, `data/audio/`), à `data/voices/samples/qwen/` et à `data/cache/loops/readings/`.

## Limites connues

- Whisper juge l'anglais et la lecture, pas le jeu d'acteur : le clonage ne reçoit aucune consigne. C'est l'oreille,
  sur le banc.
- Un retour arrière ne restaure que les registres et l'index, pas les fichiers audio.
- Un `.ogg` **nouveau** est lu en jeu après `/reload` ; un `.ogg` **remplacé** seulement après un redémarrage complet.
