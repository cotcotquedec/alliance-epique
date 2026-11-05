# S11 — Les dialogues des PNJ (fenêtre de discussion)

**Question.** Sur Forever 1.60.1, que donne le client quand on parle à un PNJ (`GOSSIP_SHOW`) : le texte de la bulle
de discussion est-il lisible (`C_GossipInfo.GetText` de Retail, ou `GetGossipText` de Classic) ? Les options
(`C_GossipInfo.GetOptions`) ? Ce texte est-il celui de la base (VMaNGOS : `gossip_menu` → `npc_text` →
`broadcast_text`, en français pour 1 364 PNJ ; 391 des 1 137 PNJ qui ont une voix Qwen) ?

**Périmètre (décidé par l'utilisateur le 2026-10-10).** Seulement les **conversations de la fenêtre de discussion** :
on clique sur un PNJ qui a l'icône de bulle, sa fenêtre s'ouvre avec un texte à lire (et ses sous-pages quand on
clique une option) ; ce texte serait lu **en direct, à l'ouverture de la fenêtre**, par la voix du PNJ. **Pas** les
paroles que le jeu joue déjà avec un son (cris, répliques d'escorte ou de combat, `broadcast_text` des scripts).

**Impact.** Si le texte est lisible : les dialogues deviennent un troisième type de lecture (après les débuts et fins
de quête), lus par la voix du PNJ, avec la capture en jeu comme source de vérité (D1). Sinon : seulement le texte de
la base, sans savoir lequel le jeu affiche (les menus ont des conditions).

## Ce que l'addon fait (2026-10-10)

À chaque `GOSSIP_SHOW`, `core/capture.lua` lit le texte (d'abord `C_GossipInfo.GetText`, sinon `GetGossipText`), le
PNJ (`UnitGUID("npc")`) et les options, et l'enregistre dans `ForeverSpeechCaptures.gossip["Creature:<id>"]`,
dédupliqué par texte. Le journal de diagnostic note chaque ouverture : `capture: GOSSIP_SHOW unit=… api=… textLen=…`.
`/fs gossip` résume ce qui est capturé. Rien n'est lu à voix haute : c'est un spike.

## Procédure

1. Redémarrer complètement le jeu (nouvelle version de l'addon), puis `/fs debug on`.
2. `/dump C_GossipInfo ~= nil, C_GossipInfo and C_GossipInfo.GetText ~= nil, GetGossipText ~= nil`
3. Parler à quelques PNJ, en ouvrant leur fenêtre de discussion (pas seulement une quête) :
   - **Maréchal McBride** (197, abbaye de Northshire). Texte attendu (base) : « Hé ! Vous m'avez l'air d'être
     costaud. Nous autres gardes sommes en sous-effectif. Vous pourriez nous aider… » ;
   - un **aubergiste** et un **marchand** (texte court, options « Je voudrais acheter… ») ;
   - un PNJ **ajouté par Forever** (par exemple Falorne Fallwind, 251371), absent de la base ;
   - si possible, un PNJ avec une **histoire en plusieurs pages** : cliquer une option qui ouvre un autre texte.
4. `/fs gossip`, puis `/reload`.

**À relever** (agent du Mac, qui lit lui-même les SavedVariables) : la sortie du `/dump`, la section `gossip` de
`ForeverSpeechCaptures` et les lignes `capture: GOSSIP_SHOW` du journal `ForeverSpeechDB.trace`
(`WTF/Account/<compte>/SavedVariables/ForeverSpeech.lua`) ; à demander à l'utilisateur : le texte qu'il voit dans la
fenêtre de McBride, et s'il a ouvert une sous-page. Le résultat cite les textes sans le nom du personnage.

## Lecture des résultats

| Résultat | Conclusion |
|---|---|
| `api = C_GossipInfo.GetText`, texte présent | Le texte est lisible (API de Retail) : on peut lire les dialogues en jeu. |
| `api = GetGossipText` | Lisible par l'API de Classic : on garde le repli. |
| rien de capturé, `textLen=nil` | Aucune des deux ne répond : chercher dans `/fs api` (documentation du client). |
| texte de McBride identique à la base | Le texte de la base suffit pour pré-générer ; la capture corrige les écarts. |
| texte différent | Forever a réécrit : la capture est la source (comme pour les quêtes, D1). |
| le texte d'une sous-page est aussi capturé | `GOSSIP_SHOW` se déclenche à chaque page : on peut lire chaque page. |

## Résultat

**2026-10-21, mesuré sur les SavedVariables du Mac** (lecture seule ; client 1.60.1.70450, plusieurs personnages),
par `python -m pipeline.captures gossip <ForeverSpeech.lua>` : la règle de correspondance du contrat d'index v9
(`pipeline/match.py` : jetons normalisés, nom, classe et race du joueur retirés comme des suites de jetons, comme le
fait l'addon (`core/dialogues.lua`), égalité exacte sinon score ≥ 0,7).

- **Le texte est lisible** : 102 textes différents capturés (247 ouvertures de fenêtre) chez 76 PNJ, **tous par
  `C_GossipInfo.GetText`** (API de Retail). Les sous-pages sont capturées aussi (un PNJ de Forever a 8 pages
  enchaînées) : `GOSSIP_SHOW` se déclenche à chaque page.
- **52 captures de 39 PNJ présents dans la base** : **38 exactes**, **10 approchées** (score ≥ 0,7), **4 différentes**.
  Soit **48 sur 52 (92 %) retrouvées**. Les approchées sont surtout des accords et des variables que la base retire
  (`$g` : « jeune homme », « mon amie » restent dans le texte affiché ; `$c` : « chasseur ») et de petites retouches
  de Forever (« Élune » devenu « Elune »). Les 4 différentes : un texte de marchand que la base n'a pas pour ce PNJ
  (« Je ne vends que les meilleurs équipements des arcanes… », deux PNJ), une sous-page d'un garde (les métiers,
  atteinte par une option qui n'est pas « discussion », donc pas importée, D14), et un forgeron qui montre le texte de
  formateur au lieu de celui de la base.
- **50 captures de 37 PNJ absents de la base** : 47 de PNJ **ajoutés par Forever** (identifiants au-delà de 247 000 :
  île de Zephras, Shen'dar, l'Ordre suprême…), 3 de PNJ qui existent dans la base sans dialogue. Quelques textes de
  Forever sont **restés en anglais** dans le client français (Bolvar, Magni, un cadavre de Forever).
- **Aucune donnée de livre** dans les captures (sections `quests`, `completions`, `gossip`, `_spikeS3` seulement).

**Conclusion.** Lisible en direct ; le texte de la base est celui du jeu pour les PNJ de Classic (92 % retrouvés), et
les PNJ de Forever n'ont que la capture (D1). Retirer le nom, la classe et la race **comme une suite de jetons** et non
jeton par jeton, comme le contrat le disait d'abord (« Elfe de la nuit » retirait sinon « de » et « la » de tout le
texte affiché), donne 38 exactes au lieu de 36, sans rien perdre (48 retrouvées dans les deux cas). Suite proposée :
lire D14 en jeu par l'index v9 (section `dialogues`), à trancher par l'utilisateur.
