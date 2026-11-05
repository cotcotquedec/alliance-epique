import json
import subprocess

import pytest

from pipeline import storage
from pipeline.llm import Answer, LLMError, claude_json
from pipeline.personas import generate as personas

PERSONA = {
    "summary": "Adjoint de la garde du Comté du Nord, il accueille les recrues.",
    "sex": "male", "sex_evidence": "game_voice", "race": "Human", "age": "adulte",
    "temperament": ["droit", "bienveillant", "pressé"],
    "register": "militaire", "pace": "normal", "energy": "moyenne",
    "speech_traits": "Phrases courtes, ton d'instructeur.",
    "default_emotion": "sérieux",
    "voice_description_en": "Adult man in his thirties, firm mid-low voice, clear diction, steady pace. "
                            "Native French speaker from France, standard French accent.",
    "voice_description_fr": "Homme d'une trentaine d'années, voix ferme, diction claire.",
    "sample_line": "Ne traînez pas dans l'abbaye, il y a du travail dehors. Les loups rôdent près du "
                   "cimetière et les recrues ont besoin d'un exemple.",
    "confidence": "haute",
}

NPC = {"id": 823, "name": "Adjoint Willem", "title": None, "type": 7, "react": {"alliance": 1, "horde": None},
       "levels": [1, 18], "forever": {"status": "updated"},
       "voice": {"source": "wowhead_classic_fr", "kind": "archetype", "set": "HumanMaleStandard",
                 "race": "Human", "sex": "male", "personality": "Standard"}}
QUESTS = {
    783: {"id": 783, "name": "Menace intérieure", "description": "J'espère que vous avez le coeur bien accroché.",
          "objectives": "Parler au maréchal McBride.", "completion": None,
          "starters": [{"type": "npc", "id": 823}], "enders": [{"type": "npc", "id": 197}]},
    18: {"id": 18, "name": "La confrérie des voleurs", "description": "Un groupe de voleurs…",
         "objectives": "Apporter 12 bandanas.", "completion": "Bien joué.",
         "starters": [{"type": "npc", "id": 823}], "enders": [{"type": "npc", "id": 823}]},
}


@pytest.fixture
def data_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(storage, "DATA_DIR", tmp_path)
    return tmp_path


def fake_call(data=PERSONA, calls=None):
    def call(system, prompt, schema, model, effort, bare=False):
        if calls is not None:
            calls.append(prompt)
        return Answer(dict(data), model, 0.03)
    return call


def test_dossier_is_built_from_the_registries_only():
    file = personas.dossier(NPC, QUESTS, ["Forêt d'Elwynn"])
    assert file["game_voice"] == {"kind": "archetype", "set": "HumanMaleStandard", "race": "Human",
                                  "sex": "male", "personality": "Standard"}
    assert [q["id"] for q in file["quests_given"]] == [18, 783]
    assert file["quests_ended"] == [{"id": 18, "name": "La confrérie des voleurs", "completion": "Bien joué."}]
    assert file["npc"]["new_in_forever"] is False


def test_hash_changes_with_the_inputs_only():
    a = personas.dossier(NPC, QUESTS, ["Forêt d'Elwynn"])
    assert personas.input_hash(a) == personas.input_hash(json.loads(json.dumps(a)))
    b = personas.dossier(NPC, {783: QUESTS[783]}, ["Forêt d'Elwynn"])
    assert personas.input_hash(a) != personas.input_hash(b)


def test_validate():
    assert personas.validate(PERSONA) == []
    assert "missing summary" in personas.validate({k: v for k, v in PERSONA.items() if k != "summary"})
    assert any("sex=" in p for p in personas.validate({**PERSONA, "sex": "other"}))
    assert any("sample_line" in p for p in personas.validate({**PERSONA, "sample_line": "Trop court."}))


def test_generate_then_skip_unchanged(data_dir):
    voices = personas.load_voices()
    jobs = personas.todo({823: NPC}, QUESTS, {823: ["Forêt d'Elwynn"]}, voices)
    calls = []
    report = personas.generate(jobs, voices, workers=1, call=fake_call(calls=calls), log=lambda *_: None)
    assert report["generated"] == 1 and len(calls) == 1
    saved = storage.read_json(data_dir / "voices.json")["npcs"]["823"]
    assert saved["persona"]["register"] == "militaire"
    assert saved["generator"]["prompt_version"] == personas.PROMPT_VERSION
    assert "qwen" not in saved and "voice_text" not in saved
    assert personas.todo({823: NPC}, QUESTS, {823: ["Forêt d'Elwynn"]}, personas.load_voices()) == []
    assert len(personas.todo({823: NPC}, QUESTS, {823: ["Forêt d'Elwynn"]}, personas.load_voices(), force=True)) == 1
    # a changed dossier (the NPC seen in another zone) does not regenerate an existing persona
    assert personas.todo({823: NPC}, QUESTS, {823: ["Forêt d'Elwynn", "Marche de l'Ouest"]},
                         personas.load_voices()) == []


def test_regeneration_keeps_the_model_voice(data_dir):
    voices = personas.load_voices()
    jobs = personas.todo({823: NPC}, QUESTS, {823: []}, voices)
    personas.generate(jobs, voices, workers=1, call=fake_call(), log=lambda *_: None)
    voices = personas.load_voices()
    voices["npcs"]["823"]["qwen"] = {"status": "ok", "seed": 7}
    voices["npcs"]["823"]["voice_text"] = {"text": "Bonjour.", "source": "quête 6"}
    jobs = personas.todo({823: NPC}, QUESTS, {823: []}, voices, force=True)
    personas.generate(jobs, voices, workers=1, call=fake_call(), log=lambda *_: None)
    record = personas.load_voices()["npcs"]["823"]
    assert record["qwen"] == {"status": "ok", "seed": 7} and record["voice_text"]["source"] == "quête 6"


def test_invalid_answer_is_not_saved(data_dir):
    voices = personas.load_voices()
    jobs = personas.todo({823: NPC}, QUESTS, {823: []}, voices)
    report = personas.generate(jobs, voices, workers=1, call=fake_call({**PERSONA, "age": "?"}), log=lambda *_: None)
    assert report["failed"] == [823] and report["generated"] == 0
    assert not (data_dir / "voices.json").exists()


def fake_run(stdout, returncode=0):
    seen = {}

    def run(cmd, **kwargs):
        seen.update(cmd=cmd, **kwargs)
        return subprocess.CompletedProcess(cmd, returncode, stdout=stdout, stderr="boom")
    return run, seen


def test_claude_json_isolated_call():
    out = json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": "{}",
                      "structured_output": {"a": 1}, "total_cost_usd": 0.01,
                      "modelUsage": {"claude-opus-5-5": {}}})
    run, seen = fake_run(out)
    answer = claude_json("sys", "hello", {"type": "object"}, "claude-opus-5-5", run=run)
    assert answer.data == {"a": 1} and answer.cost_usd == 0.01 and answer.model == "claude-opus-5-5"
    cmd = seen["cmd"]
    assert cmd[cmd.index("--tools") + 1] == "" and "--no-session-persistence" in cmd
    assert cmd[cmd.index("--model") + 1] == "claude-opus-5-5" and "--bare" not in cmd
    assert seen["input"] == "hello"


def test_claude_json_records_the_model_that_wrote_the_answer():
    """Claude Code can list a small side call first (seen: Haiku on the Dun Morogh run)."""
    out = json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": "{}",
                      "structured_output": {"a": 1}, "total_cost_usd": 0.1,
                      "modelUsage": {"claude-haiku-4-5-20251001": {"outputTokens": 12},
                                     "claude-sonnet-5-5": {"outputTokens": 900}}})
    run, _ = fake_run(out)
    assert claude_json("sys", "hello", {"type": "object"}, "claude-sonnet-5-5", run=run).model == "claude-sonnet-5-5"


@pytest.mark.parametrize("stdout, code", [("not json", 0), (json.dumps({"subtype": "error_max_turns"}), 0), ("", 1)])
def test_claude_json_failures(stdout, code):
    run, _ = fake_run(stdout, code)
    with pytest.raises(LLMError):
        claude_json("sys", "hello", {}, "m", run=run)


def test_a_verified_sex_is_a_fact_never_overridden(data_dir):
    yohwa = {**NPC, "id": 733, "name": "Sergent Yohwa", "sex": {"value": "female", "source": "model"}}
    file = personas.dossier(yohwa, QUESTS, ["Marche de l'Ouest"])
    assert file["sex"] == {"value": "female", "source": "model"}
    assert "sex" not in personas.dossier(NPC, QUESTS, [])  # unknown: no field, Claude decides as before
    voices = personas.load_voices()
    jobs = personas.todo({733: yohwa}, QUESTS, {733: ["Marche de l'Ouest"]}, voices)
    personas.generate(jobs, voices, workers=1, call=fake_call(), log=lambda *_: None)  # Claude answers "male"
    saved = storage.read_json(data_dir / "voices.json")["npcs"]["733"]["persona"]
    assert saved["sex"] == "female" and saved["sex_evidence"] == "model"
