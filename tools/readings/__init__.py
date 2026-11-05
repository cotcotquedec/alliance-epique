"""Loop of the readings pass: every quest text whose NPC has a model voice gets its audio, read by Qwen3-TTS Base
cloning that voice and validated by the judge. READ-ONLY for the loop (it says what is sealed and what an attempt
may change). Architecture: tools/loop/README.md; this loop: tools/readings/constitution.md."""

from tools.loop.engine import Pass
from tools.readings import arbiter, critic, oracle

PASS = Pass(
    name="readings",
    sealed=("tools/readings/constitution.md", "tools/readings/oracle.py", "tools/readings/judge.py",
            "tools/readings/frame.py", "tools/readings/arbiter.py", "tools/readings/__init__.py",
            "tools/voices/judge.py", "tools/voices/names.py", "tools/voices/oracle.py",
            "tools/loop/arbiter.py", "tools/loop/ratchet.py", "tools/loop/seal.py"),
    # the registries and the index only: the takes are too big to snapshot (a rollback keeps them)
    tracked=("data/zones/**/audio.json", "data/zones/**/readings.json", "addon/ForeverSpeech/data/index.lua"),
    oracle=oracle.ask,
    rules=arbiter.RULES,
    critic=critic.review,
)
