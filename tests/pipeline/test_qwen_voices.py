from tools.qwen_voices.design import describe, pick_per_race, quest_script

ACCENTS = {"default": "Human", "races": {
    "Human": {"adj": ["humain", "humaine"], "instruct_fr": "Accent standard."},
    "Dwarf": {"adj": ["nain", "naine"], "instruct_fr": "Roule les r."},
}}


def npc(race, **persona):
    return {"name": "Adjoint Willem", "title": None, "race": {"value": race}, "persona": {
        "sex": "male", "age": "adulte", "temperament": ["dévoué", "chaleureux", "vigilant", "franc"],
        "summary": "L'adjoint Willem est un garde de Stormwind. Il accueille les recrues.",
        "voice_description_fr": "Homme humain adulte d'environ 35 ans, baryton chaleureux. Locuteur natif de "
                                "France, accent français standard. Débit vif.", **persona}}


def test_describe_frames_identity_role_voice_and_race_accent():
    text = describe(npc("Human"), ACCENTS)
    assert text.startswith("Comédien de doublage français, de langue maternelle française, né et vivant en France")
    assert "Voix d'un personnage non joueur (PNJ) de World of Warcraft, côté Alliance" in text
    assert "Adjoint Willem : un homme de race humaine, d'environ 35 ans." in text
    assert "L'adjoint Willem est un garde de Stormwind. Caractère : dévoué, chaleureux, vigilant." in text
    assert "Voix : baryton chaleureux. Débit vif." in text  # identity clause and accent sentence dropped
    assert "accent français standard" not in text
    assert text.endswith("Accent standard. Français de France uniquement, aucun accent anglais.")


def test_describe_uses_the_race_accent_and_feminine_forms():
    text = describe(npc("Dwarf", sex="female", age="mûr"), ACCENTS)
    assert text.startswith("Comédienne de doublage français") and "née et vivant en France" in text
    assert ": une femme mûre de race naine, d'environ 35 ans." in text
    assert "Roule les r. Français de France uniquement" in text


def script(quest_id, chars, gendered=False):
    return {"quest_id": quest_id, "text": "x" * chars, "gendered": gendered}


def test_quest_script_prefers_plain_text_of_about_380_chars():
    assert quest_script([script(1, 900), script(2, 300), script(3, 390, gendered=True)])["quest_id"] == 2


def test_pick_per_race_one_confident_adult_npc_per_race_and_sex():
    def rec(race, sex, age="adulte", confidence="haute"):
        return {"name": "x", "race": {"value": race}, "persona": {"sex": sex, "age": age, "confidence": confidence}}
    records = {"1": rec("Human", "male", age="enfant"), "2": rec("Human", "male"),
               "3": rec("Dwarf", "female", confidence="moyenne"), "4": rec("Dwarf", "female"),
               "5": rec("Troll", "male"), "6": rec("Human", "female")}
    scripts = {n: [script(int(n), 380)] for n in records if n != "6"}
    assert pick_per_race(records, ACCENTS, scripts) == [("Human", "male", "2"), ("Dwarf", "female", "4")]
