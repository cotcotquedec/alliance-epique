"""Loop of the voice pass: every NPC who speaks gets its voice, designed by Qwen3-TTS VoiceDesign and validated
by the judge. READ-ONLY for the loop (it says what is sealed and what an attempt may change). Architecture:
tools/loop/README.md; this loop: tools/voices/constitution.md."""

from tools.loop.engine import Pass
from tools.voices import arbiter, critic, oracle

PASS = Pass(
    name="voices",
    sealed=("tools/voices/constitution.md", "tools/voices/oracle.py", "tools/voices/judge.py", "tools/voices/names.py",
            "tools/voices/arbiter.py", "tools/voices/__init__.py", "tools/qwen_voices/frame.py", "data/accents.json",
            "tools/loop/arbiter.py", "tools/loop/ratchet.py", "tools/loop/seal.py"),
    # the registry only: the takes are too big to snapshot (a rollback keeps them)
    tracked=("data/voices.json",),
    oracle=oracle.ask,
    rules=arbiter.RULES,
    critic=critic.review,
)
