import json

import pytest

from pipeline import narrator, storage
from tools.books import act, frame, judge, oracle
from tools.elise import act as elise_act

TEXT = "Le parchemin est froid."
KEY = "@books"


@pytest.fixture
def world(tmp_path, monkeypatch):
    for name, value in (("ROOT", tmp_path), ("ZONES", tmp_path / "data" / "zones"),
                        ("STATE", tmp_path / "data" / "books" / "state.json"),
                        ("CANDIDATES", tmp_path / "elise" / "book_candidates"),
                        ("REVIEW", tmp_path / "elise" / "book_review"),
                        ("GAME_AUDIO", tmp_path / "addon" / "ForeverSpeech" / "audio"),
                        ("MASTERS", tmp_path / "data" / "audio"), ("TRIES_LOG", tmp_path / "tries.jsonl")):
        monkeypatch.setattr(judge, name, value)
    voices = tmp_path / "voices.json"
    voices.write_text(json.dumps({"npcs": {"1000000": {"name": "Elise", "elevenlabs": {"voice_id": "V1"}}}}))
    monkeypatch.setattr(judge.voice_judge, "VOICES_FILE", voices)
    monkeypatch.setattr(storage, "ZONES_DIR", tmp_path / "data" / "zones")
    folder = tmp_path / "data" / "zones" / KEY
    folder.mkdir(parents=True)
    pages = {"731": {"page": 731, "n": 1, "title": "Tombe d'Eliza", "npc_id": narrator.NARRATOR_ID, "text": TEXT,
                     "gendered": False},
             "1231": {"page": 1231, "n": 1, "title": "Titre", "npc_id": narrator.NARRATOR_ID,
                      "text": "Merci <l'aventurier/l'aventurière>.", "gendered": True}}
    (folder / "scripts.json").write_text(json.dumps({"pages": pages}))
    from pipeline.voices import audio

    def fake_encode(src, dst, *_):
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(b"OGG")
    monkeypatch.setattr(audio, "to_ogg", fake_encode)
    monkeypatch.setattr(audio, "to_flac", fake_encode)
    monkeypatch.setattr(elise_act, "decode", lambda mp3, wav: wav.write_bytes(b"RIFF") or 2.0)
    from pipeline import build_index, review
    monkeypatch.setattr(build_index, "main", lambda argv: None)
    monkeypatch.setattr(review, "publish_refused", lambda *a, **k: 0)
    return tmp_path


class Client:
    def __init__(self, credits=10000):
        self.credits, self.spoken = credits, []

    def subscription(self):
        return {"character_limit": self.credits, "character_count": 0, "next_character_count_reset_unix": 1793887604}

    def speak(self, voice_id, text, model_id, seed=None, settings=None, output_format=None):
        assert voice_id == "V1" and model_id == frame.TTS_MODEL
        self.spoken.append(text)
        return b"ID3"


def budget(world, limit=None, run="r1"):
    env = {"FS_LOOP_PID": run, **({"FS_BOOKS_BUDGET": str(limit)} if limit else {})}
    return act.Budget(world / "budget.json", env)


def pages(world):
    return oracle.zone_pages(KEY, "V1", judge._read(judge.STATE, {"lines": {}}), zones=world / "data" / "zones",
                             root=world)


def test_units_one_per_page_and_two_for_a_gendered_page(world):
    assert [u["id"] for u in pages(world)["todo"]] == ["book_731", "book_1231", "book_1231_f"]
    assert pages(world)["todo"][2]["text"] == "Merci l'aventurière."


def test_every_take_goes_in_place_without_whisper(world):
    assert act.main([KEY], client=Client(), budget=budget(world)) == 0
    z = pages(world)
    assert z["ok"] == 3 and z["todo"] == []
    item = json.loads((world / "data" / "zones" / KEY / "audio.json").read_text())["book"]["731"]
    assert item["npc"] == narrator.NARRATOR_ID and item["m"]["engine"] == "elevenlabs"
    assert item["m"]["file"].endswith("\\1000000\\book_731.ogg") and item["m"]["text_hash"] == frame.text_hash(TEXT)
    assert item["m"]["validated"]["rule"] == elise_act.TRUSTED
    assert (world / "addon" / "ForeverSpeech" / "audio" / "1000000" / "book_731.ogg").is_file()
    assert oracle.ask(voices_file=world / "voices.json", zones=world / "data" / "zones", root=world)["level"] == \
        {"pages_ok": 3, "tries": 3}


def test_the_budget_stops_the_run_and_counts_across_rounds(world, capsys):
    client = Client()
    assert act.main([KEY], client=client, budget=budget(world, limit=30)) == act.EXIT_BUDGET
    assert client.spoken == [TEXT]  # 23 characters spent, the next page does not fit
    assert act.main([KEY], client=client, budget=budget(world, limit=30)) == act.EXIT_BUDGET
    assert client.spoken == [TEXT]  # same run: nothing more
    assert act.main([KEY], client=client, budget=budget(world, limit=30, run="r2")) == act.EXIT_BUDGET
    assert len(client.spoken) == 2  # a new run starts again from 0


def test_credits_spent_stop_the_round_with_the_limit_code(world, capsys):
    client = Client(credits=30)
    assert act.main([KEY], client=client, budget=budget(world)) == act.EXIT_LIMIT
    assert client.spoken == [] and "credit limit reached|1793887604" in capsys.readouterr().out


def test_rules_and_scope():
    from tools.books import PASS, arbiter
    assert 75 in arbiter.RULES.limit and {76, 77} <= set(arbiter.RULES.halt)
    assert all((storage.REPO_ROOT / f).exists() for f in PASS.sealed)
    assert "tools/books/oracle.py" in PASS.sealed and "tools/elise/frame.py" in PASS.sealed


def test_books_run_with_all_only(capsys):
    from tools.loop.__main__ import main
    main(["check", "books", "--all", "--budget", "1000"])
    with pytest.raises(SystemExit):
        main(["check", "books", "--group", "classes"])
    with pytest.raises(SystemExit):
        main(["check", "elise", "--all", "--budget", "10"])


def test_dry_run_reads_without_calling_anyone(world, capsys):
    from tools.books import plan
    p = plan.plan(budget=30)
    assert p["to_do"] == 3 and p["pages_within_budget"] == 1 and p["voice"] == "V1"


def test_review_knows_a_book_page(world):
    from pipeline import review
    asset = review.Asset("book", KEY, "book_1231_f")
    assert asset.sex == "f" and asset.path == ("book", "1231") and asset.state_key == "lines"
