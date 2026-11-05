# S9 — Fin de quête : texte de rendu et clic sur « Terminer la quête »

**Question.** Sur Forever 1.60.1 :
- l'événement `QUEST_COMPLETE` se déclenche-t-il à l'ouverture de la fenêtre de récompense ?
- `GetRewardText()` renvoie-t-il le texte de rendu, et `GetQuestID()` la quête ?
- `GetQuestReward(choix)` est-il appelé par le bouton « Terminer la quête » ? Repli : le bouton
  `QuestFrameCompleteQuestButton`.

**Impact.** En cas d'échec, la fin de quête ne se lit pas au rendu ; elle reste jouable avec `/fs play <questID> end`.

**Hypothèse.** L'interface de quêtes de Forever est de style Retail 11.x (S4), où ces trois noms existent.

## Procédure

Voir `docs/ingame-tests.md`, T11 (étapes 1 à 3).

## Résultat

**2026-10-07, d'après le journal de diagnostic** (`ForeverSpeechDB.trace`, quête 18 rendue à l'adjoint Willem) :
- `QUEST_COMPLETE` se déclenche à l'ouverture de la fenêtre de récompense ;
- `GetQuestID()` renvoie la quête (18) et `GetRewardText()` le texte de rendu (86 caractères).

**Piège trouvé** : sur Forever, `frame:RegisterEvent(event)` renvoie `false` quand la frame a déjà cet
événement. `TryRegisterEvent` prenait ce `false` pour un refus : le second abonnement à `QUEST_COMPLETE` (la
lecture de la fin de quête, après celui de la capture) était perdu, et rien ne se lisait. Corrigé : un événement
déjà enregistré reçoit simplement un abonnement de plus. Les « unknown events » du spike S4
(`QUEST_DETAIL`, `QUEST_COMPLETE`, `QUEST_LOG_UPDATE`) venaient du même piège : ils existent tous.

Vérifié en jeu le 2026-10-07 : la fin de quête se lit à l'ouverture de l'onglet « Terminer la quête » (T12), 1 s après.
