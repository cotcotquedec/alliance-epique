"""The index v9 text normalisation (pipeline/match.py): the addon computes the same tokens in Lua 5.1."""

from pipeline.match import (MAX_WORDS, fs_fp, fs_key, fs_norm, from_markup, match_page, player_phrases, score,
                            without, words)


def test_ascii_letters_only_are_lowercased_and_accents_stay():
    assert fs_norm("Élune soit avec VOUS") == ["Élune", "soit", "avec", "vous"]
    assert fs_norm("ÇA va À l'Est") == ["Ça", "va", "À", "l", "est"]


def test_french_typography_and_punctuation_separate_tokens():
    text = "« Bienvenue », dit-il : l’auberge est… ouverte – enfin — !"
    assert fs_norm(text) == ["bienvenue", "dit", "il", "l", "auberge", "est", "ouverte", "enfin"]


def test_variables_line_breaks_and_colours_are_dropped():
    assert fs_norm("Salut, $N.$BVous êtes $gprêt:prête; ?$b|cff00ff00Vert|r|nfin") == \
        ["salut", "vous", "êtes", "vert", "fin"]
    assert fs_norm("Elune soit avec vous, $c. $R et $C, $Gil:elle; part.") == \
        ["elune", "soit", "avec", "vous", "et", "part"]
    assert fs_norm(None) == [] and fs_norm("") == []


def test_key_and_fingerprint_cut_at_a_character_boundary():
    assert fs_key("Au-delà de la Porte des ténèbres") == "audelàdelaportedesténèbres"
    fp = fs_fp("é" * 30)  # 60 bytes: 48 bytes = 24 characters exactly
    assert fp == "é" * 24 and len(fp.encode()) == 48
    fp = fs_fp("a" + "é" * 30)  # 47 + a split character: cut back to 47 bytes
    assert fp == "a" + "é" * 23 and len(fp.encode()) == 47


def test_markup_gives_the_same_tokens_as_the_database_text():
    raw = "Bien le bonjour, $N. Je pense que vous serez $gintéressé:intéressée; par les résultats.$B$BMerci, $C."
    markup = ("Bien le bonjour, <nom>. Je pense que vous serez <intéressé/intéressée> par les résultats.\n\n"
              "Merci, <classe>.")
    assert from_markup(markup).count("$") == 3
    assert fs_norm(from_markup(markup)) == fs_norm(raw)


def test_words_keep_the_first_tokens():
    assert words("Un deux trois", limit=2) == "un deux"
    assert len(words(" ".join(["mot"] * 60)).split()) == MAX_WORDS


def test_matching_exact_fuzzy_and_none():
    pages = [{"words": words("Bonjour, $N ! Que puis-je pour vous ?")},
             {"words": words("Les vents du nord soufflent fort sur Darnassus ce soir.")}]
    drop = player_phrases("Aliena", "Prêtresse", "Elfe de la nuit")
    assert match_page("Bonjour, Aliena ! Que puis-je pour vous ?", pages, drop) == (0, 1.0, True)
    index, s, exact = match_page("Les vents du nord soufflent sur Darnassus.", pages, drop)
    assert index == 1 and not exact and s >= 0.7
    assert match_page("Tout autre chose.", pages, drop)[0] is None
    assert score([], ["a"]) == 0.0


def test_the_player_words_leave_as_whole_phrases():
    phrases = player_phrases("Elfe de la nuit", "Chasseur")
    assert without(fs_norm("La paix de la forêt, elfe de la nuit chasseur !"), phrases) == \
        ["la", "paix", "de", "la", "forêt"]


def test_a_long_page_matches_exactly_on_its_first_tokens():
    text = " ".join(f"mot{i}" for i in range(60))
    pages = [{"words": words(text)}]
    assert match_page(text, pages) == (0, 1.0, True)


def test_same_tokens_as_the_addon_lua(tmp_path):
    """The addon's Lua side (core/text.lua) gives the same keys, fingerprints and words, byte for byte."""
    import json
    import subprocess

    import pytest

    from pipeline import captures, storage
    text_lua = storage.REPO_ROOT / "addon" / "ForeverSpeech" / "core" / "text.lua"
    try:
        lua = captures.lua()
    except SystemExit:
        pytest.skip("no Lua 5.1 interpreter")
    if not text_lua.exists():
        pytest.skip("no core/text.lua")
    samples = ["Élune soit avec VOUS, $c.", "« Bienvenue », dit-il : l’auberge est… ouverte – enfin — !",
               "Salut, $N.$BVous êtes $gprêt:prête; ?$b|cff00ff00Vert|r|nfin", "a" + "é" * 30, "é" * 30,
               '<HTML><BODY><H1 align="center">Chronique</H1><BR/><P>Cher $N</P></BODY></HTML>', "", "Ça\tva\r\n"]
    for path in sorted((storage.ZONES_DIR / "@books").glob("books.json"))[:1]:
        samples += [p["text"] for b in json.loads(path.read_text())["books"].values() for p in b["pages"]][:300]
    (tmp_path / "in.bin").write_bytes(b"\0".join(s.encode("utf-8") for s in samples))
    script = (f"ForeverSpeech = {{}}; dofile({str(text_lua)!r}); local f = io.open({str(tmp_path / 'in.bin')!r}, 'rb'); "
              "local all = f:read('*a') .. '\\0'; f:close(); local out = {}; "
              "for s in all:gmatch('([^%z]*)%z') do local T = ForeverSpeech.Text; "
              "out[#out + 1] = T.Key(s) .. '\\1' .. T.Fp(s) .. '\\1' .. T.Words(s) end; "
              "io.write(table.concat(out, '\\0'))")
    got = subprocess.run([lua, "-e", script], capture_output=True, check=True).stdout.decode("utf-8").split("\0")
    assert len(got) == len(samples)
    for text, line in zip(samples, got):
        assert line.split("\1") == [fs_key(text), fs_fp(text), words(text, None)], text
