"""Loop of the text pass: every zone gets its persona sheets and quest scripts (Claude). READ-ONLY for the
loop (it says what is sealed and what an attempt may change). Architecture: tools/loop/README.md."""

from tools.loop.engine import Pass
from tools.text import arbiter, critic, oracle

PASS = Pass(
    name="text",
    sealed=("tools/text/constitution.md", "tools/text/oracle.py", "tools/text/arbiter.py", "tools/text/__init__.py",
            "tools/loop/arbiter.py", "tools/loop/ratchet.py", "tools/loop/seal.py"),
    tracked=("data/zones.json", "data/voices.json", "data/zones/**/quests.json", "data/zones/**/npcs.json",
             "data/zones/**/scripts.json"),
    oracle=oracle.ask,
    rules=arbiter.RULES,
    critic=critic.review,
)
