import json
import subprocess

from pipeline import storage
from tools.base import PASS as BASE
from tools.loop import seal
from tools.text import PASS as TEXT
from tools.text import oracle as text_oracle
from tools.voices import PASS as VOICES
from tools.readings import PASS as READINGS

PROGRESS = {"quests": 432, "scripts_done": 171, "audio_done": 113, "zones_text": 5, "zones_audio": 1, "zones": 112,
            "personas": 97, "next_text": "uncategorized", "next_audio": "eastern-kingdoms/anvilmar",
            "todo_text": ["uncategorized", "eastern-kingdoms/elwynn-forest"],
            "todo_audio": ["eastern-kingdoms/anvilmar", "eastern-kingdoms/elwynn-forest"]}


def fake_run(progress, code=0):
    def run(cmd, **_):
        return subprocess.CompletedProcess(cmd, code, "fetching...\n" + json.dumps(progress) + "\n", "boom")
    return run


def test_text_oracle():
    assert text_oracle.ask(fake_run(PROGRESS)) == {
        "done": False, "next": "uncategorized", "todo": ["uncategorized", "eastern-kingdoms/elwynn-forest"],
        "level": {"zones_text": 5, "scripts_done": 171, "personas": 97, "quests": 432}}
    assert text_oracle.ask(fake_run({**PROGRESS, "next_text": None}))["done"] is True


def test_focus_on_some_categories():
    from tools.loop.engine import focus
    answer = text_oracle.ask(fake_run(PROGRESS))
    only = focus(answer, ["eastern-kingdoms/elwynn-forest"])
    assert only["next"] == "eastern-kingdoms/elwynn-forest" and not only["done"]
    assert only["level"] == answer["level"]  # the ratchet stays global
    assert focus(answer, ["eastern-kingdoms/westfall"])["done"] is True
    assert focus(answer, None) is answer

def test_oracle_failure_raises():
    try:
        text_oracle.ask(fake_run(PROGRESS, code=1))
    except RuntimeError as err:
        assert "boom" in str(err)
    else:
        raise AssertionError("expected RuntimeError")


def test_passes_seal_their_own_criteria():
    for spec in (BASE, TEXT, VOICES, READINGS):
        for name in ("constitution.md", "oracle.py", "arbiter.py", "__init__.py"):
            assert f"tools/{spec.name}/{name}" in spec.sealed
        assert "tools/loop/ratchet.py" in spec.sealed and "tools/loop/arbiter.py" in spec.sealed
        assert all((storage.REPO_ROOT / f).exists() for f in spec.sealed)
        assert (storage.REPO_ROOT / spec.actor).exists()
        # the seal itself is written by a human after review: only check that it can be computed
        assert seal.digest(storage.REPO_ROOT / spec.sealed[0])


def test_text_critic(tmp_path, monkeypatch):
    from pipeline.zones import catalog
    from tools.text import critic as text_critic
    zone_dir = tmp_path / "z"
    npc = [{"type": "npc", "id": 823}]
    storage.write_json(zone_dir / "quests.json", {"quests": {
        "6": {"id": 6, "description": "Garrick rôde.", "objectives": "Tuer Garrick.", "starters": npc, "side": 1},
        "7": {"id": 7, "description": "Va voir.", "objectives": "x", "starters": [{"type": "npc", "id": 99}]},
        "8": {"id": 8, "description": None, "objectives": None, "starters": npc},
        "9": {"id": 9, "description": "Un corps.", "objectives": "x", "starters": [{"type": "object", "id": 5}]},
        "10": {"id": 10, "description": "Horde.", "objectives": "x", "starters": npc, "side": 2}}})
    storage.write_json(zone_dir / "scripts.json", {"scripts": {"6": {}}})
    monkeypatch.setattr(catalog, "zone_dir", lambda key: zone_dir)
    monkeypatch.setattr(text_critic.personas, "load_voices", lambda: {"npcs": {"823": {"name": "Adjoint Willem"}}})
    text_critic.review("z", 75, "STOPPED: Claude usage limit reached, during z.\n", {}, tmp_path)
    entry = json.loads((tmp_path / "backlog.json").read_text())["z"]
    assert entry["start: speaking NPCs without persona"] == [99]
    assert entry["start: quests without script yet"] == [7]
    assert entry["start: quests without French text (in-game capture)"] == [8]
    assert entry["start: quests without NPC speaker (narrator voice, D9)"] == [9]
    assert entry["end: quests without script yet"] == []
    assert entry["errors in the last output"] == ["STOPPED: Claude usage limit reached, during z."]
