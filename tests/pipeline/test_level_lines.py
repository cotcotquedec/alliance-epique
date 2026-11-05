import json

import pytest

from pipeline import narrator, storage
from pipeline.level_lines import FIRST, LAST, generate
from pipeline.llm import Answer, LLMError


def good(level):
    if level == LAST:
        return " ".join(["Le vrai voyage commence maintenant, et je marche avec vous."] * 5)
    return "Un pas de plus sur la route, et la forêt vous reconnaît un peu mieux chaque soir."


def test_problems_by_level():
    assert generate.problems(12, good(12)) == []
    assert generate.problems(60, good(12))[0].endswith("mots")  # too short for the last level
    assert "un mot de jeu (niveau)" in generate.problems(12, good(12) + " Un niveau de plus.")
    assert "une parenthèse, un symbole ou une exclamation" in generate.problems(12, good(12) + " Bravo !")
    assert "un nombre en chiffres" in generate.problems(12, good(12) + " 12")


@pytest.fixture
def where(tmp_path, monkeypatch):
    monkeypatch.setattr(generate, "folder", lambda: tmp_path / "levels")
    return tmp_path / "levels" / "scripts.json"


def test_the_story_is_written_once_and_a_bad_line_asked_again_alone(where):
    asked = []

    def call(system, prompt, schema, model, effort, bare=False):
        asked.append(prompt)
        if schema is generate.STORY_SCHEMA:
            lines = [{"level": lv, "text": good(lv)} for lv in range(FIRST, LAST + 1)]
            lines[10]["text"] = "Bravo !"  # level 12: asked again
            return Answer({"arc": "Elise attend depuis mille ans.", "lines": lines}, model, 0.1)
        assert "niveau 12" in prompt and "Elise attend depuis mille ans." in prompt
        return Answer({"text": good(12)}, model, 0.01)

    report = generate.generate(call=call, log=lambda *_: None)
    assert report == {"written": LAST - FIRST + 1, "fixed": 1}
    data = json.loads(where.read_text())
    assert data["arc"] == "Elise attend depuis mille ans." and len(data["levels"]) == 59
    assert data["levels"]["12"]["npc_id"] == narrator.NARRATOR_ID and data["levels"]["12"]["text"] == good(12)
    assert generate.generate(call=call, log=lambda *_: None)["written"] == 0  # already written: kept


def test_again_rewrites_some_lines_in_the_same_story(where):
    storage.write_json(where, {"arc": "Arc.", "story": "s", "levels": {
        str(lv): {"text": good(lv)} for lv in range(FIRST, LAST + 1)}})

    def call(system, prompt, schema, model, effort, bare=False):
        return Answer({"text": "Respirez. La route attend, et elle sait être patiente avec ceux qui la suivent."},
                      model, 0.0)
    generate.again([30], call=call, log=lambda *_: None)
    assert json.loads(where.read_text())["levels"]["30"]["text"].startswith("Respirez.")


def test_again_gives_up_after_the_attempts(where):
    storage.write_json(where, {"arc": "Arc.", "levels": {"30": {"text": good(30)}}})
    with pytest.raises(LLMError):
        generate.again([30], call=lambda *a, **k: Answer({"text": "Bravo !"}, "m", 0.0), log=lambda *_: None)
