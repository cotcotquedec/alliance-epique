import pytest

from pipeline.quests.registry import merge_previous, quest_record, summarize, unavailable_record

FR_DESC = "J'espère que vous avez le coeur bien accroché, jeune <classe>. Vous êtes <prêt/prête> ?"


def parsed(**overrides):
    base = {
        "id": 783, "name": "Menace intérieure", "untranslated": False,
        "objectives": "Parler au maréchal McBride.", "description": FR_DESC,
        "progress": None, "completion": "Préparez vous à une longue campagne.",
        "starters": [{"type": "npc", "id": 823, "name": "Adjoint Willem"}],
        "enders": [{"type": "npc", "id": 197, "name": "Maréchal McBride"}],
        "zone_id": 12, "level": 1, "reqlevel": 1, "side": 1, "xp": 40, "money": 0,
        "env_status": "unchanged", "added_patch": None,
    }
    return {**base, **overrides}


def test_complete_french_quest():
    r = quest_record(parsed(), 200, "2026-10-05T10:00:00")
    assert r["status"] == "complete" and r["missing"] == []
    assert r["side"] == "alliance"
    assert r["placeholders"] == ["classe", "prêt/prête"]
    assert r["forever"] == {"status": "unchanged", "patch": None}
    assert r["capture"] is None


def test_english_text_is_dropped_not_kept():
    r = quest_record(parsed(name="[Applejack Still]", untranslated=True,
                            description="Bring me the apples and the cider, you will be paid for this.",
                            objectives="Collect 8 apples."), 200, None)
    assert r["name"] is None and r["description"] is None
    assert r["objectives"] == "Collect 8 apples."  # no evidence either way: kept
    assert r["not_french"] == ["name", "description"]
    assert r["status"] == "incomplete" and r["missing"] == ["name", "description"]


@pytest.mark.parametrize("field, text", [
    ("objectives", "Parler au maréchal McBride."),
    ("name", "On recherche : « Lardeur »"),
    ("completion", "Oh, quel soulagement ! On dirait qu’ils sont tous là. Merci !"),
])
def test_short_french_text_is_not_mistaken_for_english(field, text):
    r = quest_record(parsed(**{field: text}), 200, None)
    assert r[field] == text and r["not_french"] == []


def test_no_giver_is_missing():
    r = quest_record(parsed(starters=[]), 200, None)
    assert r["missing"] == ["giver"] and r["status"] == "incomplete"


def test_unavailable_page():
    r = unavailable_record(5, 404, None)
    assert r["status"] == "unavailable" and "description" in r["missing"]


def test_refetch_keeps_captures_and_capture_only_quests():
    new = {783: quest_record(parsed(), 200, None)}
    previous = {"783": {"capture": {"text": "capturé"}},
                "99999": {"id": 99999, "status": "capture_only", "capture": {"text": "vu en jeu"}},
                "5": {"id": 5, "status": "complete"}}
    merged = merge_previous(new, previous)
    assert merged[783]["capture"] == {"text": "capturé"}
    assert merged[99999]["status"] == "capture_only"
    assert 5 not in merged  # no longer listed by Wowhead and not captured: dropped


def test_summary():
    quests = {1: quest_record(parsed(), 200, None),
              2: quest_record(parsed(id=2, starters=[], env_status="new"), 200, None)}
    s = summarize(quests)
    assert (s["quests"], s["complete"], s["incomplete"], s["missing_giver"], s["new_in_forever"], s["gendered"]) == \
        (2, 1, 1, 1, 1, 2)
