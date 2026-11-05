# S3 — Persistance des SavedVariables

**Question.** `ForeverSpeechDB` et `ForeverSpeechCaptures` sont-elles :
- écrites sur disque au `/reload` et à la déconnexion ?
- **rechargées** au lancement suivant ? Un bug de la beta est signalé à ce sujet.

**Impact si échec.** Plus de canal de capture vers le compagnon. Il faudrait une alternative.

## Ce que fait le module

- À chaque chargement (`ADDON_LOADED`), une ligne `[S3] on load: …` indique :
  - si chaque table a été restaurée (`restored=true/false`) ;
  - le compteur et le jeton lus.
- `/fs spike s3` incrémente un compteur et tire un jeton aléatoire, écrit dans les deux tables
  (`ForeverSpeechDB.s3` et `ForeverSpeechCaptures._spikeS3`).

Fichier sur disque :
`/Applications/World of Warcraft/_classic_beta_/WTF/Account/<COMPTE>/SavedVariables/ForeverSpeech.lua`.
Je peux le lire directement depuis ce Mac.

## Procédure

| Étape | Action | Attendu |
|---|---|---|
| 1 | Lancement 1 : `/fs spike s3` | `wrote counter=1 token=XXXXXX` |
| 2 | `/reload` | `[S3] on load: ForeverSpeechDB restored=true … counter=1 token=XXXXXX` (même jeton) |
| 3 | `/fs spike s3` | `counter=2`, nouveau jeton. Puis **quitte complètement le jeu**. |
| 4 | Lancement 2, connexion au même personnage | `[S3] on load: … restored=true counter=2` avec le jeton de l'étape 3. Le bug, s'il existe, donne `restored=false` ou `counter=nil`. |
| 5 | `/reload`, puis dis-moi « fait » | Je compare le fichier avant et après le lancement 2. |

Entre les étapes 3 et 4, je peux vérifier que le fichier contient bien `counter = 2`. Préviens-moi si
tu veux que je le fasse avant de relancer le jeu.

## À me renvoyer

- Ce qu'affiche la ligne `[S3] on load` à l'étape 4 (s'il y a une capture d'écran, c'est parfait).
- « fait » quand c'est fini.

## Résultat (2026-10-05, client 1.60.1.70205)

| Moment | Constat |
|---|---|
| 1er chargement | `restored=false`, normal : aucun fichier n'existait. |
| `/reload` (×4) | `restored=true` pour `ForeverSpeechDB` et `ForeverSpeechCaptures`. Compteur et jeton relus à l'identique. |
| Écriture `counter=2 token=100299`, puis **fermeture complète** du client | Le fichier sur disque contient `counter = 2` (vérifié avant de relancer). |
| **Relance**, même personnage | `restored=true counter=2 token=100299` dans les deux tables. |

Le fichier pèse 708 Ko avec le dump d'API, et l'écriture ne pose aucun problème.

## Décision

- **S3 validé : le canal SavedVariables fonctionne** au `/reload`, à la déconnexion et au redémarrage. Le
  bug signalé sur la beta n'apparaît pas sur le build 70205.
- Le compagnon pourra lire `ForeverSpeechCaptures` après chaque `/reload` ou déconnexion.
- Point de vigilance : il faut revérifier à chaque nouveau build de la beta, puis à la sortie.
