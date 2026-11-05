"""Loop of the books pass (D19, 2026-10-21): every page of every book of the Alliance scope gets its audio, read by
ElevenLabs in Elise's fixed voice and validated by the judge. READ-ONLY for the loop (it says what is sealed and what
an attempt may change). Architecture: tools/loop/README.md; this loop: tools/books/constitution.md."""

from tools.books import arbiter, critic, oracle
from tools.loop.engine import Pass

PASS = Pass(
    name="books",
    sealed=("tools/books/constitution.md", "tools/books/oracle.py", "tools/books/judge.py", "tools/books/frame.py",
            "tools/books/arbiter.py", "tools/books/__init__.py", "tools/elise/frame.py", "tools/voices/judge.py",
            "tools/voices/names.py", "tools/loop/arbiter.py", "tools/loop/ratchet.py", "tools/loop/seal.py"),
    tracked=("data/zones/@books/audio.json", "data/books/state.json"),
    oracle=oracle.ask,
    rules=arbiter.RULES,
    critic=critic.review,
)
