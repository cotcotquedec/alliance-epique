# Idées pour plus tard

Des fonctionnalités voulues, pas encore décidées ni commencées. Quand l'une démarre, elle devient une décision de
CLAUDE.md (§4) et quitte cette page.

## I1 — Elise encourage le joueur à chaque niveau (2026-10-11) : **faite**, D17 de CLAUDE.md

Gardée pour mémoire.

À chaque prise de niveau, une réplique d'Elise (voix ElevenLabs, D9), pour motiver le joueur.

- **Déclencheur** : l'événement `PLAYER_LEVEL_UP` (le nouveau niveau en premier argument ; à vérifier sur Forever,
  comme tout événement : une demande de la file en jeu).
- **Répliques** : une par niveau (2 à 60), ou par palier (10, 20, 40, 60 plus marquants : la monture, les
  talents…), écrites dans sa personnalité (timide, mystérieuse, sage) ; jamais d'accord selon le sexe du joueur,
  ou deux variantes (D8).
- **Lecture** : dans la liste de lecture, comme une présentation de zone, avec sa propre icône.
- Coût ElevenLabs : 59 répliques courtes, environ 10 000 caractères.

## I2 — Présentation de chaque technique de classe chez le maître de classe (2026-10-11)

**En attente** (décidé le 2026-10-11) : attendre que la Forever Database couvre les techniques de Forever, qui
diffèrent beaucoup de Classic. Déjà vérifié : VMaNGOS donne pour Classic ce que vend chaque maître (`npc_trainer`,
`npc_trainer_template` : technique, rang, niveau, prix), le nom et la description français (`locales_spell`, 99 à
100 %, environ 410 techniques distinctes) et les valeurs pour remplacer les `$s1` ; 118 maîtres de classe ont déjà
leur voix Qwen. Reste à vérifier en jeu la fenêtre du maître sur Forever, à décider qui parle (le maître ou Elise :
environ 160 000 caractères ElevenLabs pour Elise) ; le chaman est une classe de la Horde dans Classic.

Un audio qui présente chaque technique (sort, capacité) qu'on achète chez son maître de classe : à quoi elle sert et
comment la jouer.

- **Où** : dans la fenêtre du maître de classe (`ClassTrainerFrame`, ou `TrainerFrame` selon le client : à vérifier
  sur Forever), un bouton lecture sur la technique choisie, **avant l'achat**, pour entendre l'explication et
  décider ; la lecture passe aussi par la liste de lecture.
- **Texte** : à partir d'une base de données des sorts (nom, rang, description, coût, temps de recharge : la Forever
  Database ou les données Wowhead en cache, à voir), réécrit pour l'oreille : le rôle de la technique, quand
  l'utiliser, avec quelles autres techniques elle se combine. Une explication par technique, pas par rang (les
  rangs suivants : une phrase courte, ou rien).
- **Voix** : le maître de classe qui la vend (sa voix Qwen3, D11), ou Elise ; à décider.
- Volume : 9 classes, quelques dizaines de techniques chacune.
