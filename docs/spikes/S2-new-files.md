# S2 — Fichiers ajoutés ou écrasés pendant la session

> Les scripts de ce spike (`tools/spike_s2.sh`) ont été retirés le 2026-10-07 : voir l'historique git.

**Question.**
- Un .ogg **ajouté** pendant que le client tourne est-il lisible sans redémarrage ?
- Un .ogg **existant écrasé** est-il relu avec son nouveau contenu ?
- Dans les deux cas : tout de suite, après `/reload`, ou seulement après un redémarrage complet ?

**Impact.** C'est ce qui fixe le mode du compagnon (mode B, §12) :
- soit « disponible au prochain lancement » ;
- soit `/reload` avec des fichiers « slots » créés à l'avance puis écrasés.

## Principe

Le script `tools/spike_s2.sh` manipule deux fichiers dans `addon/ForeverSpeech/audio/test/` (lien symbolique,
donc directement dans le dossier du jeu) :

| Fichier | `prepare` (jeu fermé) | `change` (jeu lancé) |
|---|---|---|
| `s2_new.ogg` | absent | créé (contenu « deux ») |
| `s2_slot.ogg` | contenu « un » (copie de test_1) | écrasé par « deux » (copie de test_2) |

`/fs spike s2 <étiquette>` joue `s2_new.ogg`, puis `s2_slot.ogg` 11 s plus tard. Il enregistre aussi
la valeur de retour de chaque `PlaySoundFile`.

## Procédure

1. **Jeu fermé**, dans un terminal à la racine du dépôt : `tools/spike_s2.sh prepare`. Lance le jeu et
   connecte-toi.
2. `/fs spike s2 1-initial`.
   Attendu : `new` = silence (`willPlay` = false), `slot` = « un ».
3. Jeu toujours lancé, dans le terminal : `tools/spike_s2.sh change`.
4. `/fs spike s2 2-after-change` (sans `/reload`), puis `/reload` et
   `/fs spike s2 3-after-reload`.
5. **Après un redémarrage complet du jeu** (lancement 2) : `/fs spike s2 4-after-restart`.
   Attendu : `new` = « deux », `slot` = « deux ».
6. Une fois fini : `tools/spike_s2.sh reset`.

## À me renvoyer

Pour chaque run (1 à 4), ce que tu as entendu pour `new` puis pour `slot` : silence, « un » ou « deux ».

## Résultat (2026-10-05, client 1.60.1.70205)

| Run | `new` (fichier **ajouté** en cours de session) | `slot` (fichier existant **écrasé**) |
|---|---|---|
| 1-initial | silence, `PlaySoundFile` ne renvoie rien | « un » |
| 2-after-change, sans reload | silence, rien renvoyé : **invisible** | « un » : **ancien contenu** |
| 3-after-reload | **« deux »** : visible après `/reload` | « un » : **toujours l'ancien contenu** |
| 4-after-restart | « deux » | « deux » |

## Décision

- **Un nouveau fichier devient lisible après un simple `/reload`, sans redémarrage.** En revanche, un
  fichier **écrasé** garde son ancien contenu jusqu'au redémarrage complet du client. Le client semble
  garder en cache les sons déjà ouverts.
- **Mode B incrémental (§12) : possible au `/reload`**, à une condition : ne jamais réécrire un fichier
  existant.
  - Chaque génération produit un **nom de fichier neuf** : la version de voix ou de texte fait partie du
    nom, par exemple `audio/<npc>/<quest>_detail_v2.ogg`.
  - `index.lua` est régénéré pour pointer vers le nouveau fichier ; il est relu au `/reload`.
  - Les anciennes versions sont supprimées par le compagnon **jeu fermé**.
- Les fichiers « slots » créés à l'avance ne sont pas nécessaires. Le contrat d'index n'a pas besoin de
  changer : `file` contient déjà un chemin complet. La convention de nommage versionnée sera fixée avec le
  compagnon (phase 2).
