from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from tools.voices.arbiter import RULES as VOICES
from tools.loop import arbiter as ar
from tools.loop.arbiter import State, next_state
from tools.text.arbiter import RULES as TEXT

PARIS = ZoneInfo("Europe/Paris")
NOW = datetime(2026, 10, 6, 10, 0, tzinfo=PARIS)


def lvl(zones_text=3, scripts=100, personas=40, quests=200):
    return {"zones_text": zones_text, "scripts_done": scripts, "personas": personas, "quests": quests}


def ans(done=False, **kw):
    return {"done": done, "next": None if done else "eastern-kingdoms/westfall", "level": lvl(**kw)}


BEFORE = lvl()
SAME = ans()
MORE = ans(scripts=130)


def decide(code, after, tail="", state=State(), rules=TEXT, before=BEFORE):
    return ar.decide(code, before, after, tail, state, NOW, rules)


def test_done():
    assert decide(0, ans(done=True, zones_text=112))[0] == "done"


def test_level_below_ratchet_rolls_back_even_when_done():
    action, _, reason = decide(0, ans(done=True, personas=39))
    assert action == "rollback" and "DATA LOSS" in reason and "personas 40 -> 39" in reason
    # one counter down is a loss even if another one went up
    assert decide(0, ans(zones_text=4, quests=150))[0] == "rollback"


def test_progress_retries_after_one_minute():
    assert decide(0, MORE)[:2] == ("retry", 60)
    assert decide(1, MORE, state=State(fails=1))[:2] == ("retry", 60)


def test_no_progress_twice_stops_with_summary():
    action, wait, _ = decide(1, SAME, "boom")
    assert action == "retry" and wait == ar.FAIL_WAIT
    state = next_state(State(), 1, BEFORE, SAME, TEXT)
    assert state.fails == 1
    action, _, reason = decide(0, SAME, "line 1\nTraceback: KeyError\n", state)
    assert action == "stop" and "Traceback: KeyError" in reason
    assert next_state(state, 0, BEFORE, MORE, TEXT).fails == 0  # progress resets the count


def test_limit_with_epoch_reset():
    at = NOW + timedelta(hours=3)
    out = f"...\nClaude AI usage limit reached|{int(at.timestamp())}\nSTOPPED: Claude usage limit reached"
    assert decide(75, MORE, out)[:2] == ("wait", 3 * 3600 + ar.LIMIT_MARGIN)


def test_limit_with_clock_reset():
    action, wait, reason = decide(75, SAME, "You've hit your limit · resets 3pm (Europe/Paris)")
    assert action == "wait" and wait == 5 * 3600 + ar.LIMIT_MARGIN and "15:00" in reason
    # a time already past today is tomorrow's; no time zone: the one of `now`
    assert ar.reset_time("resets 9:30am", NOW) == datetime(2026, 10, 7, 9, 30, tzinfo=PARIS)
    assert ar.reset_time("resets at 15:00", NOW) == datetime(2026, 10, 6, 15, 0, tzinfo=PARIS)
    assert ar.reset_time("resets 3 times", NOW) is None


def test_limit_without_reset_backs_off_up_to_two_hours():
    state, waits = State(), []
    for _ in range(4):
        action, wait, _ = decide(75, SAME, "usage limit reached", state)
        assert action == "wait"
        waits.append(wait // 60)
        state = next_state(state, 75, BEFORE, SAME, TEXT)
    assert waits == [30, 60, 120, 120]
    assert state.fails == 0  # a limit never counts as a failure
    assert decide(75, MORE, "usage limit reached", state)[1] == 30 * 60  # progress restarts the backoff


def test_stale_or_far_reset_is_ignored():
    past = int((NOW - timedelta(hours=1)).timestamp())
    assert decide(75, SAME, f"limit reached|{past}")[1] == 30 * 60
    far = int((NOW + timedelta(days=30)).timestamp())
    assert ar.reset_time(f"limit reached|{far}", NOW) is None


def test_block_once_waits_then_twice_stops():
    action, wait, _ = decide(69, SAME, "403 on ...")
    assert action == "wait" and wait == 3600
    state = next_state(State(), 69, BEFORE, SAME, TEXT)
    action, _, reason = decide(69, SAME, "403 on ...", state)
    assert action == "stop" and "investigate" in reason


def test_block_after_progress_gets_its_retry():
    state = next_state(State(), 69, BEFORE, SAME, TEXT)
    assert decide(69, MORE, "429", state)[0] == "wait"
    state = next_state(state, 69, BEFORE, MORE, TEXT)
    assert state.blocks == 1
    assert decide(69, ans(scripts=130), "429", state, before=lvl(scripts=130))[0] == "stop"


def test_voices_halt_without_their_environment():
    before = {"voices_ok": 1, "tries": 1}
    after = {"done": False, "next": "x", "level": {"voices_ok": 2, "tries": 2}}
    action, _, reason = ar.decide(77, before, after, "", State(), NOW, VOICES)
    assert action == "stop" and "tools/voices/setup.sh" in reason
    assert decide(77, MORE)[0] == "retry"  # 77 means nothing to the text pass

def test_max_attempts():
    assert decide(0, MORE, state=State(attempt=9, max_attempts=10))[0] == "stop"
