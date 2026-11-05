import pytest

from tools.loop import scope


@pytest.fixture
def zones(tmp_path):
    for key in ("eastern-kingdoms/elwynn-forest", "eastern-kingdoms/westfall", "battlegrounds/alterac-valley",
                "eastern-kingdoms/alterac-valley", "classes/warrior", "uncategorized"):
        (tmp_path / key).mkdir(parents=True)
        (tmp_path / key / "quests.json").write_text("{}")
    return tmp_path


def resolve(zones, all_=False, group=None, categories=None):
    return scope.resolve(all_, group, categories, zones)


def test_groups_hold_their_categories(zones):
    assert scope.groups(zones) == {
        "battlegrounds": ["battlegrounds/alterac-valley"], "classes": ["classes/warrior"],
        "eastern-kingdoms": ["eastern-kingdoms/alterac-valley", "eastern-kingdoms/elwynn-forest",
                             "eastern-kingdoms/westfall"],
        "uncategorized": ["uncategorized"]}


def test_all_a_group_or_categories_of_a_group(zones):
    assert resolve(zones, all_=True) is None
    assert resolve(zones, group="classes") == ["classes/warrior"]
    assert resolve(zones, group="uncategorized") == ["uncategorized"]
    assert resolve(zones, group="eastern-kingdoms", categories=["elwynn-forest", "eastern-kingdoms/westfall"]) == [
        "eastern-kingdoms/elwynn-forest", "eastern-kingdoms/westfall"]
    # the same category name in two groups: the group says which one
    assert resolve(zones, group="battlegrounds", categories=["alterac-valley"]) == ["battlegrounds/alterac-valley"]


@pytest.mark.parametrize("kwargs, message", [
    ({}, "give --all, or --group"),
    ({"categories": ["elwynn-forest"]}, "always given with its --group"),
    ({"all_": True, "group": "classes"}, "no --group or --category with it"),
    ({"group": "kalimdor"}, "unknown group 'kalimdor'"),
    ({"group": "classes", "categories": ["elwynn-forest"]}, "no category 'elwynn-forest' in group 'classes'"),
    ({"group": "classes", "categories": ["eastern-kingdoms/westfall"]}, "no category"),
])
def test_scope_errors(zones, kwargs, message):
    with pytest.raises(scope.ScopeError, match=message):
        resolve(zones, **kwargs)


def test_the_loop_cli_needs_a_scope_to_run(capsys):
    from tools.loop import __main__ as cli
    with pytest.raises(SystemExit) as stop:
        cli.main(["run", "voices"])
    assert stop.value.code == 2 and "give --all, or --group" in capsys.readouterr().err


def test_the_oracle_covers_everything_without_a_scope():
    import argparse
    args = argparse.Namespace(all_groups=False, group=None, category=None)
    assert scope.from_args(args, required=False) is None
    with pytest.raises(scope.ScopeError):
        scope.from_args(args)
