"""The narrator (D9, 2026-10-10): Elise, a speaker of the addon's own, who reads every quest text that no NPC says (a
quest started by an object or an item picked up, triggered by a place, turned in to an object).

She is an entry of data/voices.json like an NPC, under NARRATOR_ID, outside the game's creature IDs (Forever's go up
to about 254 000) and in no category: the voice loop never sees her. Her model voice is chosen by ear among a few
candidates (tools/voices/narrator.py); her quest readings are made by the readings loop like any other, cloned from
that voice. In the index, her quests keep no giver and no ender (no 3D model): only their audio entries name her,
and npcs[NARRATOR_ID] gives her name to the player frame.
"""

from __future__ import annotations

NARRATOR_ID = 1000000
NAME = "Elise"

# Her record in data/voices.json "npcs", without her voice ("qwen", set when the user picks one). Decided by the user
# on 2026-10-10: a female adult elf, shy, mysterious and very wise, with a calm, soft voice.
RACE = "NightElf"  # the elves of the Alliance (data/accents.json)
PERSONA = {
    "summary": "Elise est une elfe de la nuit, la narratrice de l'addon : elle lit les textes de quête qu'aucun "
               "personnage ne dit, ceux d'un objet, d'un panneau, d'une lettre ou d'un lieu.",
    "sex": "female",
    "age": "adulte",
    "temperament": ["timide", "mystérieuse", "sage"],
    "voice_description_fr": "Voix de femme médium, calme et douce, un peu voilée, comme confiée à mi-voix. Débit lent "
                            "et régulier, diction nette et sans emphase : une conteuse réservée, qui en sait plus "
                            "qu'elle n'en dit, et dont chaque phrase porte une sagesse tranquille.",
    "sample_line": "Le parchemin est couvert d'une écriture fine et pressée. Quelques lignes ont été effacées par la "
                   "pluie, mais le message reste clair : il faut retrouver le messager avant la tombée de la nuit, "
                   "et ne faire confiance à personne sur la route.",
}


def is_narrator(npc: int | str | None) -> bool:
    return npc is not None and str(npc) == str(NARRATOR_ID)


def record() -> dict:
    """Her voices.json entry, before any voice."""
    return {"npc_id": NARRATOR_ID, "name": NAME, "title": None, "narrator": True, "zones": [],
            "race": {"value": RACE, "source": "narrator"}, "persona": dict(PERSONA)}
