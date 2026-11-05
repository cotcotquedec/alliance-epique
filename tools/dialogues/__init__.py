"""Loop of the dialogues pass (2026-10-10): every page of an NPC's dialogue window gets its audio, read by Qwen3-TTS
Base cloning the NPC's model voice and validated by the judge. READ-ONLY for the loop (it says what is sealed and
what an attempt may change). Architecture: tools/loop/README.md; this loop: tools/dialogues/constitution.md."""

from tools.dialogues import arbiter, critic, oracle
from tools.loop.engine import Pass

PASS = Pass(
    name="dialogues",
    sealed=("tools/dialogues/constitution.md", "tools/dialogues/oracle.py", "tools/dialogues/judge.py",
            "tools/dialogues/frame.py", "tools/dialogues/arbiter.py", "tools/dialogues/__init__.py",
            "tools/readings/judge.py", "tools/readings/frame.py", "tools/readings/oracle.py",
            "tools/voices/judge.py", "tools/voices/names.py", "tools/voices/oracle.py",
            "tools/loop/arbiter.py", "tools/loop/ratchet.py", "tools/loop/seal.py"),
    tracked=("data/zones/**/dialogue_audio.json", "data/zones/**/dialogue_readings.json"),
    oracle=oracle.ask,
    rules=arbiter.RULES,
    critic=critic.review,
)
