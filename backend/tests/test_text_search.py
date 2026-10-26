"""Ranking rules behind the Explore search (app/core/text_search.py)."""

from app.core.text_search import relevant


def test_a_lone_weak_match_is_not_shown():
    # The only post sharing anything with 「學生證」 just says 學生 once in its body.
    posts = [("prayer-room", "is there a muslim prayer room", "我是穆斯林學生，想找祈禱室")]
    assert relevant(posts, "學生證", 10) == []
    assert relevant(posts, "學生證不見了", 10) == []


def test_a_title_match_or_most_of_the_words_is_enough():
    posts = [
        ("card", "補發學生證", ""),
        ("muslim", "", "is there a muslim prayer room on campus"),
    ]
    assert relevant(posts, "學生證不見了", 10) == ["card"]
    assert relevant(posts, "muslim", 10) == ["muslim"]


def test_weaker_results_are_cut_relative_to_the_best():
    guides = [
        ("about", "申請在學證明", "到教務處申請在學證明"),
        ("mentions", "申請工作證", "準備學生證 申請在學證明"),
    ]
    assert relevant(guides, "申請在學證明", 10) == ["about"]
