import pytest

from pipeline.narration import normalize, speech


@pytest.mark.parametrize("raw, expected", [
    ("Ne perdez pas de temps, <nom>. Plus les kobolds seront tranquilles…", "Ne perdez pas de temps. Plus les kobolds seront tranquilles…"),
    ("<nom>, mes éclaireurs me rapportent", "Mes éclaireurs me rapportent"),
    ("S'il vous plaît, <nom>, parlez à Dughan.", "S'il vous plaît, parlez à Dughan."),
    ("Salutations, <nom>. Les animaux", "Salutations. Les animaux"),
    ("C'est fini. <nom>, allez-y !", "C'est fini. Allez-y !"),
    ("Votre fiabilité est démontrée, <classe>. Vous", "Votre fiabilité est démontrée. Vous"),
    ("le coeur bien accroché, jeune <classe>, car il y a du travail", "le coeur bien accroché, jeune camarade, car il y a du travail"),
    ("Bonne chance, brave <classe>. J'espère", "Bonne chance, brave camarade. J'espère"),
])
def test_address_forms(raw, expected):
    assert normalize(raw) == {"text": expected, "text_f": None, "directions": []}


def test_gender_variants():
    r = normalize("Mais soyez <prudent/prudente> <nom>. Garrick a rassemblé une bande.")
    assert r["text"] == "Mais soyez prudent. Garrick a rassemblé une bande."
    assert r["text_f"] == "Mais soyez prudente. Garrick a rassemblé une bande."


def test_class_suffix_variant_and_article():
    r = normalize("<nom>, vous êtes <un/une:c> <classe> indubitablement <impliqué/impliquée:c> dans")
    assert r["text"] == "Vous êtes un camarade indubitablement impliqué dans"
    assert r["text_f"] == "Vous êtes une camarade indubitablement impliquée dans"


def test_stage_direction_is_not_read():
    r = normalize("Je sais peut-être qui l'a, mais...<grand sourire>... J'ai trop faim.")
    assert r["text"] == "Je sais peut-être qui l'a, mais... J'ai trop faim."
    assert r["directions"] == ["grand sourire"]


def test_speech_reads_objectives_after_the_description():
    s = speech("Bonjour, <cher monsieur/ma dame> ! Une seconde ?", "Parler à Willem.")
    assert s["text"] == "Bonjour, cher monsieur ! Une seconde ?\n\nObjectif : Parler à Willem."
    assert s["text_f"] == "Bonjour, ma dame ! Une seconde ?\n\nObjectif : Parler à Willem."
    assert speech(None, "x")["text"] is None
    assert speech("Texte.", None) == {"text": "Texte.", "text_f": None, "directions": []}


def test_long_bracketed_block_is_narration_not_a_stage_direction():
    raw = "<Ce Murloc devait terroriser les gens de passage dans les environs. Une récompense est peut-être offerte.>"
    r = normalize(raw)
    assert r["text"] == raw[1:-1] and r["directions"] == []


def test_template_keeps_gender_markers_and_renders_both():
    from pipeline.narration import render, speech_template
    t = speech_template("Soyez <prudent/prudente> <nom>. Vous êtes <un/une:c> <classe> fiable.", "Tuer Garrick.")
    assert t["text"] == "Soyez <prudent/prudente>. Vous êtes <un/une> camarade fiable.\n\nObjectif : Tuer Garrick."
    assert t["gendered"] is True
    assert render(t["text"], "m") == speech(  # same result as the direct normalization
        "Soyez <prudent/prudente> <nom>. Vous êtes <un/une:c> <classe> fiable.", "Tuer Garrick.")["text"]
    assert render(t["text"], "f").startswith("Soyez prudente. Vous êtes une camarade fiable.")
