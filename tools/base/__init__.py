"""Loop of the base pass: the zone registries are built from the Forever Database (no Wowhead, no paid call).
READ-ONLY for the loop (it says what is sealed and what an attempt may change). Architecture: tools/loop/README.md."""

from tools.base import arbiter, critic, oracle
from tools.loop.engine import Pass

PASS = Pass(
    name="base",
    sealed=("tools/base/constitution.md", "tools/base/oracle.py", "tools/base/arbiter.py", "tools/base/__init__.py",
            "tools/loop/arbiter.py", "tools/loop/ratchet.py", "tools/loop/seal.py"),
    tracked=("data/zones.json", "data/zones/**/quests.json", "data/zones/**/npcs.json"),
    oracle=oracle.ask,
    rules=arbiter.RULES,
    critic=critic.review,
)
