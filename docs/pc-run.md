# Prochaine passe sur le PC (RTX 4090)

Le brief de la prochaine session Claude Code sur le PC (WSL2). Réécrit à chaque passe préparée sur le Mac ; le guide
du PC reste [machines.md](machines.md), à lire d'abord.

## Passe du 2026-11-16 : l'audio des textes venus des captures

**Préparé sur le Mac** :
- Forever Database : à jour (release v0.1.6, aucune release ni commit plus récent au 2026-11-16).
- Captures en jeu importées dans les registres (`python -m pipeline.captures quests`, nouveau) : 825 textes capturés
  depuis la sortie, 104 textes français qui manquaient comblés (51 débuts, 53 fins ; Marche de l'Ouest, Les Paluns,
  Les Carmines, Hurlevent, donjons de Forever…). Aucun texte existant remplacé.
- Cache du client importé (`python -m pipeline.captures cache`, nouveau ; `questcache.wdb`, build 70938) : 50 quêtes
  de plus (45 textes de début, 49 objectifs ; Les Paluns, Dalaran, site de fouilles des Paluns, Bois de la Pénombre…).
- Textes de wow-data importés (`python -m pipeline.captures wowdata`, nouveau ; release `db-1ef9f3cb9a92`) : 677
  quêtes de plus (622 textes de début, 99 fins, 119 objectifs ; Fête lunaire, Gangrebois, Foire de Sombrelune,
  Zul'Gurub, Tanaris, quêtes de classe…).
- Au total, à produire ici : 72 voix modèles, 603 lectures de début, 153 de fin (puis les dialogues). Les 123
  textes d'Elise (110 débuts, 13 fins) se font sur le Mac (ElevenLabs).
- Fiches des PNJ : un bug de la boucle texte en avait créé 717 de trop (PNJ qui ne parlent pas) ; retirées, bug
  corrigé. Sans ce correctif, la boucle des voix aurait fait des centaines de voix inutiles.
- Boucle texte relancée (`--reset-ratchet` : le cliquet datait du 2026-10-10) : fiches des PNJ qui n'en avaient pas,
  scripts des textes comblés.

**À faire sur le PC**, une seule machine produit à la fois :

1. Récupérer le code et les registres JSON (dans git depuis le 2026-11-16) : `git fetch origin && git switch main &&
   git pull --ff-only`. Les fichiers JSON de `data/` encore non suivis sur le PC sont remplacés par ceux du Mac (le
   Mac fait foi : fiches et scripts y ont été écrits). Les voix modèles déjà sur le PC (`data/voices/samples/qwen/`)
   restent.
2. Vérifier l'environnement : `.venv-voices/bin/python -m tools.qwen_voices.doctor`.
3. Les voix modèles des PNJ qui n'en ont pas : `tools/voices/run.sh --all`.
4. Les lectures (débuts et fins de quête) : `tools/readings/start.sh --all` (tmux `fs-readings`).
5. Les dialogues des PNJ qui viennent d'avoir leur voix : `tools/dialogues/run.sh --all` (jamais en même temps que 3
   ou 4 : un seul GPU).
6. Point final : `tools/report.sh --all` (colonnes Voix, Audio début, Audio fin).
7. Rapporter : commiter les registres JSON changés (`data/voices.json`, `data/zones/**/*.json`), jamais l'audio, et
   pousser. L'audio produit (`addon/ForeverSpeech/audio/`, voix modèles neuves) attend le moyen de transfert à
   choisir ; ensuite, sur le Mac : `.venv/bin/python -m pipeline.build_index`.

**À ne pas faire** : refaire un audio existant ; toucher aux textes listés « differs » (réécritures de Forever, voir
ci-dessous) ; modifier un fichier scellé pendant qu'une boucle tourne.

**Décision humaine en attente** (pas pour le PC) : 52 textes déjà voisés diffèrent de ce que le jeu affiche. Surtout
les noms de lieux, que Forever traduit (« Goldshire » → « Comté-de-l'Or ») ; quelques fins réécrites (937, 5637,
234…). Liste : `python -m pipeline.captures quests <SavedVariables> --dry-run`.
