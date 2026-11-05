import json

from pipeline.wowhead.parse import listview, parse_quest_menu, placeholders

MENU = 'WH.setPageData("menu.def.quests", ' + json.dumps([
    ["continents", "Continents", None, None, {"heading": True}],
    ["0", "Royaumes de l'Est", "/forever/fr/quests/eastern-kingdoms", [
        ["12", "Forêt\xa0d'Elwynn", "/forever/fr/quests/eastern-kingdoms/elwynn-forest"]]],
    ["-2", "Non classés", "/forever/fr/quests/uncategorized"],
]) + ");"


def test_category_listview():
    page = "<script>new Listview({template: 'quest', id: 'quests', data: " \
           + json.dumps([{"id": 783, "level": 1}, {"id": 33, "level": 2}]) + "});</script>"
    assert [row["id"] for row in listview(page, "quests")] == [783, 33]
    assert listview(page, "npcs") == [] and listview("<html></html>", "quests") == []


def test_quest_menu():
    zones = parse_quest_menu(MENU)
    assert zones == [
        {"id": 12, "name": "Forêt d'Elwynn", "group_name": "Royaumes de l'Est",
         "path": "/forever/fr/quests/eastern-kingdoms/elwynn-forest"},
        {"id": -2, "name": "Non classés", "group_name": "Non classés", "path": "/forever/fr/quests/uncategorized"}]
    assert parse_quest_menu("<html></html>") == []


def test_placeholders():
    assert placeholders("Bonjour <nom>, jeune <costaud/costaude>.") == ["nom", "costaud/costaude"]
    assert placeholders(None) == []
