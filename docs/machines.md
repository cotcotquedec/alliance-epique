# Deux machines : le Mac et le PC Windows (WSL2, RTX 4090)

À lire en premier par une session Claude Code ouverte sur le PC Windows, dans WSL2. Décidé le 2026-10-07.

## Qui fait quoi

| | Mac (Apple Silicon) | PC Windows, dans **WSL2** (Ubuntu), RTX 4090 |
|---|---|---|
| Le jeu, l'addon, les tests en jeu | **oui** (seul endroit où tourne WoW) | non : `tools/link_addon.sh` n'y sert à rien |
| Boucle base (`tools/base/run.sh`) | oui | oui (refait le Lua 5.1 pour Linux tout seul) |
| Boucle texte (`tools/text/run.sh`, Claude pour les fiches) | oui | oui, si `claude` est installé et connecté |
| Boucles voix et lectures (Qwen3-TTS) | oui, MLX (lent) | **oui, CUDA : la raison d'être de ce PC** |
| Site d'écoute (`.venv/bin/python -m tools.voices.bench`) | oui | oui (ouvrir http://127.0.0.1:8765 dans le navigateur Windows) |

**Une seule machine produit à la fois.** Les données ne sont pas dans git (`data/`, `addon/ForeverSpeech/audio/`,
`addon/ForeverSpeech/data/index.lua`) : le dossier entier est copié d'une machine à l'autre par un disque externe.
Deux machines qui produisent en même temps donneraient deux `data/voices.json` différents, impossibles à fusionner.
Le code, lui, passe par git.

**Le dépôt a changé le 2026-11-06** : c'est [alliance-epique](https://github.com/cotcotquedec/alliance-epique)
(public) ; l'ancien dépôt privé ForeverSpeech est archivé, en lecture seule. Sur le PC, une seule fois, dans le dossier
du projet, après avoir commité ce qui est en cours (les données, l'audio et le lien du jeu ne bougent pas) :

```bash
git remote rename origin archive && git config remote.archive.tagOpt --no-tags
git remote add origin git@github.com:cotcotquedec/alliance-epique.git
git tag -l | xargs -r git tag -d    # les anciens tags restent sur le dépôt archivé
git fetch origin
git branch -m main archive-main && git switch -c main --track origin/main
```

## Ce qui diffère entre les deux, et où

Tout le code est le même. Ne changent que l'endroit où tournent les modèles et l'installation :

| Quoi | Mac | WSL2 + 4090 | Où dans le code |
|---|---|---|---|
| Choix du backend | `mlx` (macOS arm64) | `cuda` (torch voit le GPU) | `tools/qwen_voices/backend.py`, `name()` ; `FS_TTS_BACKEND=mlx\|cuda\|cpu` force |
| Qwen3-TTS | MLX-Audio, poids `mlx-community/Qwen3-TTS-12Hz-1.7B-*-bf16` | paquet officiel `qwen-tts`, poids `Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign` et `-Base`, bf16 | `backend.Qwen` ; `backend.repo()` traduit le nom du cadre |
| Whisper large-v3 (juge) | faster-whisper, processeur, int8 | faster-whisper, GPU, float16 | `backend.whisper()` |
| ECAPA (ressemblance, juge des lectures) | processeur | GPU | `backend.torch_device()` |
| Paquets Python (`.venv-voices`) | `tools/voices/requirements-mlx.txt` | `tools/voices/requirements-cuda.txt` (torch `+cu126`) | `tools/voices/setup.sh` choisit |
| Outils système | Homebrew | apt (dont `sox`, demandé par `qwen-tts`) | `tools/setup.sh` dit quoi installer |
| Garder la machine éveillée | `caffeinate` (dans `run.sh`) | rien : **désactiver la veille de Windows** | — |

Les noms de modèles des cadres scellés (`tools/qwen_voices/frame.py`, `tools/readings/frame.py`) restent ceux de MLX :
c'est `backend.repo()` qui les traduit. Ne pas les modifier pour CUDA (le sceau casserait, et ce serait inutile).

Ce qui ne change pas d'une machine à l'autre :
- une voix modèle ou une lecture validée reste valable ; `audio.json` note `model: qwen3-tts-1.7b-base`, quel que soit
  le backend ;
- le champ `engine` d'un essai dit où il a été fait (par exemple `Qwen/Qwen3-TTS-12Hz-1.7B-Base (cuda)`) ;
- une même graine ne donne pas le même essai sur les deux machines : sans importance, les graines sont tirées au
  hasard et jamais réutilisées.

## Mettre en route le PC (une fois)

1. Windows : pilote NVIDIA récent (il fournit CUDA à WSL2 ; ne pas installer CUDA dans Ubuntu), puis dans PowerShell
   `wsl --install -d Ubuntu-24.04`.
2. Copier le dossier du projet **dans le disque Linux**, par exemple `~/foreverspeech`, jamais sous `/mnt/c/…` (dix
   fois plus lent). Depuis le disque externe, dans Ubuntu : `rsync -a /mnt/d/foreverspeech/ ~/foreverspeech/` (adapter
   la lettre). Inutile de copier `.backups/`, `.venv/`, `.venv-voices/` et `.luarocks/` : ils sont refaits.
3. Dans Ubuntu :
   ```bash
   sudo apt update && sudo apt install -y python3.12 python3.12-venv build-essential curl git ffmpeg vorbis-tools sox luajit luarocks liblua5.1-0-dev
   cd ~/foreverspeech && bash tools/setup.sh
   ```
   `bash tools/setup.sh` et non `tools/setup.sh` : la copie a pu perdre les droits d'exécution (le script les remet).
4. Vérifier :
   ```bash
   nvidia-smi                                         # la RTX 4090 doit apparaître
   tools/check.sh                                     # luacheck, busted, pytest : tout doit passer
   .venv-voices/bin/python -m tools.qwen_voices.doctor
   ```
   Le docteur doit dire `backend: cuda, NVIDIA GeForce RTX 4090` et finir par `all good`. Écouter
   `data/cache/doctor/design.wav` et `clone.wav` (la seconde doit ressembler à la voix modèle du PNJ cité).
   Le premier lancement télécharge ~8,5 Go de modèles (cache Hugging Face, `~/.cache/huggingface`).
5. Claude Code, pour la boucle texte : `curl -fsSL https://claude.ai/install.sh | bash`, puis `claude` une fois pour
   se connecter.

## Lancer la nuit

```bash
tools/readings/run.sh --all     # ou tools/voices/run.sh --all ; ou une catégorie : --group G --category C
```

Pour les lectures, `tools/readings/start.sh [arguments de run.sh]` fait tout : session tmux `fs-readings` (boucle à
gauche, tableau de bord à droite), même périmètre que la dernière exécution sans argument, rien n'est relancé si la
boucle tourne déjà ; une fenêtre `bench` lance le banc d'écoute (http://127.0.0.1:8765, vue « Refusées (tout le
jeu) », avec les boutons Valider, Refuser et Supprimer, `pipeline/review.py`) ; il affiche la commande pour s'attacher
(`tmux attach -t fs-readings`). `--kill` arrête tout.

Les boucles sont décrites dans `tools/loop/README.md`. Ctrl-C arrête sans rien perdre ; relancer reprend. Lancer la
commande dans `tmux` (ou `nohup … &`) pour qu'elle survive à la fermeture du terminal. Suivre : `tools/report.sh --all`,
`tools/loop/status.sh readings`.

Pas de boucle texte en même temps que la boucle voix : les deux écrivent dans `data/voices.json`.

## Jouer sur le PC (2026-10-12)

Le jeu Forever beta est aussi installé sur le PC (`D:\Games\World of Warcraft`, client frFR). `tools/link_addon.sh`
crée un lien symbolique Windows du dossier AddOns vers l'addon dans Ubuntu (`\\wsl.localhost\Ubuntu\…`, mode
développeur de Windows) : le jeu charge la copie de travail, l'audio produit par les boucles compris. Ubuntu doit
tourner pendant le jeu. `addon/ForeverSpeech/data/game_voices.lua` n'est pas versionné : le générer une fois
(`.venv/bin/python -m pipeline.game_voices`). Un `.ogg` nouveau s'entend après `/reload`, un `.ogg` remplacé après un
redémarrage complet (S2).

## Rapporter le travail sur le Mac

Copier vers le Mac (le dossier entier, ou au moins) : `data/` (registres, `voices.json`, voix modèles
`data/voices/samples/qwen/`, masters `data/audio/`), `addon/ForeverSpeech/audio/` et
`addon/ForeverSpeech/data/index.lua`. En jeu : un `.ogg` nouveau s'entend après `/reload`, un `.ogg` remplacé
seulement après un redémarrage complet du jeu (spike S2).

## Les sceaux : à ne pas oublier

Les juges, les cadres, les oracles et les constitutions sont **scellés** (`tools/<boucle>/SEAL`) : une boucle refuse
de démarrer, ou s'arrête en cours (« seal broken during the attempt »), si l'un d'eux a changé. Donc :
- **ne jamais modifier un fichier scellé pendant qu'une boucle tourne** (vérifier avec
  `ps aux | grep tools.loop`) ;
- après une modification, l'utilisateur relit le fichier puis rescelle : `tools/loop/seal.sh <boucle>` (c'est sa
  décision, pas celle de Claude), et le nouveau `SEAL` est commité.

Liste des fichiers scellés d'une boucle : `cat tools/<boucle>/SEAL`.

## Pannes connues et corrections

| Symptôme | Cause | Correction |
|---|---|---|
| `WARNING: Whisper on the GPU failed (… libcublas.so.12 …)`, puis le juge tourne sur le processeur | CTranslate2 4.8 (faster-whisper) est lié à CUDA 12 ; un torch CUDA 13 ne fournit pas `libcublas.so.12` | vérifier `.venv-voices/bin/python -c "import torch; print(torch.__version__, torch.version.cuda)"` → `2.14.1+cu126 12.6`. Sinon : `rm -rf .venv-voices && tools/voices/setup.sh`. En dernier recours : `export LD_LIBRARY_PATH=$(.venv-voices/bin/python -c "import os, nvidia.cublas.lib, nvidia.cudnn.lib; print(os.path.dirname(nvidia.cublas.lib.__file__) + ':' + os.path.dirname(nvidia.cudnn.lib.__file__))")` |
| le docteur dit `backend: cpu` sur le PC | torch ne voit pas le GPU | `nvidia-smi` dans WSL (pilote Windows trop ancien ?) ; `python -c "import torch; print(torch.cuda.is_available())"` ; un torch sans `+cu126` → refaire `.venv-voices` |
| `SoX could not be found!` | le paquet Python `sox` (dépendance de `qwen-tts`) cherche le programme | `sudo apt install sox` (avertissement sans conséquence sinon) |
| `flash-attn is not installed` | optionnel | ignorer : l'attention SDPA de PyTorch suffit ; ne pas compiler flash-attn sous WSL sans raison |
| `voice environment missing: tools/voices/setup.sh` (code 77) | `.venv-voices` absent ou copié du Mac (liens vers `/opt/homebrew`) | `tools/voices/setup.sh` (il remplace un environnement venu d'une autre machine) |
| `Permission denied` sur `tools/*.sh`, ou un oracle qui échoue sur `tools/zone.sh` | droits d'exécution perdus à la copie | `bash tools/setup.sh`, ou `find tools -name '*.sh' -exec chmod +x {} +` |
| erreur de lecture d'un `._…wav` ou `._….json` | fichiers de métadonnées macOS écrits sur le disque externe | `find . -name '._*' -type f -delete` (fait par `tools/setup.sh`) |
| `tools/prepare_db.sh` : `cannot execute binary file` | Lua 5.1 compilé sur le Mac | le script le recompile seul (cible `posix`) ; sinon `rm -rf .data/lua-5.1.5` |
| beaucoup de lectures refusées sur la ressemblance (`sim` < 0,75) | à surveiller : sur le seul essai comparé (2026-10-07, processeur), PyTorch donnait 0,78 et MLX 0,87 pour la même phrase | écouter au banc ; si c'est général sur CUDA, comparer avec le Mac sur un même PNJ avant de toucher aux seuils (scellés, décision humaine) |
| `CUDA out of memory` | improbable (Qwen3 1,7B bf16 ~5 Go, Whisper fp16 ~3 Go, sur 24 Go) | une autre application occupe le GPU : `nvidia-smi` |

## Ce qui a été vérifié, et ce qui ne l'a pas été (2026-10-07)

- Vérifié sur le Mac : la branche MLX dans la vraie boucle lectures, et le docteur complet (ressemblance 0,87).
- Vérifié sur le Mac : **la branche PyTorch exécutée sur le processeur** (`FS_TTS_BACKEND=cpu`, même code que CUDA
  sauf le périphérique) : voix, clonage, Whisper, ECAPA, tout passe.
- Vérifié sans GPU : la liste `requirements-cuda.txt` se résout pour Linux x86_64 (torch 2.14.1+cu126, qwen-tts
  0.1.1, transformers 4.57.3, ctranslate2 4.8.2).
- **Pas encore vérifié : l'exécution sur la RTX 4090.** C'est le premier lancement du docteur sur le PC qui le dira.
  Une correction éventuelle se fait dans `tools/qwen_voices/backend.py` (non scellé) ; noter le résultat ici.

## Pistes pour aller plus vite (pas faites)

- Lire les paragraphes d'une lecture en un seul lot : `generate_voice_clone` accepte une liste de textes.
- Plusieurs PNJ en un lot pour la boucle voix (`generate_voice_design` accepte des listes).
- Les deux changent le résultat obtenu pour une graine : à valider à l'oreille avant de les garder.
