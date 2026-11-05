# Boucles : base, texte, voix, lectures

Quatre boucles mènent la production jusqu'au bout sans surveillance, dans cet ordre : **base** (les registres),
**texte** (fiches et scripts), **voix** (la voix modèle de chaque PNJ, Qwen3-TTS en local) et **lectures** (l'audio
de chaque texte de quête, lu par le PNJ en clonant sa voix modèle). Chaîne complète : [README](../../README.md).

```bash
tools/base/run.sh --all      # base : construire la Forever Database (.data/) et importer les registres
tools/text/run.sh --all      # texte : fiches et scripts de toutes les catégories (Claude)
tools/text/run.sh --group eastern-kingdoms --category elwynn-forest   # une catégorie, toujours avec son groupe
tools/text/run.sh --group classes                                     # toutes les catégories d'un groupe
tools/voices/run.sh --all    # voix : une voix modèle par PNJ (Qwen3-TTS en local, jugée par Whisper ;
                             # tools/voices/setup.sh une fois ; tools/voices/constitution.md)
tools/readings/run.sh --all  # lectures : l'audio de chaque quête dont le PNJ a sa voix modèle (--npc 823 : ce PNJ
                             # seulement ; tools/readings/constitution.md)
tools/dialogues/run.sh --all # dialogues : l'audio de chaque page de dialogue d'un PNJ qui a sa voix modèle (Qwen,
                             # comme les lectures ; jamais à côté des boucles voix ou lectures, un seul GPU ;
                             # tools/dialogues/constitution.md). tmux : tools/dialogues/start.sh
tools/elise/run.sh --all     # Elise : l'audio de chaque réplique de la narratrice (ElevenLabs, sa voix fixe ; jamais
                             # à côté de la boucle lectures ; tools/elise/constitution.md). tmux : tools/elise/start.sh
tools/books/run.sh --all     # livres (D19) : l'audio de chaque page de livre, lue par Elise (ElevenLabs ; --budget N :
                             # caractères au plus ; --dry-run : ce qu'une exécution lirait, sans appel ; jamais à
                             # côté de la boucle Elise ; tools/books/constitution.md). tmux : tools/books/start.sh
tools/loop/status.sh text    # le dernier essai et le chemin du backlog
.venv/bin/python -m tools.loop oracle text   # la réponse de l'oracle (code 0 : but atteint)
tools/loop/seal.sh text      # après relecture humaine : sceller les objets en lecture seule
```

`tools/voices/run.sh` et `tools/readings/run.sh` prennent `--parallel N` : le nombre d'essais générés ensemble sur le
GPU, en un lot (par défaut 8 sur CUDA, 1 ailleurs ; variable `FS_TTS_BATCH`). Un lot rend tous ses essais à la fin du
plus long.

**Tableau de bord** : `tools/loop/dashboard.sh [voices|readings]`, dans un autre terminal ou un volet tmux
(`Ctrl-b %`), redessiné chaque seconde (`--once` : une seule fois). Il montre la durée depuis le lancement, une barre
pour toute l'exécution (PNJ ou lectures réglés sur ceux à faire au lancement, avec une estimation du temps restant),
une pour la catégorie en cours (essais générés, puis jugés) et une par essai du lot en cours. La barre d'un essai est
une **estimation** : le temps attendu vient de la longueur du texte et des vitesses apprises sur les lots précédents
(`progress/rates.json`). Il ne lit que `data/cache/loops/<passe>/progress/` (`tools/loop/progress.py`), que la boucle,
l'acteur et le générateur écrivent ; aucun oracle ni juge ne le lit. Ctrl-C ferme le tableau de bord, pas la boucle.

`run.sh` garde le Mac éveillé (`caffeinate -i`). Ctrl-C arrête la boucle sans rien perdre : la relancer reprend où
elle s'était arrêtée.

## Sept objets, une frontière de droits d'écriture

| Objet | Fichier | Droit d'écriture | Fonction |
|---|---|---|---|
| Constitution | `tools/<passe>/constitution.md` | boucle : lecture seule | point fixe : but, interdits, schéma cible |
| Oracle | `tools/<passe>/oracle.py` | boucle : lecture seule | prédicat externe qui peut dire non : but atteint ? niveau ? zone suivante ? |
| Cliquet | `tools/loop/ratchet.py` → `data/cache/loops/<passe>/ratchet.json` | boucle : lecture seule | niveau le plus haut atteint ; il ne peut que monter |
| Arbitre | `tools/loop/arbiter.py` + `tools/<passe>/arbiter.py` | lecture seule, la boucle l'exécute | applique l'oracle : valider, attendre, réessayer, arrêter ou revenir en arrière |
| Acteur | `tools/<passe>/actor.sh <zone>` | les données de `data/` | fait une tâche, une seule : une zone |
| Critique | `tools/<passe>/critic.py` → `backlog.md` | le backlog | dit ce qui manque, ne valide jamais |
| Journal / quarantaine | `tools/loop/engine.py` → `logs/`, `journal.jsonl`, `last.json`, `quarantine/` | la boucle | remonte ce qui n'a pas été tranché |

Le dossier de chaque boucle est `data/cache/loops/<passe>/` (ignoré par git).

**Règle n° 1 : la boucle n'écrit jamais son propre critère de succès.** Sans Docker, l'équivalent du montage en
lecture seule est un **sceau** : `tools/<passe>/SEAL` contient l'empreinte SHA-256 de la constitution, de l'oracle,
de l'arbitre, du cliquet et de la définition de la passe. Un humain relit ces fichiers, puis lance
`tools/loop/seal.sh <passe>` et commite le sceau. La boucle refuse de démarrer, et s'arrête avant chaque arbitrage,
si un fichier scellé a changé. Le cliquet n'est écrit que par son propre code, qui refuse de le faire baisser.

Limite : les oracles s'appuient sur `tools/zone.sh progress` (texte) ou `tools/zone.sh order` (voix,
lectures ; `pipeline/zones/__main__.py`), qui ne sont pas scellés parce qu'ils changent souvent. L'acteur ne peut pas
les modifier : les appels à Claude se font sans outils, et les acteurs voix et lectures n'écrivent que des données.

## Un tour de boucle

```
PLANIFIER   l'oracle donne la zone suivante ; copie des registres que l'essai peut modifier
   ↓
AGIR        l'acteur traite cette zone ; sortie affichée en direct et gardée dans logs/
   ↓
ARBITRER    vérification du sceau, nouvel appel à l'oracle, arbitre appliqué par rapport au cliquet :
            progrès → le cliquet monte (validation) ; niveau en baisse → retour arrière
   ↓
CRITIQUER   le critique note dans le backlog ce qui manque à la zone
   ↺        retour à PLANIFIER ; chaque essai est un nouveau processus
```

## Décisions de l'arbitre

Le niveau est un ensemble de compteurs donnés par l'oracle :

- base : zones avec des quêtes, quêtes, descriptions françaises, textes de fin français ;
- texte : zones avec leur texte, scripts, fiches, quêtes récupérées ;
- voix : voix validées et essais jugés (dans une exécution, le nombre de PNJ restants ne fait que baisser ; un PNJ
  pas trouvé après 5 essais est rouvert à l'exécution suivante). Le juge (`tools/voices/judge.py`, scellé) est lancé
  par l'acteur en fin de tour : il garde ou supprime chaque essai ; l'oracle ne fait que relire et revérifier les
  scores ;
- lectures : lectures en place et essais jugés, sur le même principe (juge `tools/readings/judge.py`, qui ajoute la
  ressemblance avec la voix modèle).

Il y a **progrès** quand un compteur monte sans qu'aucun ne baisse.

| Cas | Décision |
|---|---|
| un compteur sous le cliquet | **retour arrière** : les fichiers de l'essai vont en quarantaine, la copie est restaurée ; arrêt |
| l'oracle dit oui | fin |
| limite d'usage Claude (code 75) | attente jusqu'à l'heure de reprise lue dans la sortie, sinon 30 min, 1 h, puis 2 h ; ce n'est pas un échec |
| refus de Wowhead (code 69) | attente de 60 min, puis un essai ; deux refus de suite sans progrès : arrêt (Wowhead n'est plus crawlé depuis D10) |
| environnement des voix absent (77) | arrêt : `tools/voices/setup.sh` (voix et lectures) |
| autre code, avec progrès | nouvel essai après 1 min |
| autre code, sans progrès | nouvel essai après 5 min ; la deuxième fois de suite, arrêt avec la fin de la sortie |
| 1 000 essais (`--max-attempts`) | arrêt |

Au démarrage, un niveau sous le cliquet arrête aussi la boucle (perte entre deux lancements). Si la baisse est voulue,
par exemple une zone récupérée de nouveau avec moins de quêtes, ou si les compteurs ont changé, un humain relance avec
`--reset-ratchet` : le cliquet repart du niveau du lancement.

À chaque arrêt, le journal de l'essai et la raison sont copiés dans `quarantine/<heure>-attempt-<n>/`.

Codes de sortie de la boucle : 0 fin, 1 oracle en échec, 2 arrêt, 3 perte de données, 4 sceau rompu,
130 interruption.
