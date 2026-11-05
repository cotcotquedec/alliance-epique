import json
import os

import pytest

from tools.loop import dashboard, progress


@pytest.fixture
def root(tmp_path, monkeypatch):
    monkeypatch.setattr(progress, "ROOT", tmp_path)
    monkeypatch.setattr(progress.folder, "__defaults__", (tmp_path,))
    return tmp_path


def test_rates_learn_and_persist(tmp_path):
    rates = progress.Rates(tmp_path / "rates.json")
    assert rates.expect(140, 8) == pytest.approx(progress.WALL * 140 / progress.CPS)
    rates.learn([100, 200], [10.0, 20.0], longest=200, wall=40.0, batch=2)
    again = progress.Rates(tmp_path / "rates.json")
    assert again.cps == pytest.approx(0.7 * progress.CPS + 0.3 * 10)
    assert again.wall[2] == pytest.approx(40 / (200 / again.cps), rel=1e-3)
    assert again.wall_for(3) == again.wall[2]  # the nearest batch size learned


def test_record_writes_atomically(tmp_path):
    rec = progress.Record(tmp_path / "p" / "x.json", a=1)
    rec.add("a", 2)
    data = json.loads((tmp_path / "p" / "x.json").read_text())
    assert data["a"] == 3 and data["pid"] == os.getpid()
    assert [p.name for p in (tmp_path / "p").iterdir()] == ["x.json"]


def test_bar():
    assert dashboard.bar(0, 4) == "[····]"
    assert dashboard.bar(0.5, 4) == "[██··]"
    assert dashboard.bar(1.5, 4) == "[████]"


def test_dashboard_without_progress(root):
    assert "never run" in dashboard.render("voices", 0)[0]


def test_dashboard_shows_run_category_and_batch(root):
    now = 10_000.0
    folder = progress.folder("readings")
    progress.write(folder / "loop.json", {
        "pass": "readings", "scope": "--all", "started": now - 3600, "state": "acting", "attempt": 3,
        "unit": "readings", "parallel": "8", "pid": os.getpid(), "updated": now, "attempt_started": now - 60,
        "remaining_start": 100, "remaining": 80, "level_start": {"tries": 10}, "level": {"tries": 40},
        "zones_left": 5, "zone": "kalimdor/teldrassil"})
    progress.write(folder / "actor.json", {
        "zones": ["kalimdor/teldrassil", "kalimdor/darkshore"], "started": now - 59, "phase": "generating and judging", "takes": 16,
        "generated": 0, "judged": 4, "ok": 3, "failed": 1, "not_found": 1, "updated": now})
    progress.write(folder / "slots.json", {
        "parallel": 8, "total": 16, "done": 8, "batch": 2, "batches": 2, "loading": False,
        "batch_started": now - 10, "updated": now - 10,
        "slots": [{"label": "783_detail Adjoint Willem", "expected": 20.0},
                  {"label": "7_detail Maréchal McBride", "expected": 5.0}]})
    text = "\n".join(dashboard.render("readings", now, 120))
    assert "elapsed 01:00:00" in text and "parallel 8" in text
    assert "24/100 readings" in text  # 20 settled before the attempt, 3 kept and 1 not found in it
    assert "takes judged 34 this run" in text
    assert "8/16 takes" in text and "4/16: 3 kept, 1 failed, 1 not found" in text
    assert "2 categories, kalimdor/teldrassil … kalimdor/darkshore" in text
    assert "batch 2/2" in text
    assert " 50% ~  10s" in text  # 10 s of an expected 20
    assert " 99% ~   0s" in text  # past its estimate: waits for the batch


def test_dashboard_ignores_files_of_an_older_attempt(root):
    now = 10_000.0
    folder = progress.folder("voices")
    progress.write(folder / "loop.json", {"pass": "voices", "started": now - 100, "state": "acting",
                                          "pid": os.getpid(), "attempt_started": now - 5, "remaining_start": 10,
                                          "remaining": 10, "unit": "NPCs", "zone": "z"})
    progress.write(folder / "actor.json", {"zones": ["old"], "started": now - 50, "ok": 9, "takes": 9})
    text = "\n".join(dashboard.render("voices", now))
    assert "0/10 NPCs" in text and "round     z: starting" in text and "old" not in text


def test_dashboard_says_a_dead_loop_is_not_running(root):
    progress.write(progress.folder("voices") / "loop.json", {"pass": "voices", "started": 0, "state": "acting",
                                                              "pid": 2 ** 22 + 12345, "updated": 50})
    assert "not running" in dashboard.render("voices", 100)[1]
