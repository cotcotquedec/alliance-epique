# Constitution de la boucle voix

**Lecture seule pour la boucle.** Un humain la relit puis la scelle (`tools/loop/seal.sh voices`). La boucle refuse
de tourner si elle, l'oracle, le juge, l'arbitre, le cadre ou le cliquet ont changé depuis le sceau.

## But

Chaque PNJ qui parle (il a une fiche de personnalité, `data/voices.json`) a une **voix modèle** : un enregistrement
de son texte de voix, créé par Qwen3-TTS VoiceDesign depuis sa description et validé par le juge. Elle sert ensuite
à cloner la voix pour lire ses quêtes (boucle lectures). Catégorie par catégorie, dans l'ordre des niveaux, sur ce
que le lancement couvre : `--all`, ou `--group G [--category C]…`, et `--npc` en plus.

L'oracle dit oui quand aucun PNJ couvert n'attend sa voix dans cette exécution : chacun a une voix validée, ou n'a
pas été trouvé après 5 essais ratés dans cette exécution. **Aucun PNJ n'est abandonné** : chaque exécution
(`tools/voices/run.sh`) commence par rouvrir les PNJ sans voix, qui repartent avec 5 essais (`reopen.py`).

## Un tour de boucle : une catégorie

1. **Acteur** (`tools/voices/actor.sh`) : il juge d'abord les essais laissés par un tour interrompu, puis récupère
   les meilleurs essais gardés qui passent les seuils du moment (seuils assouplis). Ensuite, chaque PNJ sans voix
   reçoit **un seul** essai, avec une graine qu'il n'a jamais eue, puis le juge, puis la page d'écoute.
   Le texte lu est le `voice_text` du PNJ : sa phrase d'exemple (recopiée au premier essai), ou un texte choisi à la
   main dans ses quêtes. Si ce texte a changé depuis ses essais ratés, ceux-ci sont archivés (`qwen_history`) : ils
   restent comptés, leurs graines ne reviennent pas, et le nouveau texte repart avec ses 5 essais.
2. **Juge** (`tools/voices/judge.py`) : Whisper large-v3 écoute chaque essai une fois. L'essai est bon si
   - l'anglais est à **0,15 % au plus** ;
   - les mots mal lus sont à **15 % au plus** (depuis le 2026-10-13, un nom propre écrit autrement par Whisper mais
     proche, accents et tirets à part, compte comme lu : `tools/voices/names.py`) ;
   - le débit est de **7 à 22 caractères par seconde**.

   Bon : il devient la voix du PNJ (`data/voices/samples/qwen/voices/<pnj>/ref.wav` et `ref.txt`, clé `qwen` de
   `voices.json`, statut `ok`). Mauvais : il est supprimé, sauf s'il est le meilleur essai raté du PNJ, gardé dans
   `review/`. Après **5 essais ratés dans l'exécution**, le PNJ est **pas trouvé** jusqu'à l'exécution suivante.
   Chaque verdict va dans `data/cache/loops/voices/tries.jsonl`.
3. **Oracle** : il ne fait que lire ; il recompte les voix et revérifie leurs scores contre les seuils du juge.
4. **Cliquet** : voix validées et essais jugés (archives comprises) ; ils ne peuvent que monter. Un tour qui ne fait
   monter aucun compteur est un échec (deux de suite : arrêt). `--reset-ratchet` repart du niveau du lancement.
5. **Critique** : le backlog dit qui attend sa voix, pourquoi ses essais échouent, et le taux d'échec par race. Une
   race qui échoue souvent est une décision humaine : son accent ou le cadre.

## Le cadre (scellé)

`tools/qwen_voices/frame.py` et `data/accents.json` : la description envoyée à Qwen3 (comédien de doublage français
natif, contexte World of Warcraft Alliance, identité, rôle, caractère, voix, accent de la race, « français de France
uniquement »), le modèle (Qwen3-TTS 1.7B VoiceDesign), la langue, la température 0,7. Le changer est une décision
humaine ; les voix validées sont gardées.

## Interdits

- **Jamais de régénération** d'une voix validée ; la refaire est une décision humaine (`tools/voices/redo.py`).
- **Jamais de perte** : le niveau ne baisse jamais.
- **Jamais de graine réutilisée** pour un même PNJ.
- **Pas de texte** : ni fiche ni script (boucle texte). **Pas de réseau**, hors premier téléchargement des modèles.
- **Écriture limitée** à `data/voices.json` (clés `qwen`, `qwen_history`, `voice_text`), à `data/voices/samples/qwen/`
  et à `data/cache/loops/voices/`.
- Ne pas faire tourner la boucle texte en même temps : les deux écrivent `data/voices.json`.

## Limites connues

- Whisper juge l'anglais et la lecture, pas les accents de race (r roulés des nains…) : c'est l'oreille, sur le banc.
- Un retour arrière ne restaure que `data/voices.json`, pas les fichiers audio.
- Un PNJ présent dans plusieurs catégories est traité dans la première que la boucle visite.
