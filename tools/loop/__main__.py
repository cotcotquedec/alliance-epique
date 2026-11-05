"""python -m tools.loop run|check|seal|status|oracle base|text|voices|readings|elise|dialogues|books

    run <pass> (--all | --group G [--category C]...) [--npc N]... [--kind zone|level|companion|quest]
        [--parallel N] [--round N]
        [--max-attempts N] [--reset-ratchet]           the loop (tools/<pass>/run.sh) on every group, or a group, or some
                                    categories of a group (tools/loop/scope.py); --reset-ratchet: the ratchet
                                    starts again from the level at launch; --npc (voices, readings): only these
                                    NPCs (environment FS_NPCS, read by the oracle and the actor); --kind (elise):
                                    only her zone introductions, her level-up lines, her companion lines (D18)
                                    or her quest lines (environment
                                    FS_ELISE_KIND; with --group G, the zone introductions of G are in the scope
                                    unless --category is given); --parallel
                                    (voices, readings): takes generated together on the GPU (environment
                                    FS_TTS_BATCH; default 8 on CUDA, 1 elsewhere: tools/qwen_voices/backend.py);
                                    --round (voices, readings): about N items per attempt, over as many
                                    categories as needed (environment FS_ROUND_TAKES, default 200); books: page
                                    readings per attempt (default 100); --budget (books): characters the run may
                                    spend on ElevenLabs (environment FS_BOOKS_BUDGET; the books are in no group:
                                    --all only)
                                    Follow it: tools/loop/dashboard.sh <pass>
    seal <pass>                     after a human review: seal the read-only objects (tools/<pass>/SEAL)
    status <pass>                   the last attempt (last.json) and where the backlog is
    check <pass> (--all | --group G [--category C]...)
                                    only checks the arguments of a run (tools/<pass>/run.sh, before anything else)
    oracle <pass> [--all | --group G [--category C]...]
                                    the oracle's answer (everything by default); exit 0: goal reached, 1: not yet
"""

from __future__ import annotations

import argparse
import importlib
import json
import os
import sys

from pipeline import storage
from tools.loop import engine, scope, seal
from tools.loop.arbiter import State

PASSES = ("base", "text", "voices", "readings", "elise", "dialogues", "books")


def load(name: str) -> engine.Pass:
    return importlib.import_module(f"tools.{name}").PASS


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(prog="python -m tools.loop", description=__doc__.split("\n")[0])
    ap.add_argument("command", choices=("run", "check", "seal", "status", "oracle"))
    ap.add_argument("name", choices=PASSES, metavar="pass", help="base, text, voices, readings, elise, dialogues or books")
    ap.add_argument("--max-attempts", type=int, default=1000, help="safety limit of run (default 1000)")
    scope.add_arguments(ap)
    ap.add_argument("--npc", action="append", help="run, oracle (voices, readings): only this NPC (repeatable)")
    ap.add_argument("--kind", choices=("zone", "level", "companion", "quest"),
                    help="run, oracle (elise): only her zone introductions, her level-up lines, her companion "
                         "lines or her quest lines")
    ap.add_argument("--parallel", type=int, metavar="N",
                    help="run (voices, readings): takes generated together on the GPU (default: 8 on CUDA, else 1)")
    ap.add_argument("--round", type=int, metavar="N",
                    help="run (voices, readings): about N items per attempt, several categories (default 200)")
    ap.add_argument("--budget", type=int, metavar="N",
                    help="run (books): characters the run may spend on ElevenLabs (default: the account's credits)")
    ap.add_argument("--reset-ratchet", action="store_true",
                    help="run: start the ratchet again from the level at launch (a wanted drop, new counters)")
    args = ap.parse_args(argv)
    try:  # a run always says what it covers; the oracle covers everything by default
        zones = scope.from_args(args, required=args.command in ("run", "check")) \
            if args.command in ("run", "check", "oracle") else None
    except scope.ScopeError as err:
        ap.error(str(err))
    if args.parallel is not None and args.parallel < 1:
        ap.error("--parallel: at least 1")
    if args.round is not None and args.round < 1:
        ap.error("--round: at least 1")
    if args.kind and args.name != "elise":
        ap.error("--kind: the elise pass only")
    if args.budget is not None and (args.name != "books" or args.budget < 1):
        ap.error("--budget: the books pass only, at least 1 character")
    if args.name == "books" and zones is not None:
        ap.error("books: --all only (the books are in no group nor category)")
    if args.name == "elise" and zones is not None and args.group and not args.category:
        from pipeline import zone_intros  # her zone introductions of the group: in no category, but in the group
        zones = [k for k in zone_intros.keys() if k.split("/", 1)[0] == args.group] + zones
    if args.command == "check":
        return
    if args.kind:
        os.environ["FS_ELISE_KIND"] = args.kind  # read by the oracle here and by the actor (child process)
    if args.npc:
        os.environ["FS_NPCS"] = " ".join(args.npc)  # read by the oracle here and by the actor (child process)
    if args.parallel:
        os.environ["FS_TTS_BATCH"] = str(args.parallel)  # read by the actor (child process), backend.batch_size
    if args.round:
        os.environ["FS_ROUND_TAKES"] = str(args.round)  # read by the engine, round_of
    if args.budget:
        os.environ["FS_BOOKS_BUDGET"] = str(args.budget)  # read by the books actor (child process)
    spec = load(args.name)
    if args.command == "seal":
        print(seal.write(storage.REPO_ROOT / spec.seal, list(spec.sealed)), end="")
        print(f"sealed in {spec.seal}: commit it with the files it seals")
        return
    if args.command == "oracle":
        answer = engine.focus(spec.oracle(), zones)
        print(json.dumps(answer, ensure_ascii=False))
        sys.exit(0 if answer["done"] else 1)
    if args.command == "status":
        run_dir = engine.run_dir_of(spec)
        last = storage.read_json(run_dir / "last.json")
        print(json.dumps(last, ensure_ascii=False, indent=1) if last else "no attempt yet")
        print(f"backlog: {run_dir / 'backlog.md'}")
        return
    try:
        label = " ".join((sys.argv[1:] if argv is None else argv)[2:])  # the run's options, for the dashboard
        sys.exit(engine.run(spec, State(max_attempts=args.max_attempts), zones=zones,
                            reset_ratchet=args.reset_ratchet, label=label))
    except KeyboardInterrupt:
        print(f"\n{args.name} loop: interrupted; rerun it to resume (the data files keep the progress)")
        sys.exit(130)


if __name__ == "__main__":
    main()
