# S5 — Fin de son et synthèse vocale intégrée

**Questions.**
- `SOUNDKIT_FINISHED` existe-t-il sur Forever, et se déclenche-t-il pour `PlaySoundFile` ? Avec quel
  délai ?
- `StopSound(handle)` coupe-t-il le son, et déclenche-t-il l'événement ?
- `C_Sound.IsPlaying` existe-t-il ? On pourrait alors interroger l'état du son au lieu d'attendre un
  événement.
- `C_VoiceChat.SpeakText` est-il disponible, avec quelle signature et quelles voix ?

**Impact.**
- Sans événement de fin : une minuterie basée sur `dur`.
- Sans TTS : pas de fallback vocal (§8).

## Ce que fait le module (`/fs spike s5`, environ 30 s)

1. Il teste l'existence de `StopSound`, `C_Sound.IsPlaying`, `C_VoiceChat.SpeakText`,
   `C_VoiceChat.GetTtsVoices` et `Enum.VoiceTtsDestination`.
2. Il enregistre `SOUNDKIT_FINISHED` via `pcall`, ce qui ne plante pas si l'événement est inconnu, ainsi
   que les événements `VOICE_CHAT_TTS_PLAYBACK_*`.
3. Il exécute trois étapes :

   | Temps | Étape | Action |
   |---|---|---|
   | t = 0 | **A** | Joue `test_2.ogg` (9,38 s) en entier. Il note l'heure de `SOUNDKIT_FINISHED` et le moment où `C_Sound.IsPlaying` passe à faux. |
   | t = 12 s | **B** | Rejoue `test_2.ogg`. |
   | t = 14 s | **B** (suite) | `StopSound(handle)` : le son doit se couper après environ 2 s. |
   | t = 18 s | **C** | TTS : liste les voix, choisit une voix française si possible, puis appelle `SpeakText`. |

   À l'étape C, la signature n'est pas présumée. Le module la lit dans la documentation d'API intégrée
   au client (`Blizzard_APIDocumentationGenerated`, la même que pour `/api`) et construit l'appel
   d'après les noms d'arguments. Si cette documentation est absente, il utilise par défaut la signature
   Classic `(voiceID, text, destination, rate, volume)` et le note dans le journal.

## Procédure

1. `/fs spike s5` et écoute pendant 30 s.
2. `/fs spike api` : enregistre toute la documentation d'API du client (fonctions et événements),
   ce qui me permettra de vérifier les signatures plutôt que de les supposer. C'est utile pour toute la
   suite.
3. `/reload`.

## À me renvoyer

- A s'est-il joué jusqu'au bout ?
- B s'est-il coupé après environ 2 s ?
- As-tu entendu la phrase TTS « Bonjour aventurier… » ? Avec quelle voix, et en français ou non ?

## Résultat

Session du 2026-10-05.

- **`SOUNDKIT_FINISHED`**
  - L'événement existe : `RegisterEvent` réussit et la documentation donne
    `SOUNDKIT_FINISHED(soundHandle)`.
  - Mais **il ne s'est déclenché ni pour une fin naturelle ni après `StopSound`** sur un son lancé par
    `PlaySoundFile`.
- **`C_Sound.IsPlaying(soundHandle) -> bool`** fonctionne.
  - A (fin naturelle) : passe à faux 9,62 s après le lancement, pour une durée réelle de 9,38 s et un
    sondage toutes les 0,25 s.
  - B (après `StopSound` à 2 s) : passe à faux à 2,25 s.
  - Le journal affichait « ERROR » à cause d'un bug du module de test (`false or "ERROR"`), corrigé
    depuis.
- **`StopSound(handle)`** ne renvoie rien et **coupe le son**.
  - `IsPlaying` le mesurait dès le premier essai.
  - Le premier retour à l'oreille était contradictoire. Le second test (`/fs spike s5 stop`, avec le
    moment de l'arrêt annoncé dans le chat) l'a confirmé à l'oreille.
- **TTS : disponible.**
  - Signature documentée : `C_VoiceChat.SpeakText(voiceID, text, rate, volume, overlap)`, sans
    `destination`. `Enum.VoiceTtsDestination` n'existe pas.
  - Les voix sont celles de macOS. Les voix françaises vont des id 0 à 17 ; « Thomas [fr-FR] » a l'id 17.
  - Les événements `VOICE_CHAT_TTS_PLAYBACK_STARTED(0)` et `FINISHED(0)` se sont déclenchés,
    5 s d'écart.
  - Le premier test a choisi « Amélie [fr-CA] », la première voix contenant « fr ».
  - Le second test (`/fs spike s5 tts`) préfère Thomas [fr-FR], puis Jacques, puis n'importe quelle voix
    fr-FR. **Phrase entendue à l'oreille** (confirmé le 2026-10-05).

## Décision

- **Fin de lecture** : on sonde `C_Sound.IsPlaying(handle)` toutes les 0,25 s, dans un seul `OnUpdate`
  actif uniquement pendant une lecture. On n'utilise ni `SOUNDKIT_FINISHED`, qui ne se déclenche pas pour
  `PlaySoundFile`, ni une minuterie basée sur `dur`. `dur` reste utile pour une barre de progression.
- **Fallback TTS (§8) : possible.** On choisira une voix `[fr-FR]` par nom, en préférant Thomas puis
  Jacques, sinon la première voix fr-FR, plutôt que par ID, qui dépend de l'OS.
  - On l'arrête avec `C_VoiceChat.StopSpeakingText`.
  - La fin se détecte avec `VOICE_CHAT_TTS_PLAYBACK_FINISHED`.
