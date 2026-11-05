local wow = require("tests.lua.helpers.wow")

-- The vectors of the index contract v9 (fs_norm, fs_key, fs_fp): the Python side (pipeline) must give the same bytes.
describe("text normalisation shared with the pipeline", function()
  local Text
  before_each(function()
    wow.reset()
    wow.loadAddon()
    Text = ForeverSpeech.Text
  end)

  local VECTORS = {
    -- input, tokens
    { "Bonjour, $N ! Vous êtes $gun brave:une brave; $C.", { "bonjour", "vous", "êtes" } },
    { "Prenez-en soin, $Gmon frère:ma sœur;.", { "prenez", "en", "soin" } },
    { "$n $c $r $R $N $C", {} },
    { "Ligne un$BLigne deux$bfin |cff00ff00Vert|r|nEnd", { "ligne", "un", "ligne", "deux", "fin", "vert", "end" } },
    { "L’Œil de « Dalaran »… — fin – suite", { "l", "Œil", "de", "dalaran", "fin", "suite" } },
    { "Attention\194\160: danger\226\128\175!", { "attention", "danger" } },
    { "\195\137COLE d'\195\137t\195\169", { "\195\137cole", "d", "\195\137t\195\169" } }, -- ÉCOLE d'Été: É kept
    { "a\tb\nc\r\nd  e", { "a", "b", "c", "d", "e" } },
    { "x!\"#%&'()*+,-./:;<=>?@[\\]^_`{|}~y", { "x", "y" } },
    { "Salut, $R ! La nuit tombe.", { "salut", "la", "nuit", "tombe" } },
  }

  it("gives the contract's tokens", function()
    for _, v in ipairs(VECTORS) do
      assert.same(v[2], Text.Tokens(v[1]))
    end
  end)

  it("joins them with spaces (words) or with nothing (key)", function()
    assert.equals("bonjour vous êtes", Text.Words(VECTORS[1][1]))
    assert.equals("bonjourvousêtes", Text.Key(VECTORS[1][1]))
    assert.equals("lelivredetirion", Text.Key("Le Livre de Tirion"))
    assert.equals("", Text.Key(nil))
  end)

  it("cuts the fingerprint at 48 bytes, on a UTF-8 character boundary", function()
    assert.equals("ilétaitunefoisunpaladinnommétirionfordringquiv",
      Text.Fp("Il était une fois un paladin nommé Tirion Fordring, qui vivait près de Hearthglen."))
    assert.equals("unautrelivreportecetitremaissonhistoireestdiffé",
      Text.Fp("Un autre livre porte ce titre, mais son histoire est différente."))
    local a47, a48 = string.rep("a", 47), string.rep("a", 48)
    assert.equals(a47, Text.Fp(a47 .. "é")) -- é would be cut in two: left out
    assert.equals(a48, Text.Fp(a48 .. "é"))
    assert.equals(string.rep("a", 46) .. "é", Text.Fp(string.rep("a", 46) .. "éz")) -- é ends at byte 48: kept
    assert.equals("court", Text.Fp("Court."))
  end)
end)
