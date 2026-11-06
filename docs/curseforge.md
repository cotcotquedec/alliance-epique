# Alliance Épique sur CurseForge

Le kit pour créer le projet et y déposer l'addon (préparé le 2026-11-05). **Le projet existe** : n° 1785582, créé le
2026-11-05 avec le compte du joueur (https://authors.curseforge.com/#/projects/1785582/files). La création du projet et l'envoi des fichiers
se font avec le compte CurseForge du joueur, dans l'espace auteur du site. Les archives se construisent avec
`node tools/package_addon.ts` (README, « Installer » ; CLAUDE.md, « Releases »).

## Le projet

| Champ | Valeur |
|---|---|
| Jeu | World of Warcraft |
| Nom | Alliance Épique |
| Adresse (slug) | `alliance-epique` |
| Résumé (**en anglais**, exigé) | Your companion for the Alliance on WoW Forever: quests read aloud in French by their own NPCs, Elise the narrator, and comfort that keeps the game's look. |
| Catégorie principale | Quests & Leveling (à choisir dans la liste du site) |
| Autres catégories | Audio & Video, Roleplay |
| Licence | MIT |
| Code source | https://github.com/cotcotquedec/alliance-epique |
| Logo | `dist/curseforge/logo.png` (400 × 400, l'icône de l'addon) |
| Langue | Français (client frFR) |

**Les relations** (dans les réglages du projet, ou à l'envoi de chaque fichier) : FlareUI, **dépendance optionnelle**
(pas « Required » : l'addon garde l'apparence du jeu sans lui). Le TOC le dit aussi (`## OptionalDeps: FlareUI`).

**La version de jeu** (à l'envoi de chaque fichier) : le groupe « WoW Forever », version **1.60.1** (le client, interface
`16001`). **La distribution** aux applications tierces : autorisée.

**Le fichier à envoyer** : `dist/AllianceEpique-<version>-<date>.zip` (l'addon seul, sans les voix). Jamais l'archive
des voix (3,2 Go) : elle se partage à part.

**Ce que CurseForge exige** (appris le 2026-11-05) :

- le résumé en anglais ; la description commence donc par un paragraphe anglais, puis le texte français ;
- **tout le contenu du zip dans un seul dossier** : un fichier posé à côté du dossier `ForeverSpeech` (le premier
  `LISEZMOI.txt`) a fait refuser la première 0.3.0 (« This ZIP contains files at the top level ») ; le LISEZMOI est
  maintenant dans le dossier ;
- le fichier se choisit à la main (« Choose File ») : l'outil de navigateur de Claude ne joint pas plus de 10 Mo.

## La description

Le texte à coller dans la description du projet :

```markdown
**Ton compagnon pour l'Alliance, sur World of Warcraft Forever.**

Alliance Épique accompagne ton aventure côté Alliance, en français, sans changer l'esprit du jeu : l'interface reste celle
de Blizzard, ce qui s'ajoute t'accompagne sans te distraire.

### Ce qu'il fait

- **Les quêtes lues à voix haute**, en français, par le personnage qui les donne : une voix par PNJ, accordée à sa race,
  à son âge et à son rôle. Le début d'une quête quand tu l'acceptes, sa fin quand tu la rends, avec les fenêtres du jeu
  comme avec Dialogue UI. Les dialogues des PNJ aussi.
- **Elise, la narratrice** : une sentinelle elfe de la nuit qui présente chaque zone, a un mot à chaque niveau gagné
  (une seule histoire du niveau 2 au niveau 60), lit les livres et les plaques du monde, et salue tes compagnons de route.
- **La fenêtre de quête** : le PNJ, les objectifs suivis en direct, l'avancement de chaque membre de ton groupe, les
  récompenses, une liste de lecture.
- **Le journal des compagnons** : les joueurs avec qui tu as le plus groupé.
- **Du confort** : l'interface qui s'efface quand tu marches (la mini-carte reste), les quêtes triées par niveau, la
  roue d'émotes, le sac d'un seul tenant avec les métiers en onglets, l'annonce au groupe des quêtes terminées.

Tout se règle dans Échap > Options > AddOns > Alliance Épique, ou avec `/fs options`.

### Les voix

Les voix (environ 3 Go) ne sont pas dans ce téléchargement : elles se partagent à part, dans une archive qui ajoute le
dossier `AllianceEpique_Voix` à côté de l'addon. Les mises à jour de l'addon n'y touchent pas. Sans elles, l'addon lit
les textes avec la synthèse vocale du jeu.

### Avec FlareUI

Alliance Épique est pensé avec [FlareUI](https://www.curseforge.com/wow/addons/flareui) : quand il est installé, la
fenêtre se colle à son suivi des quêtes et en prend l'apparence. Sans lui, l'addon garde l'apparence du jeu.

Pour le client français et les quêtes de l'Alliance. Projet de fan, sans lien avec Blizzard. Code :
[github.com/cotcotquedec/alliance-epique](https://github.com/cotcotquedec/alliance-epique) (licence MIT).
```

## Le journal de la version 0.3.0

Le texte à coller à l'envoi du fichier :

```markdown
Première version sur CurseForge.

- Le nom Alliance Épique dans le jeu ; une page de présentation et la licence MIT.
- FlareUI : la fenêtre se colle à son suivi des quêtes et en prend l'apparence (cadre, polices, bronze, icônes) ;
  sans FlareUI, l'apparence du jeu.
- L'avancement de chaque membre du groupe sous les objectifs.
- L'interface s'efface quand tu marches ou voles en griffon (la mini-carte reste), revient à l'arrêt et en combat.
- Un onglet par métier appris sur le côté du sac, grisé loin de son atelier.
- Les voix livrées à part, dans leur propre dossier (AllianceEpique_Voix).
- Retiré : le bandeau du bas (niveau et or).
```
