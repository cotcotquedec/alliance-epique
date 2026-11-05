# Constitution de la boucle dialogues

**Lecture seule pour la boucle.** Un humain la relit puis la scelle (`tools/loop/seal.sh dialogues`). La boucle
refuse de tourner si elle, l'oracle, le juge, le cadre, l'arbitre, le cliquet ou les objets des lectures qu'elle
réutilise (juge, cadre et oracle des lectures, juge et oracle des voix) ont changé depuis le sceau.

## But

Chaque **page de dialogue d'un PNJ** dont le PNJ a une **voix modèle** (boucle voix) a son **audio** : le texte
que la fenêtre de discussion affiche quand on parle au PNJ, page après page (décidé le 2026-10-10 : seulement le
texte du PNJ, jamais les lignes que le joueur clique), et, pour un texte accordé (D8), une lecture par sexe du
joueur. Les textes viennent de la base (VMaNGOS, `pipeline/foreverdb/dialogues.py`), puis des scripts
(`pipeline/scripts.py`, section `dialogues`). Catégorie par catégorie, dans l'ordre des niveaux, sur ce que le
lancement couvre : `--all`, ou `--group G [--category C]…`, et `--npc` en plus.

L'oracle dit oui quand aucune lecture couverte n'attend dans cette exécution : chacune est en place, ou n'a pas été
trouvée après 5 essais ratés dans cette exécution. **Aucune lecture n'est abandonnée** : chaque exécution
(`tools/dialogues/run.sh`) rouvre les lectures pas trouvées (`reopen.py`). Une lecture dont le PNJ n'a pas encore
de voix modèle attend la boucle voix.

## Un tour de boucle : quelques catégories

1. **Acteur** (`tools/dialogues/actor.sh`) : il juge d'abord les essais laissés par un tour interrompu, puis chaque
   lecture à faire reçoit **un seul** essai, avec une graine qu'elle n'a jamais eue : Qwen3-TTS 1.7B **Base** clone
   la voix modèle du PNJ et lit le texte, paragraphe par paragraphe (comme les lectures de quête). La génération et
   le juge tournent côte à côte, avec les serveurs de modèles de l'exécution.
2. **Juge** (`tools/dialogues/judge.py`, qui reprend celui des lectures) : l'anglais à **0,15 % au plus**, les mots
   mal lus à **15 % au plus**, le débit de **7 à 22 caractères par seconde**, la **ressemblance avec la voix
   modèle d'au moins 0,75** (essai court : les seuils des lectures, 0,65 sous 3 s, 0,70 de 3 à 5 s, anglais 0,5 % sous
   5 s, 2026-10-12). Bon : il devient l'audio de la page
   (`addon/ForeverSpeech/audio/<pnj>/dialogue_<page>[_f].ogg`, master FLAC dans `data/audio/`, entrée dans le
   `dialogue_audio.json` de la catégorie). Mauvais : il est supprimé, sauf s'il est le meilleur essai raté
   (`dialogue_review/`). Après **5 essais ratés dans l'exécution**, la lecture est **pas trouvée** jusqu'à
   l'exécution suivante. L'état est dans le `dialogue_readings.json` de la catégorie ; chaque verdict va dans
   `data/cache/loops/dialogues/tries.jsonl`.
3. **Oracle** : il ne fait que lire ; il ne compte que les lectures Qwen3 dont le fichier existe et dont les scores
   passent les seuils du juge.
4. **Cliquet** : lectures de dialogue en place et essais jugés ; ils ne peuvent que monter.
   `--reset-ratchet` repart du niveau du lancement.
5. **Critique** : le backlog dit les lectures qui attendent et pourquoi leurs essais échouent.

## Interdits

- Écrire un fichier des boucles lectures ou Elise : les dialogues ont leurs propres fichiers (`dialogue_audio.json`,
  `dialogue_readings.json`).
- Tourner à côté de la boucle voix ou lectures : un seul GPU (`run.sh` refuse).
- Écrire un texte : la boucle lit les scripts, elle ne les écrit pas.
