import json
import subprocess

import pytest

from tools.voices import act, critic, judge, oracle, reopen

GOOD = {"en": 0.0002, "fr": 0.99, "wer": 0.05, "cps": 14.0, "secs": 18.0}


def test_verdict_thresholds():
    assert judge.verdict(GOOD) == []
    assert judge.verdict({**GOOD, "en": 0.0015}) == []  # 0.15 % is still accepted
    assert judge.verdict({**GOOD, "en": 0.0016}) == ["en"]
    assert judge.verdict({**GOOD, "wer": 0.15}) == []
    assert judge.verdict({**GOOD, "wer": 0.151}) == ["wer"]
    assert judge.verdict({**GOOD, "cps": 6.9}) == ["cps"]
    assert judge.verdict({**GOOD, "en": 0.4, "wer": 0.3, "cps": 30}) == ["en", "wer", "cps"]


def test_word_error_rate_ignores_case_punctuation_and_splits_elisions():
    assert judge.word_error_rate("Oh non, non… L'abbaye !", "oh non non l' abbaye") == 0
    assert judge.word_error_rate("trois paniers à remplir", "trois peignets à remplir") == 0.25
    # spoken elisions in the sample lines, standard French in Whisper's transcript
    assert judge.word_error_rate("j'vous l'dis, l'vieux", "je vous le dis, le vieux") == 0


@pytest.fixture
def world(tmp_path, monkeypatch):
    """A repo in tmp_path: voices.json with three NPCs, a zone, the judge's folders."""
    samples = tmp_path / "data" / "voices" / "samples" / "qwen"
    monkeypatch.setattr(judge, "ROOT", tmp_path)
    monkeypatch.setattr(judge, "VOICES_FILE", tmp_path / "data" / "voices.json")
    monkeypatch.setattr(judge, "CANDIDATES", samples / "candidates")
    monkeypatch.setattr(judge, "VOICES", samples / "voices")
    monkeypatch.setattr(judge, "REVIEW", samples / "review")
    monkeypatch.setattr(judge, "TRIES_LOG", tmp_path / "data" / "cache" / "loops" / "voices" / "tries.jsonl")
    persona = {"sample_line": "Bonjour à vous.", "sex": "male", "age": "adulte"}
    npcs = {"1": {"name": "Willem", "race": {"value": "Human"}, "persona": persona},
            "2": {"name": "Grelin", "race": {"value": "Dwarf"}, "persona": persona},
            "3": {"name": "Muet", "persona": {}}}  # no sample line: not a speaker
    (tmp_path / "data").mkdir()
    judge.VOICES_FILE.write_text(json.dumps({"schema": 1, "npcs": npcs}), encoding="utf-8")
    zone = tmp_path / "data" / "zones" / "eastern-kingdoms" / "elwynn-forest"
    zone.mkdir(parents=True)
    (zone / "npcs.json").write_text(json.dumps({"npcs": {"1": {}, "2": {}, "3": {}}}), encoding="utf-8")
    return tmp_path


def candidate(npc, seed, text="Bonjour à vous."):
    folder = judge.CANDIDATES / npc
    folder.mkdir(parents=True, exist_ok=True)
    take = folder / f"s{seed}.wav"
    take.write_bytes(b"RIFF" + str(seed).encode())
    take.with_suffix(".json").write_text(json.dumps(
        {"npc": int(npc), "seed": seed, "engine": "qwen", "temperature": 0.7, "instruct": "desc", "text": text}))
    return take


def hearing(results):
    """Fake Whisper: seed -> (English probability, transcript)."""
    def hear(path):
        en, heard = results[int(path.stem[1:])]
        return {"en": en, "fr": 1 - en}, heard, 1.0
    return hear


def qwen(npc):
    return json.loads(judge.VOICES_FILE.read_text())["npcs"][npc]["qwen"]


def test_judge_promotes_a_good_take_and_logs_it(world):
    take = candidate("1", 7)
    counts = judge.judge([take], hear=hearing({7: (0.0, "Bonjour à vous.")}), say=lambda _: None)
    assert counts == {"ok": 1, "failed": 0, "not_found": 0}
    entry = qwen("1")
    assert entry["status"] == "ok" and entry["seed"] == 7 and entry["tries"] == 1 and entry["seeds"] == [7]
    assert (world / entry["ref"]).read_bytes() == b"RIFF7"
    assert (judge.VOICES / "1" / "ref.txt").read_text() == "Bonjour à vous.\n"
    assert not judge.CANDIDATES.joinpath("1").exists()
    log = [json.loads(x) for x in judge.TRIES_LOG.read_text().splitlines()]
    assert log[0]["npc"] == 1 and log[0]["failed"] == [] and log[0]["status"] == "ok"


def test_judge_keeps_only_the_best_failed_take_then_not_found_until_the_next_run(world):
    results = {s: (0.5, "Bonjour à vous.") for s in range(1, 6)}
    results[3] = (0.01, "Bonjour à vous.")  # the least English: the best failed take
    for seed in range(1, 6):
        judge.judge([candidate("2", seed)], hear=hearing(results), say=lambda _: None)
        assert qwen("2")["status"] == ("not_found" if seed == 5 else "pending")
    entry = qwen("2")
    assert entry["tries"] == 5 and entry["seeds"] == [1, 2, 3, 4, 5] and entry["best"]["seed"] == 3
    assert (judge.REVIEW / "2" / "best.wav").read_bytes() == b"RIFF3"
    assert entry["best"]["failed"] == ["en"]


def test_a_good_take_after_failures_clears_the_review(world):
    judge.judge([candidate("1", 1)], hear=hearing({1: (0.3, "Bonjour")}), say=lambda _: None)
    assert (judge.REVIEW / "1" / "best.wav").exists()
    judge.judge([candidate("1", 2)], hear=hearing({2: (0.0, "Bonjour à vous.")}), say=lambda _: None)
    entry = qwen("1")
    assert entry["status"] == "ok" and entry["tries"] == 2 and "best" not in entry
    assert not (judge.REVIEW / "1").exists()


def test_judge_drops_a_take_without_meta(world):
    take = candidate("1", 4)
    take.with_suffix(".json").unlink()
    assert judge.judge([take], hear=hearing({}), say=lambda _: None) == {"ok": 0, "failed": 0, "not_found": 0}
    assert not take.exists()


def fake_order(keys):
    def run(cmd, **_):
        return subprocess.CompletedProcess(cmd, 0, "".join(f"{k}\t7\t75\t1-11\n" for k in keys), "")
    return run


def test_oracle_counts_settled_npcs_and_checks_scores_again(world):
    zones = world / "data" / "zones"
    run = fake_order(["eastern-kingdoms/anvilmar", "eastern-kingdoms/elwynn-forest"])

    def ask():
        return oracle.ask(run=run, voices_file=judge.VOICES_FILE, zones=zones, root=world)

    assert ask() == {"done": False, "next": "eastern-kingdoms/elwynn-forest", "todo": ["eastern-kingdoms/elwynn-forest"],
                     "remaining": 2, "not_found": 0, "level": {"voices_ok": 0, "tries": 0}}
    judge.judge([candidate("1", 1)], hear=hearing({1: (0.0, "Bonjour à vous.")}), say=lambda _: None)
    assert ask()["level"] == {"voices_ok": 1, "tries": 1} and ask()["remaining"] == 1
    for seed in range(1, 6):
        judge.judge([candidate("2", seed)], hear=hearing({seed: (0.5, "x")}), say=lambda _: None)
    answer = ask()  # this run is over: NPC 2 was not found
    assert answer["done"] and answer["next"] is None and answer["remaining"] == 0 and answer["not_found"] == 1
    assert answer["level"] == {"voices_ok": 1, "tries": 6}
    # the next run reopens it with 5 more takes; the level does not move
    voices = json.loads(judge.VOICES_FILE.read_text())
    assert reopen.reopen(voices) == ["2"]
    judge.VOICES_FILE.write_text(json.dumps(voices))
    answer = ask()
    assert not answer["done"] and answer["remaining"] == 1 and answer["level"] == {"voices_ok": 1, "tries": 6}
    judge.judge([candidate("2", 6)], hear=hearing({6: (0.5, "x")}), say=lambda _: None)
    assert qwen("2")["status"] == "pending" and qwen("2")["tries"] == 6 and qwen("2")["campaign_tries"] == 1
    # archived takes (a voice text changed by hand) still count
    voices = json.loads(judge.VOICES_FILE.read_text())
    voices["npcs"]["2"]["qwen_history"] = [voices["npcs"]["2"].pop("qwen")]
    judge.VOICES_FILE.write_text(json.dumps(voices))
    assert ask()["level"] == {"voices_ok": 1, "tries": 7}
    # a voice whose recorded scores do not pass the thresholds, or whose file is gone, is not counted
    voices = json.loads(judge.VOICES_FILE.read_text())
    voices["npcs"]["1"]["qwen"]["scores"]["en"] = 0.2
    judge.VOICES_FILE.write_text(json.dumps(voices))
    assert ask()["level"]["voices_ok"] == 0 and ask()["remaining"] == 2


def test_new_seed_is_never_reused():
    class Rng:
        values = iter([5, 5, 9])

        def randrange(self, *_):
            return next(self.values)

    assert act.new_seed({5}, Rng()) == 9


def test_critic_failure_rate_by_race():
    voices = {"1": {"race": {"value": "Human"}}, "2": {"race": {"value": "Dwarf"}}}
    accents = {"default": "Human", "races": {"Human": {}, "Dwarf": {}}}
    tries = [{"npc": 1, "failed": []}, {"npc": 2, "failed": ["wer"]}, {"npc": 2, "failed": ["en", "wer"]},
             {"npc": 2, "failed": []}]
    assert critic.race_failures(tries, voices, accents) == [
        "Dwarf: 2/3 failed (mots mal lus 2, anglais 1)", "Human: 0/1 failed"]


def test_zone_page_lists_not_found_first_then_validated(world, monkeypatch):
    from tools.voices import page
    accents = world / "data" / "accents.json"
    accents.write_text(json.dumps({"default": "Human", "races": {
        "Human": {"name_fr": "Humain", "adj": ["humain", "humaine"]},
        "Dwarf": {"name_fr": "Nain", "adj": ["nain", "naine"]}}}), encoding="utf-8")
    monkeypatch.setattr(page, "ACCENTS", accents)
    monkeypatch.setattr(page, "PAGES", world / "pages")
    judge.judge([candidate("1", 1)], hear=hearing({1: (0.0, "Bonjour à vous.")}), say=lambda _: None)
    for seed in range(1, 6):
        judge.judge([candidate("2", seed)], hear=hearing({seed: (0.5, "x")}), say=lambda _: None)
    voices = json.loads(judge.VOICES_FILE.read_text())["npcs"]
    html = page.write("eastern-kingdoms/elwynn-forest", voices).read_text()
    assert "1 voix validée(s), 1 PNJ pas trouvé(s) à écouter, 0 en cours" in html
    assert html.index("Grelin") < html.index("Willem") and "Muet" not in html
    assert 'src="../data/voices/samples/qwen/review/2/best.wav"' in html
    assert 'src="../data/voices/samples/qwen/voices/1/ref.wav"' in html


def test_voice_text_is_the_records_own_else_the_sample_line():
    record = {"persona": {"sample_line": "Ha ! Bonjour."}}
    assert act.voice_text(record) == {"text": "Ha ! Bonjour.", "source": "persona.sample_line"}
    record["voice_text"] = {"text": "Bonjour à vous.", "source": "quête 33"}
    assert act.voice_text(record)["text"] == "Bonjour à vous."


def test_keep_voice_texts_writes_the_sample_line_once(world):
    act.keep_voice_texts(["1"])
    assert json.loads(judge.VOICES_FILE.read_text())["npcs"]["1"]["voice_text"] == {
        "text": "Bonjour à vous.", "source": "persona.sample_line"}


def test_npc_filter_of_the_voice_oracle(world, monkeypatch):
    monkeypatch.setenv("FS_NPCS", "2")
    assert oracle.pending("eastern-kingdoms/elwynn-forest", json.loads(judge.VOICES_FILE.read_text())["npcs"]) == ["2"]


def test_redo_archives_the_voice_and_deletes_readings_and_candidates(world, monkeypatch):
    from tools.voices import redo
    samples = world / "data" / "voices" / "samples" / "qwen"
    monkeypatch.setattr(redo, "SAMPLES", samples)
    monkeypatch.setattr(redo, "HISTORY", samples / "voices_history")
    monkeypatch.setattr(redo, "ZONES", world / "data" / "zones")
    monkeypatch.setattr(redo, "GAME_AUDIO", world / "addon" / "audio")
    from pipeline import build_index
    rebuilt = []
    monkeypatch.setattr(build_index, "main", rebuilt.append)  # never the repository's real index
    judge.judge([candidate("1", 1)], hear=hearing({1: (0.0, "Bonjour à vous.")}), say=lambda _: None)
    zone = world / "data" / "zones" / "eastern-kingdoms" / "elwynn-forest"
    master = world / "data" / "audio" / "18_detail.flac"
    master.parent.mkdir(parents=True)
    master.write_bytes(b"fLaC")
    (zone / "audio.json").write_text(json.dumps({"audio": {"18": {"npc": 1, "m": {"master": "data/audio/18_detail.flac"}}},
                                                 "complete": {}}))
    (zone / "readings.json").write_text(json.dumps({"readings": {"18_detail": {"npc": 1, "tries": 2, "best": {}}}}))
    (world / "addon" / "audio" / "1").mkdir(parents=True)
    pending = samples / "reading_candidates" / "eastern-kingdoms-elwynn-forest" / "18_detail_s5.json"
    pending.parent.mkdir(parents=True)
    pending.write_text(json.dumps({"npc": 1}))
    pending.with_suffix(".wav").write_bytes(b"RIFF")
    assert redo.main(["1"]) == 0 and rebuilt == [[]]
    record = json.loads(judge.VOICES_FILE.read_text())["npcs"]["1"]
    assert "qwen" not in record and record["qwen_history"][0]["seed"] == 1
    assert (world / record["qwen_history"][0]["ref"]).read_bytes() == b"RIFF1"
    assert json.loads((zone / "audio.json").read_text())["audio"] == {} and not master.exists()
    state = json.loads((zone / "readings.json").read_text())
    assert state["readings"] == {} and state["history"][0]["id"] == "18_detail" and state["history"][0]["tries"] == 2
    assert not pending.exists() and not pending.with_suffix(".wav").exists()
    assert not (world / "addon" / "audio" / "1").exists()


def test_a_kept_voice_take_passing_loosened_thresholds_becomes_the_voice(world, monkeypatch):
    judge.judge([candidate("2", 3)], hear=hearing({3: (0.004, "Bonjour à vous.")}), say=lambda _: None)
    assert judge.rejudge_kept(say=lambda _: None) == 0
    monkeypatch.setattr(judge, "MAX_EN", 0.005)
    monkeypatch.setenv("FS_NPCS", "1")  # another NPC: not touched
    assert judge.rejudge_kept(say=lambda _: None) == 0
    monkeypatch.setenv("FS_NPCS", "2")
    assert judge.rejudge_kept(say=lambda _: None) == 1
    entry = qwen("2")
    assert entry["status"] == "ok" and entry["seed"] == 3 and "best" not in entry
    assert (judge.VOICES / "2" / "ref.wav").read_bytes() == b"RIFF3"
    assert (judge.VOICES / "2" / "ref.txt").read_text() == "Bonjour à vous.\n"


def test_a_voice_text_changed_by_hand_archives_the_earlier_takes(world):
    judge.judge([candidate("2", 3)], hear=hearing({3: (0.5, "x")}), say=lambda _: None)
    assert act.archive_changed_texts(["2"]) == []  # same text: nothing to do
    voices = json.loads(judge.VOICES_FILE.read_text())
    voices["npcs"]["2"]["voice_text"] = {"text": "Un autre texte.", "source": "quête 7"}
    judge.VOICES_FILE.write_text(json.dumps(voices))
    assert act.archive_changed_texts(["2"], when="t") == ["2"]
    record = json.loads(judge.VOICES_FILE.read_text())["npcs"]["2"]
    assert "qwen" not in record and record["qwen_history"][0]["seeds"] == [3]
    assert not (judge.REVIEW / "2").exists()
