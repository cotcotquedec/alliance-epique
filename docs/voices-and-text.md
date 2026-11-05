# Voix des PNJ et texte à lire

État au 2026-10-07. La chaîne complète est décrite dans [pipeline.md](pipeline.md).

Ordre de travail :
1. une fiche de personnalité par PNJ qui parle ;
2. le texte à lire, avec des règles d'adaptation pour qu'un seul audio serve à tous les personnages ;
3. une voix modèle par PNJ, créée depuis sa fiche, puis la lecture de ses quêtes avec cette voix (Qwen3-TTS, D11).

Chaque PNJ a sa propre personnalité et sa propre voix. C'est l'**option A** de Q-VOIX-1
(`docs/reference/npc-voices.md`). Elle est retenue dans les faits, mais pas encore tranchée formellement.
Couper les salutations d'origine du jeu reste à traiter plus tard.

## 1. Fiches de personnalité (`data/voices.json`)

| Commande | Effet |
|---|---|
| `tools/zone.sh personas <zone> --dry-run [--show <npcID>]` | Liste les fiches à générer, sans appel. `--show` affiche le dossier d'un PNJ. |
| `tools/zone.sh personas <zone> [--npc ID] [--force] [--jobs 4] [--bare]` | Génère les fiches manquantes ou périmées. |
| `tools/zone.sh persona <npcID>` | Affiche une fiche. |

### Fonctionnement

1. Le **dossier** d'un PNJ est construit uniquement à partir des registres. Il contient :
   - le PNJ : nom, titre, niveaux, zones ;
   - sa voix dans le jeu : race, sexe, personnalité ;
   - le texte des quêtes qu'il donne ;
   - le texte d'achèvement des quêtes qu'il conclut.

   Toutes les zones déjà récupérées sont prises en compte.
2. Claude reçoit ce dossier, avec la consigne [`pipeline/personas/prompt_v3.md`](../pipeline/personas/prompt_v3.md).
   Depuis la v2, la consigne exige une voix **de jeu de rôle**, très expressive, et une réplique test chargée
   d’émotion. Les versions précédentes sont dans l’historique git.
3. La réponse doit respecter un schéma JSON fixe (`PERSONA_SCHEMA` dans `pipeline/personas/generate.py`) :
   - résumé, sexe et source du sexe, âge ;
   - tempérament, registre, débit, énergie, manière de parler, émotion de fond ;
   - **description de voix en anglais**, pour l'outil de design vocal, et sa traduction française ;
   - **réplique test** originale (100 à 1000 caractères), qui sert à écouter la voix.

   Le schéma est imposé par Claude Code, puis revérifié par `validate()`.

### Reproductibilité

- Le modèle est fixé (`claude-sonnet-5-5` depuis le 2026-10-05 ; Elwynn et Dun Morogh ont été faits avec
  `claude-opus-5-5` et sont gardés tels quels), effort `medium`, et la consigne est versionnée (`PROMPT_VERSION`).
- Chaque fiche garde l'**empreinte de ses entrées** : dossier, consigne, schéma et modèle.
  - Une relance ne régénère que les PNJ dont l'empreinte a changé : une nouvelle zone apporte de nouvelles quêtes, ou la consigne passe en v2.
  - `--force` régénère tout.
- `data/voices.json` est versionné : une voix déjà créée ne change pas par accident.
- La partie `voice`, remplie à l'étape 2, est conservée quand on régénère la fiche.

### Appel à Claude

Le script passe par `claude -p`, Claude Code en mode non interactif (`pipeline/llm.py`). Aucune dépendance Python et aucune clé
dans le dépôt.
- **Par défaut**, l'appel utilise la connexion Claude Code de la machine.
- **Avec une clé d'API** : option `--bare`. Claude Code ne lit alors que `ANTHROPIC_API_KEY`. Pour ne pas l'écrire
  en clair, on peut la ranger dans le trousseau macOS :

  ```bash
  security add-generic-password -s anthropic-api-key -a "$USER" -w
  export ANTHROPIC_API_KEY=$(security find-generic-password -s anthropic-api-key -w)
  ```
- **Isolement** : chaque appel tourne sans outil, sans session enregistrée, sans réglages ni CLAUDE.md, dans un
  dossier temporaire vide.
- **Coût mesuré** : environ 0,04 $ par fiche, soit 1,20 $ pour les 32 fiches d'Elwynn en v2.

## 1 bis. Plus de direction d'acteur (2026-10-07)

Jusqu'au 2026-10-07, Claude découpait chaque texte en segments, avec une émotion, une intensité et des balises de
jeu pour ElevenLabs. Qwen3 ne lit que le texte (D11) : cette direction est retirée. Un script est maintenant calculé
sans Claude par `pipeline/scripts.py`, à partir de `pipeline/narration.py` ; les scripts écrits avant gardent leurs
champs de direction, inutilisés. La boucle texte n'appelle plus Claude que pour les fiches.

## 2. Texte à lire : règles d'adaptation

**« camarade » validé le 2026-10-05.** Les règles sont codées dans `pipeline/narration.py`, avec des tests dans `tests/pipeline/test_narration.py`.

Le but est **un seul audio par quête**, plus une variante féminine uniquement quand le texte s'accorde au sexe du
joueur (D8). Constats sur Elwynn :

| Élément | Occurrences (descriptions) | Règle proposée |
|---|---|---|
| `<nom>`, nom du joueur | 12 | Toujours en apostrophe (« Ne perdez pas de temps, `<nom>`. »). **On le retire et on recolle la phrase** : « Ne perdez pas de temps. » ; « `<nom>`, mes éclaireurs… » → « Mes éclaireurs… ». Pas de variante. |
| `<classe>` | 4 (et 4 dans les achèvements) | En apostrophe seule (« Votre fiabilité est démontrée, `<classe>`. ») : **on la retire**, comme `<nom>`. Après un adjectif (« jeune `<classe>` », « brave `<classe>` ») : on met un mot **épicène**, donc identique au masculin et au féminin : **« camarade »**, ou « recrue » au Comté du Nord. |
| `<race>` | 0 | Même traitement que `<classe>`. |
| `<a/b>` (`<prudent/prudente>`, `<cher monsieur/ma dame>`) | 4 quêtes | **Deux audios**, homme (`file`) et femme (`fileF`). |
| `<a/b:c>` (`<un/une:c>`, quête 54) | 1 quête | Hypothèse : un accord comme `<a/b>`. Il est à confirmer par une capture de la quête 54. |
| `<grand sourire>` | 1 achèvement | Ce n'est pas du texte mais une **indication de jeu**. Elle n'est pas lue et devient une consigne de ton pour la voix. |
| Texte capturé en jeu | — | Le client y a inséré le nom, la classe et la race du personnage. La capture les enregistre depuis le 2026-10-05 (`playerName`, `playerClass`, `playerRace`), donc le pipeline peut les remplacer par `<nom>`, `<classe>` et `<race>`, puis appliquer les règles ci-dessus. |
| Noms propres (Elwynn, Stormwind, Garrick, Défias…) | — | Un **lexique de prononciation** commun à toutes les voix. |
| Objectifs | — | Lus après la description, annoncés « Objectif : … » (D6). |

## 3. Voix et lectures (Qwen3-TTS, D11)

- **Voix modèle** : Qwen3-TTS VoiceDesign, depuis une description française construite à partir de la fiche
  (`tools/qwen_voices/frame.py`) et de l'accent de la race (`data/accents.json`) ; boucle voix,
  [`tools/voices/constitution.md`](../tools/voices/constitution.md).
- **Lectures** : Qwen3-TTS Base clone la voix modèle et lit le script ; boucle lectures,
  [`tools/readings/constitution.md`](../tools/readings/constitution.md).
- **Texte de la voix** (`voice_text` dans `data/voices.json`) : la phrase d'exemple de la fiche, ou un texte choisi à
  la main dans les quêtes du PNJ quand elle échoue (sans nom anglais, sans interjection : « Ha ! », « Hé », « Euh »).
- **Une voix qui se clone mal** (lectures refusées sur la ressemblance) : on la refait, `tools/voices/redo.py`.
- **Écoute** : le banc, `.venv/bin/python -m tools.voices.bench`.

## 4. La narratrice, Elise (D9, 2026-10-10)

Elise lit tout texte de quête qu'aucun PNJ ne dit : quête donnée par un objet (panneau « WANTED », coffre) ou par un
item ramassé, quête déclenchée par un lieu, quête rendue à un objet. Un PNJ donneur ou de rendu reste prioritaire.
À terme, elle devient la compagne du joueur, avec des répliques propres au jeu (entrée dans une zone…).

- **Fiche** (`pipeline/narrator.py`, écrite à la main) : elfe de la nuit adulte, timide, mystérieuse et très sage,
  voix calme et douce. Identifiant `1000000`, hors des ID du jeu, dans aucune catégorie.
- **Voix, ElevenLabs, définitive** : `FS Elise` (`G6INpmIspgFpsST79Psc`, l'ancienne voix de base
  HumanFemaleOfficial, choisie par l'utilisateur ; étiquetée `language: fr`). Fiche dans `data/voices.json`
  (`npcs["1000000"].elevenlabs`), référence `data/voices/samples/elise/voice/ref.flac`. Outil :
  `tools/elise/voice.py` (`use <voice_id>`, ou `design` puis `keep` ; tout changement de voix est une décision
  humaine, à la main). Clé d'API : `config/secrets.env` (jamais versionné).
- **Ses répliques** : `pipeline/scripts.py` lui donne les textes sans PNJ (`tools/zone.sh scripts <catégorie>`),
  546 côté Alliance (~210 000 caractères). La **boucle Elise** (`tools/elise/`, constitution
  `tools/elise/constitution.md`) les fait lire par ElevenLabs (`eleven_v4`) et juger par Whisper (anglais, mots mal
  lus, débit ; pas de ressemblance). Elle attend quand les crédits du compte sont épuisés (code 75). Jamais à côté
  de la boucle lectures : les deux écrivent les `audio.json`.
- **En jeu** (index v4) : pas de modèle 3D (icône de quête), « Elise » sous le titre, sauf si la capture a le nom
  de l'objet. Fichiers : `addon/ForeverSpeech/audio/1000000/`.
- La boucle lectures (Qwen) ne la touche pas : Elise n'a pas de voix Qwen, ses répliques y comptent « en attente de
  voix ».
