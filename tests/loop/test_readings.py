import json
import subprocess

import pytest

from tools.readings import frame, judge, oracle, reopen
from tools.voices import judge as voice_judge

GOOD = {"en": 0.0003, "fr": 0.99, "wer": 0.03, "cps": 17.0, "secs": 20.0, "sim": 0.9}
ZONE = "eastern-kingdoms/elwynn-forest"


def test_units_resolve_gendered_texts_and_both_kinds():
    scripts = {"scripts": {"6": {"npc_id": 823, "name": "La prime", "gendered": True,
                                 "text": "Vous êtes <un héros/une héroïne>.\n\nObjectif : Tuer Garrick."},
                           "7": {"npc_id": 197, "name": "Sans texte", "text": ""}},
               "complete": {"6": {"npc_id": 823, "name": "La prime", "text": "Merci."}}}
    units = frame.units(scripts)
    assert [u["id"] for u in units] == ["6_detail", "6_detail_f", "6_complete"]
    assert units[1]["text"] == "Vous êtes une héroïne.\n\nObjectif : Tuer Garrick." and units[1]["sex"] == "f"
    assert frame.paragraphs(units[0]["text"]) == ["Vous êtes un héros.", "Objectif : Tuer Garrick."]


def test_verdict_adds_the_voice_similarity():
    assert judge.verdict(GOOD) == []
    assert judge.verdict({**GOOD, "sim": 0.74}) == ["sim"]
    assert judge.verdict({**GOOD, "en": 0.002, "sim": 0.5}) == ["en", "sim"]


@pytest.fixture
def world(tmp_path, monkeypatch):
    """A repo in tmp_path: one NPC with a model voice (823), one without (197), a zone with their scripts."""
    for mod, name, value in [
            (judge, "ROOT", tmp_path), (judge, "ZONES", tmp_path / "data" / "zones"),
            (judge, "CANDIDATES", tmp_path / "cand"), (judge, "REVIEW", tmp_path / "review"),
            (judge, "GAME_AUDIO", tmp_path / "addon" / "ForeverSpeech" / "audio"),
            (judge, "MASTERS", tmp_path / "data" / "audio"), (judge, "TRIES_LOG", tmp_path / "tries.jsonl"),
            (voice_judge, "ROOT", tmp_path), (voice_judge, "VOICES_FILE", tmp_path / "data" / "voices.json")]:
        monkeypatch.setattr(mod, name, value)
    ref = tmp_path / "voices" / "823" / "ref.wav"
    ref.parent.mkdir(parents=True)
    ref.write_bytes(b"RIFF")
    persona = {"sample_line": "Bonjour."}
    (tmp_path / "data").mkdir()
    voice_judge.VOICES_FILE.write_text(json.dumps({"npcs": {
        "823": {"name": "Willem", "persona": persona, "qwen": {"status": "ok", "seed": 5, "ref": "voices/823/ref.wav",
                                                               "scores": {"en": 0, "wer": 0, "cps": 15}}},
        "197": {"name": "McBride", "persona": persona}}}))
    folder = judge.ZONES / ZONE
    folder.mkdir(parents=True)
    (folder / "scripts.json").write_text(json.dumps({"scripts": {
        "18": {"npc_id": 823, "name": "Voleurs", "text": "Un groupe de voleurs."},
        "7": {"npc_id": 197, "name": "Kobolds", "text": "Des kobolds."}}}))

    def to_file(src, dst):
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(src.read_bytes())
    from pipeline.voices import audio
    monkeypatch.setattr(audio, "to_ogg", to_file)
    monkeypatch.setattr(audio, "to_flac", to_file)
    return tmp_path


class FakeEars:
    def __init__(self, results):
        self.results = results  # seed -> scores

    def scores(self, take, text, model_voice):
        seed = int(take.stem.rsplit("_s", 1)[1])
        return self.results[seed], text


def candidate(unit_id, seed, npc=823, text="Un groupe de voleurs."):
    folder = judge.CANDIDATES / judge.flat(ZONE)
    folder.mkdir(parents=True, exist_ok=True)
    take = folder / f"{unit_id}_s{seed}.wav"
    take.write_bytes(b"RIFF" + str(seed).encode())
    quest, kind = unit_id.split("_")[:2]
    take.with_suffix(".json").write_text(json.dumps(
        {"id": unit_id, "quest": int(quest), "kind": kind, "sex": "m", "npc": npc, "text": text, "seed": seed,
         "engine": "qwen-base", "voice_seed": 5, "voice_ref": "voices/823/ref.wav"}))
    return take


def fake_order(run_keys=(ZONE,)):
    def run(cmd, **_):
        return subprocess.CompletedProcess(cmd, 0, "".join(f"{k}\t7\t75\t1-11\n" for k in run_keys), "")
    return run


def ask(world):
    return oracle.ask(run=fake_order(), voices_file=voice_judge.VOICES_FILE, root=world)


def test_an_accepted_reading_goes_to_the_game_and_audio_json(world):
    answer = ask(world)
    assert answer["remaining"] == 1 and answer["waiting_voice"] == 1  # McBride has no model voice yet
    status = judge.judge_take(ZONE, candidate("18_detail", 9), FakeEars({9: GOOD}), say=lambda _: None)
    assert status == "ok"
    item = json.loads((judge.ZONES / ZONE / "audio.json").read_text())["audio"]["18"]
    assert item["npc"] == 823 and item["m"]["file"] == "Interface\\AddOns\\ForeverSpeech\\audio\\823\\18_detail.ogg"
    assert item["m"]["model"] == judge.MODEL and item["m"]["stamp"]["voice"] == "q5"
    assert (judge.GAME_AUDIO / "823" / "18_detail.ogg").read_bytes() == b"RIFF9"
    assert (world / item["m"]["master"]).exists()
    answer = ask(world)
    assert answer["done"] and answer["level"] == {"readings_ok": 1, "tries": 1}


def test_failed_readings_keep_the_best_then_are_not_found_until_the_next_run(world):
    results = {s: {**GOOD, "en": 0.01} for s in range(1, 6)}
    results[3] = {**GOOD, "sim": 0.7}  # one criterion failed only: the best
    for seed in range(1, 6):
        judge.judge_take(ZONE, candidate("18_detail", seed), FakeEars(results), say=lambda _: None)
    state = json.loads(judge.state_file(ZONE).read_text())
    entry = state["readings"]["18_detail"]
    assert entry["status"] == "not_found" and entry["best"]["seed"] == 3 and entry["best"]["failed"] == ["sim"]
    assert ask(world)["done"] and ask(world)["not_found"] == 1
    assert reopen.reopen(state) == ["18_detail"]
    judge._write(judge.state_file(ZONE), state)
    answer = ask(world)
    assert not answer["done"] and answer["level"] == {"readings_ok": 0, "tries": 5}


def test_only_a_qwen3_reading_counts(world):
    game = judge.GAME_AUDIO / "823" / "18_detail.ogg"
    game.parent.mkdir(parents=True)
    game.write_bytes(b"OggS")
    (judge.ZONES / ZONE / "audio.json").write_text(json.dumps({"audio": {"18": {"npc": 823, "m": {
        "file": "Interface\\AddOns\\ForeverSpeech\\audio\\823\\18_detail.ogg", "model": "eleven_v4"}}}}))
    assert ask(world)["level"]["readings_ok"] == 0 and ask(world)["remaining"] == 1  # another engine: to redo

def test_npc_filter(world, monkeypatch):
    voices = json.loads(voice_judge.VOICES_FILE.read_text())["npcs"]
    voices["197"]["qwen"] = dict(voices["823"]["qwen"])
    monkeypatch.setenv("FS_NPCS", "197")
    todo = oracle.zone_readings(ZONE, voices, root=world)["todo"]
    assert [u["id"] for u in todo] == ["7_detail"]


def test_a_kept_take_passing_loosened_thresholds_becomes_the_audio(world, monkeypatch):
    judge.judge_take(ZONE, candidate("18_detail", 4), FakeEars({4: {**GOOD, "en": 0.003}}), say=lambda _: None)
    assert judge.rejudge_kept(ZONE, say=lambda _: None) == 0  # still failing
    monkeypatch.setattr(voice_judge, "MAX_EN", 0.005)  # the user loosens the English threshold
    assert judge.rejudge_kept(ZONE, say=lambda _: None) == 1
    entry = json.loads(judge.state_file(ZONE).read_text())["readings"]["18_detail"]
    assert entry["status"] == "ok" and entry["seed"] == 4 and "best" not in entry
    item = json.loads((judge.ZONES / ZONE / "audio.json").read_text())["audio"]["18"]["m"]
    assert item["text"] == "Un groupe de voleurs." and item["stamp"]["voice"] == "q5"
    assert (judge.GAME_AUDIO / "823" / "18_detail.ogg").read_bytes() == b"RIFF4"
    assert ask(world)["level"]["readings_ok"] == 1


def test_a_qwen_reading_counts_only_with_passing_scores_and_its_file(world):
    judge.judge_take(ZONE, candidate("18_detail", 9), FakeEars({9: GOOD}), say=lambda _: None)
    assert ask(world)["level"]["readings_ok"] == 1
    audio_path = judge.ZONES / ZONE / "audio.json"
    audio = json.loads(audio_path.read_text())
    audio["audio"]["18"]["m"]["scores"]["sim"] = 0.5  # recorded scores no longer pass
    audio_path.write_text(json.dumps(audio))
    assert ask(world)["level"]["readings_ok"] == 0
    audio["audio"]["18"]["m"]["scores"]["sim"] = 0.9
    audio_path.write_text(json.dumps(audio))
    (judge.GAME_AUDIO / "823" / "18_detail.ogg").unlink()  # the game file is gone
    assert ask(world)["level"]["readings_ok"] == 0


def test_short_takes_get_the_short_thresholds():
    from tools.readings import judge as rj
    base = {"en": 0.0001, "wer": 0.0, "cps": 12.0}
    assert rj.verdict({**base, "sim": 0.66, "secs": 2.5}) == []  # under 3 s: 0.65
    assert rj.verdict({**base, "sim": 0.66, "secs": 4.0}) == ["sim"]  # 3 to 5 s: 0.70
    assert rj.verdict({**base, "sim": 0.72, "secs": 4.0}) == []
    assert rj.verdict({**base, "sim": 0.72, "secs": 6.0}) == ["sim"]  # from 5 s: 0.75, unchanged
    assert rj.verdict({**base, "en": 0.004, "sim": 0.9, "secs": 4.0}) == []  # English 0.5 % under 5 s
    assert rj.verdict({**base, "en": 0.004, "sim": 0.9, "secs": 6.0}) == ["en"]
    assert rj.verdict({**base, "sim": 0.70}) == ["sim"]  # no length: the usual thresholds
