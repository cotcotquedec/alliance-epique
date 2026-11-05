"""The voice frame: how an NPC's voice is described to Qwen3-TTS VoiceDesign, and the generation settings
(2026-10-07). READ-ONLY for the voice loop (sealed in tools/voices/SEAL with data/accents.json): changing the frame
is a human decision, and voices already validated are kept.

The description, in French: a native French dubbing actor (Qwen3 otherwise gives many voices an English accent),
the World of Warcraft Alliance context, the NPC's identity (name, race, sex, age), its role (persona summary), its
temperament, its voice (persona voice description, accent sentences removed) and the accent of its race
(data/accents.json), then a closing reminder: French from France only.
"""
import re

REPO = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"
LANGUAGE = "french"
TEMPERATURE = 0.7  # 0.9 (default) gave more English-accented takes (2026-10-07 test)
SR = 24000  # takes: mono 24 kHz, -20 LUFS
LOUDNESS = -20.0

CONTEXT = ("Voix d'un personnage non joueur (PNJ) de World of Warcraft, côté Alliance, qui lit ses textes de "
           "quête en français, comme dans le doublage du jeu.")
# persona.age -> (masculine, feminine) noun; the race adjective follows it.
AGE_NOUNS = {
    "enfant": ("garçon", "fille"),
    "adolescent": ("adolescent", "adolescente"),
    "jeune adulte": ("jeune homme", "jeune femme"),
    "adulte": ("homme", "femme"),
    "mûr": ("homme mûr", "femme mûre"),
    "âgé": ("vieil homme", "vieille femme"),
}
# Sentences of the persona's voice description about language or accent: the race's accent replaces them.
ACCENT_SENTENCE = re.compile(r"accent|natif|native|francophone|locut", re.IGNORECASE)
APPROX_AGE = re.compile(r"environ ([\w -]+?) ans")
# Leading clause of a voice sentence restating who the NPC is ("Homme humain adulte d'environ 35 ans, baryton..."):
# the identity line already says it.
IDENTITY_CLAUSE = re.compile(r"^[^,:]*\bans\b\s*[,:]\s*")


def sentences(text):
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", text or "") if s.strip()]


def race_of(npc, accents):
    persona = npc.get("persona") or {}
    race = ((npc.get("race") or {}).get("value") or persona.get("race")
            or (npc.get("game_voice") or {}).get("race"))
    return race if race in accents["races"] else None


def french_frame(female):
    """Opening of every description: a native French dubbing actor (2026-10-07, against the English accent)."""
    actor, born = ("Comédienne", "née") if female else ("Comédien", "né")
    return (f"{actor} de doublage français, de langue maternelle française, {born} et vivant en France : ne parle "
            "que français, avec la prononciation, le rythme et la mélodie d'un doublage français de jeu vidéo. "
            "Aucune trace d'accent anglais ou américain : r français, voyelles françaises pures, accent tonique en "
            "fin de groupe.")


FRENCH_END = "Français de France uniquement, aucun accent anglais."


def describe(npc, accents):
    """The French voice description of an NPC record (an entry of voices.json "npcs")."""
    persona = npc["persona"]
    accent = accents["races"][race_of(npc, accents) or accents["default"]]
    female = persona.get("sex") == "female"
    noun = AGE_NOUNS.get(persona.get("age"), AGE_NOUNS["adulte"])[female]
    voice_fr = persona.get("voice_description_fr") or ""
    age = APPROX_AGE.search(voice_fr)
    name = npc["name"] + (f", {npc['title']}" if npc.get("title") else "")
    identity = (f"{name} : {'une' if female else 'un'} {noun} de race {accent['adj'][1]}"
                + (f", d'environ {age.group(1)} ans" if age else "") + ".")
    role = (sentences(persona.get("summary"))[:1] or [""])[0]
    temperament = ", ".join(persona.get("temperament", [])[:3])
    kept = [s for s in sentences(voice_fr) if not ACCENT_SENTENCE.search(s)]
    if kept and IDENTITY_CLAUSE.search(kept[0]):
        kept[0] = "Voix : " + IDENTITY_CLAUSE.sub("", kept[0])
    voice = " ".join(kept)
    parts = [french_frame(female), CONTEXT, identity, role, f"Caractère : {temperament}." if temperament else "",
             voice, accent["instruct_fr"], FRENCH_END]
    return " ".join(p for p in parts if p)
