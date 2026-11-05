import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

from tools.loop import engine, ratchet, seal
from tools.loop.arbiter import Rules, State

NOW = datetime(2026, 10, 6, 10, 0, tzinfo=ZoneInfo("Europe/Paris"))
SEALED = ("tools/fake/constitution.md",)


def answer(n, done=False, zone="zone-a"):
    return {"done": done, "next": None if done else zone, "level": {"n": n}}


@pytest.fixture
def root(tmp_path):
    (tmp_path / "tools" / "fake").mkdir(parents=True)
    (tmp_path / "tools" / "fake" / "constitution.md").write_text("goal")
    seal.write(tmp_path / "tools" / "fake" / "SEAL", list(SEALED), tmp_path)
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "reg.json").write_text('{"v": 1}')
    return tmp_path


def make(oracle_answers, critic_log=None):
    answers = iter(oracle_answers)

    def critic(zone, code, tail, after, run_dir):
        if critic_log is not None:
            critic_log.append((zone, code))

    return engine.Pass(name="fake", sealed=SEALED, tracked=("data/*.json",), oracle=lambda: next(answers),
                       rules=Rules(limit=frozenset({75})), critic=critic)


def loop(spec, root, runs, sleeps=None, lines=None):
    runs = iter(runs)

    def act(zone, log_path: Path):
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(zone)
        code, tail, effect = next(runs)
        if effect:
            effect(root)
        return code, tail

    return engine.run(spec, State(), root=root, act=act, sleep=(sleeps if sleeps is not None else []).append,
                      clock=lambda: NOW, say=(lines if lines is not None else []).append)


def test_loop_until_done(root):
    critic = []
    spec = make([answer(1), answer(2), answer(2), answer(3), answer(4, done=True)], critic)
    sleeps = []
    code = loop(spec, root, [(75, "usage limit reached", None), (1, "oops", None), (0, "ok", None),
                             (0, "ok", None)], sleeps)
    assert code == engine.EXIT_DONE
    assert sleeps == [30 * 60, 5 * 60, 60]
    assert len(critic) == 4
    run_dir = root / "data" / "cache" / "loops" / "fake"
    last = json.loads((run_dir / "last.json").read_text())
    assert last["attempt"] == 4 and last["action"] == "done" and last["resume_at"] is None
    assert ratchet.load(run_dir / "ratchet.json") == {"n": 4}
    assert len((run_dir / "journal.jsonl").read_text().splitlines()) == 4
    assert len(list((run_dir / "logs").glob("*.log"))) == 4


def test_data_loss_rolls_back_into_quarantine(root):
    def damage(r):
        (r / "data" / "reg.json").write_text('{"v": 0}')
        (r / "data" / "new.json").write_text("{}")

    spec = make([answer(5), answer(4)])
    assert loop(spec, root, [(0, "", damage)]) == engine.EXIT_LOSS
    assert (root / "data" / "reg.json").read_text() == '{"v": 1}'  # restored
    assert not (root / "data" / "new.json").exists()
    quarantine = next((root / "data" / "cache" / "loops" / "fake" / "quarantine").iterdir())
    assert (quarantine / "files" / "data" / "reg.json").read_text() == '{"v": 0}'
    assert (quarantine / "files" / "data" / "new.json").exists()
    assert "DATA LOSS" in (quarantine / "reason.txt").read_text()
    # the ratchet stayed at its highest level
    assert ratchet.load(root / "data" / "cache" / "loops" / "fake" / "ratchet.json") == {"n": 5}


def test_level_below_ratchet_at_start_stops(root):
    ratchet.tighten(root / "data" / "cache" / "loops" / "fake" / "ratchet.json", {"n": 9}, "t")
    lines = []
    assert loop(make([answer(3)]), root, [], lines=lines) == engine.EXIT_LOSS
    assert "DATA LOSS" in lines[-1]


def test_reset_ratchet_starts_again_from_the_level_at_launch(root):
    path = root / "data" / "cache" / "loops" / "fake" / "ratchet.json"
    ratchet.tighten(path, {"n": 9, "gone": 2}, "t")
    lines = []
    code = engine.run(make([answer(3, done=True)]), State(), root=root, act=None, sleep=[].append,
                      clock=lambda: NOW, say=lines.append, reset_ratchet=True)
    assert code == engine.EXIT_DONE and ratchet.load(path) == {"n": 3}
    assert "ratchet reset" in lines[0]


def test_loop_limited_to_a_zone(root):
    def ans(n, todo):
        return {"done": not todo, "next": todo[0] if todo else None, "todo": todo, "level": {"n": n}}

    spec = make([ans(1, ["a/x", "b/elwynn"]), ans(2, ["a/x"])])
    zones_acted = []

    def act(zone, log_path):
        zones_acted.append(zone)
        return 0, ""

    code = engine.run(spec, State(), root=root, act=act, sleep=lambda s: None, clock=lambda: NOW,
                      say=lambda *_: None, zones=["b/elwynn"])
    assert code == engine.EXIT_DONE and zones_acted == ["b/elwynn"]  # a/x is left alone


def test_ratchet_never_goes_down(tmp_path):
    path = tmp_path / "ratchet.json"
    assert ratchet.tighten(path, {"a": 2, "b": 1}, "t") == {"a": 2, "b": 1}
    with pytest.raises(ValueError):
        ratchet.tighten(path, {"a": 1, "b": 5}, "t")
    assert ratchet.load(path) == {"a": 2, "b": 1}


def test_broken_seal_refuses_to_run(root):
    (root / "tools" / "fake" / "constitution.md").write_text("goal: whatever the loop likes")
    lines = []
    assert loop(make([answer(1)]), root, [], lines=lines) == engine.EXIT_SEAL
    assert any("changed since the seal" in ln for ln in lines)


def test_seal_broken_during_an_attempt_stops(root):
    def tamper(r):
        (r / "tools" / "fake" / "constitution.md").write_text("done = True")

    assert loop(make([answer(1), answer(2)]), root, [(0, "", tamper)]) == engine.EXIT_SEAL


def test_missing_seal(root):
    (root / "tools" / "fake" / "SEAL").unlink()
    assert loop(make([answer(1)]), root, []) == engine.EXIT_SEAL


def test_stop_keeps_the_log_in_quarantine(root):
    spec = make([answer(1), answer(1), answer(1)])
    assert loop(spec, root, [(1, "x", None), (1, "Traceback", None)]) == engine.EXIT_STOP
    quarantine = list((root / "data" / "cache" / "loops" / "fake" / "quarantine").iterdir())
    assert len(quarantine) == 1 and "no progress twice" in (quarantine[0] / "reason.txt").read_text()


def test_run_actor_streams_and_logs(tmp_path, capsys):
    code, tail = engine.run_actor(["sh", "-c", "echo one; echo 'limit reached' >&2; exit 75"],
                                  tmp_path / "logs" / "a.log", tmp_path)
    assert code == 75 and tail == "one\nlimit reached\n"
    assert (tmp_path / "logs" / "a.log").read_text() == tail
    assert capsys.readouterr().out == tail


def test_loop_writes_its_progress(root):
    spec = make([{**answer(1), "todo": ["zone-a", "zone-b"]}, answer(2, done=True)])
    assert loop(spec, root, [(0, "ok", None)]) == engine.EXIT_DONE
    board = json.loads((root / "data" / "cache" / "loops" / "fake" / "progress" / "loop.json").read_text())
    assert board["state"] == "done" and board["attempt"] == 1 and board["zone"] == "zone-a"
    assert board["remaining_start"] == 2 and board["remaining"] == 0 and board["unit"] == "categories"


def test_round_takes_categories_until_the_budget(monkeypatch):
    counts = {"a": 120, "b": 70, "c": 50, "d": 5}
    monkeypatch.setattr(engine, "zone_counts", lambda name, todo: {k: counts[k] for k in todo})
    answer_ = {"next": "a", "todo": ["a", "b", "c", "d"]}
    assert engine.round_of("voices", answer_, 200) == ["a", "b"]
    assert engine.round_of("readings", answer_, 100) == ["a"]  # always one category, even past the budget
    assert engine.round_of("readings", answer_, 1000) == ["a", "b", "c", "d"]
    assert engine.round_of("text", answer_, 200) == ["a"]  # other passes: one category per attempt


def test_a_round_of_several_categories_reaches_the_actor_and_the_critic(root, monkeypatch):
    monkeypatch.setattr(engine, "round_of", lambda name, answer, budget=None: ["zone-a", "zone-b"])
    critic, seen = [], []
    spec = make([answer(1), answer(2, done=True)], critic)

    def act(zone, log_path):
        seen.append(zone)
        return 0, ""

    assert engine.run(spec, State(), root=root, act=act, sleep=lambda s: None, clock=lambda: NOW,
                      say=lambda line: None) == engine.EXIT_DONE
    assert seen == ["zone-a zone-b"] and critic == [("zone-a", 0), ("zone-b", 0)]
    last = json.loads((root / "data" / "cache" / "loops" / "fake" / "last.json").read_text())
    assert last["zone"] == "zone-a" and last["zones"] == ["zone-a", "zone-b"]
