from tools.voices import judge, names


def wer(text, heard):
    return names.tolerant_wer(text, heard, judge.words)


def test_names_written_another_way_are_not_misread_words():
    text = "Allez voir le maréchal à Féralas, puis rejoignez Dun Morogh avant la nuit."
    heard = "Allez voir le maréchal à Feralas, puis rejoignez Dunmorog avant la nuit."
    assert judge.word_error_rate(text, heard) > 0.1
    assert wer(text, heard) == 0.0


def test_a_name_heard_as_two_words_and_hyphens():
    assert wer("Les sangliers de Tranchebauge vous attendent.", "Les sangliers de Tranche bauge vous attendent.") == 0
    assert wer("Le clan Hache-Tripes rôde ici.", "Le clan Hachetripes rôde ici.") == 0


def test_ordinary_words_and_far_names_still_count():
    assert wer("Rapportez la tête du chef.", "Rapportez la fête du chef.") == 0.2  # not a name
    assert wer("Parlez à Gnomeregan demain.", "Parlez à notre demain.") > 0  # too far from the name
    assert names.proper_words("Bonjour. Allez à Ironforge.") == {"ironforge"}  # not the sentence's first word
