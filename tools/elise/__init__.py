"""Loop of the Elise pass (2026-10-10): every line of Elise, the narrator, gets its audio, read by ElevenLabs in her
fixed voice and validated by the judge. READ-ONLY for the loop (it says what is sealed and what an attempt may
change). Architecture: tools/loop/README.md; this loop: tools/elise/constitution.md."""

from tools.elise import arbiter, critic, oracle
from tools.loop.engine import Pass

PASS = Pass(
    name="elise",
    sealed=("tools/elise/constitution.md", "tools/elise/oracle.py", "tools/elise/judge.py", "tools/elise/frame.py",
            "tools/elise/arbiter.py", "tools/elise/__init__.py", "tools/voices/judge.py", "tools/voices/names.py",
            "tools/loop/arbiter.py", "tools/loop/ratchet.py", "tools/loop/seal.py"),
    tracked=("data/zones/**/audio.json", "data/elise/state.json", "addon/ForeverSpeech/data/index.lua"),
    oracle=oracle.ask,
    rules=arbiter.RULES,
    critic=critic.review,
)
