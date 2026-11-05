# S7 — Faisabilité du crawl Wowhead Forever (FR)

**Question.** Peut-on crawler `wowhead.com/forever/fr/…` ? Il faut vérifier :
- ce qu'autorise le robots.txt ;
- s'il y a une protection anti-bot ;
- la structure des pages de quête et de PNJ ;
- l'existence de données structurées et d'un endpoint de tooltip.

**Statut : fait le 2026-10-05.**
- Environ 27 requêtes d'exploration, espacées de 2 à 3 s.
- Puis le crawl S6 avec le client du pipeline.

## Résultat

### Accès

- **robots.txt** (`www.wowhead.com/robots.txt`) :
  - Pour `User-Agent: *`, seules quelques sections sont interdites, par saveur et par locale : `account`,
    `list`, `random`, `search`, `site-achievement`, `error-static-cdn`.
  - Aucune règle ne touche `quest=`, `npc=`, `zone=`, `/quests/` ni les tooltips.
  - Pas de `Crawl-delay`.
  - En revanche, les robots d'IA et d'entraînement sont entièrement interdits (`Disallow: /`) :
    `anthropic-ai`, `ClaudeBot`, `Claude-Web`, `GPTBot`, `CCBot`… ainsi que `Scrapy`.
  - Notre crawler est un outil personnel, avec un UA propre (`ForeverSpeechPersonalCrawler`), un faible volume
    et un cache. Il relève de `*`. Le client relit robots.txt et refuse toute URL interdite.
- **Hébergement** : nginx derrière AWS CloudFront. Pas de Cloudflare, pas de challenge JS, pas de cookie,
  pas d'en-tête de limitation de débit.
- **Le WAF bloque** en 403 « Request blocked » :
  - l'UA par défaut de `python-requests` ;
  - un UA Chrome usurpé.

  **Un UA honnête et personnalisé avec `urllib` (bibliothèque standard) passe (200).** C'est le choix
  retenu, sans dépendance.
- **Cache CDN** :
  - HTML : `s-maxage=600` ;
  - tooltips : `43200` ;
  - redirections : `86400`.

### URL

- `https://www.wowhead.com/forever/fr/{quest|npc|object|item|zone}={id}` renvoie une 301 vers l'URL avec
  slug (par exemple `/forever/fr/quest=783/menace-intérieure`), puis une 200. Il suffit de suivre la
  redirection.
- Un identifiant absent donne une 301 vers `/forever/fr/quests?notFound=<id>`, puis une **404**. Le client
  la met en cache pour ne jamais la redemander.
- Listes :
  - Catégorie : `/forever/fr/quests/eastern-kingdoms/elwynn-forest` (76 quêtes pour la Forêt d'Elwynn).
  - Zone : `/forever/fr/zone=12`. Elle liste 181 quêtes liées à la zone et 266 PNJ.
  - Sitemap : `/forever/sitemap/quest?page=1`, soit **5385 quêtes** (989 avec un id > 30000, c'est-à-dire
    du contenu propre à Forever).
- Environnement Wowhead : `dataEnv=16` correspond à Forever (`data.pageMeta` → `"env":16`,
  `"versions":{"16":"1.60.1"}`).

### Marqueurs d'une page de quête (parser : `pipeline/wowhead/parse.py::parse_quest`)

| Donnée | Source |
|---|---|
| Nom | `<h1 class="heading-size-1">…</h1>`. Un nom entre crochets (`[Applejack Still]`) signale une quête non traduite. |
| Objectifs | Le texte après `</h1>`, jusqu'à `<table class="icon-list">`, `<script` ou `<h2` |
| Description | De `<h2 class="heading-size-3">Description</h2>` jusqu'au `<h2` suivant. Les paragraphes sont séparés par `<br /><br />`, ou par un simple `\n` dans les textes 1.60. |
| Progrès / Achèvement | `<div id="…-progress">` / `<div id="…-completion">` (préfixe obfusqué : on cible le suffixe) |
| Donneur / Rendu | Infobox `WH.markup.printHtml("…[icon name=quest-start]Début : [url=/forever/fr/npc=823/…]…")`, décodée comme une chaîne JSON. Le donneur peut être un `npc`, un `object` ou un `item` (D9). |
| Métadonnées | `$.extend(g_quests[<id>], {…})` en JSON strict : `category` (zone), `level`, `reqlevel`, `side` (1 = A, 2 = H, 3 = les deux), `xp`, `money`, `envChange.status` (`new`, `updated` ou `unchanged` par rapport à Classic) |
| Patch d'ajout | `[acronym="1.60.1.69893"]` dans l'infobox |

À **ne pas** lire : `lv_comments0`, qui contient les commentaires des utilisateurs, en anglais.

### Marqueurs d'une page de PNJ (`parse_npc`)

| Donnée | Source |
|---|---|
| Nom, titre, type, classification, réaction A/H, zones, niveaux | `$.extend(g_npcs[<id>], {…})`. Le titre est le champ `tag`, présent seulement s'il existe. |
| displayID | `data-mv-display-id="2072"` |
| Quêtes données / rendues | `new Listview({template: 'quest', id: 'starts' / 'ends', … data: [...]})` |
| Sexe et race | **Absents de la page.** Ils sont disponibles via `https://wow.zamimg.com/modelviewer/classic/meta/npc/<displayId>.json` → `"Character":{"Race":1,"Gender":0}` (vérifié pour 2072). Hypothèses non vérifiées : le chemin `classic` vaut pour Forever, et les créatures non humanoïdes ont `Character: null`. |

### Endpoint de tooltip

`https://nether.wowhead.com/tooltip/quest/<id>?dataEnv=16&locale=2` (locale 2 = frFR, vérifié). Il
renvoie le nom et le résumé des objectifs, **mais pas la description**. Il est donc inutile pour la
narration. Il pourrait servir à un rafraîchissement léger du nom.

### Textes : constats utiles pour D8

Wowhead écrit les variables sous forme de balises : `<nom>`, `<classe>`, `<race>`, et les accords sous la
forme `<costaud/costaude>`. Ce n'est pas la syntaxe `$N`, `$C` ou `$G` du client. La normalisation
du pipeline devra traiter les deux formes :
- `<a/b>` donne les variantes m/f ;
- `<nom>` et `<classe>` sont neutralisés.

## Décision

- **Crawler en bibliothèque standard** (`urllib`, `json.raw_decode`, `re`). Aucune dépendance à
  ajouter.
- Client : `pipeline/wowhead/client.py`.
  - UA `ForeverSpeechPersonalCrawler/0.1` ;
  - au moins 2,5 s entre deux requêtes réseau ;
  - robots.txt respecté ;
  - cache disque `data/cache/wowhead/` (gitignore), où les 404 sont aussi mises en cache ;
  - **arrêt immédiat sur 403 ou 429** (exception `Blocked`) ;
  - jusqu'à 3 tentatives sur une erreur 5xx.
- Énumération des quêtes : sitemap pour le lot complet, pages de catégorie pour un échantillon de zone.
- Les parseurs sont testés sur des fixtures HTML (`tests/pipeline/fixtures/wowhead/`). Ce sont des pages
  Wowhead brutes : elles sont **exclues de git** (dépôt public, pas de redistribution) et se reconstruisent
  localement avec `python -m pipeline.wowhead.fetch_fixtures`. Sans elles, les tests de parsing sont sautés.
- Crawl complet estimé : environ 5 400 quêtes + environ 2 000 PNJ donneurs, à 2,5 s par requête, soit
  environ 5 h. C'est faisable en une nuit, puis le cache fait le reste. Non testé à ce volume : surveiller
  les 403.

## Fin (2026-11-01)

Le crawler est retiré. Depuis le 2026-10-12, le pare-feu CloudFront de Wowhead refuse les pages de quête à tout client
qui n'est pas un navigateur : 403 pour notre User-Agent honnête, pour curl et pour une requête sans User-Agent, depuis
l'adresse même d'où un navigateur ouvre la page (200). robots.txt et l'API des infobulles
(`nether.wowhead.com/forever/tooltip/quest/<id>`, titre et objectifs seulement) répondent encore. Attendre ne lève
pas le refus (essayé une heure de suite, puis 7 h), et le contourner (navigateur piloté, Playwright, UA imité) est
exclu (CLAUDE.md §3). Les pages déjà en cache restent lues par `pipeline/wowhead/cache.py` ; `client.py`,
`fetch_fixtures.py`, `pipeline/zones/fetch.py`, `pipeline/quests/enrich.py` et `pipeline/npcs/` (enrich, model,
voice) sont supprimés.

