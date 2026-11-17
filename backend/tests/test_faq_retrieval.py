"""Retrieval test set for the official Q&A: typical student questions and the official
questions that must come back in the top three. It runs the keyword half of the assistant's
search (no Gemini in CI), so a change to ranking, stemming or the labels that pushes a right
answer out shows up here. Questions keywords can't answer yet (「健保什麼時候可以加保」) rely on
the semantic half in production and are not listed.
"""

import pytest

from app.assistant.data import DemoDataSource
from app.core.config import get_settings

CASES = [
    ("居留證逾期怎麼辦", {"nisa-934", "nisa-1076"}),
    ("居留證要怎麼延期", {"nisa-1077", "nisa-974", "nisa-1076"}),
    ("外國學生實習需要工作證嗎", {"nisa-1025"}),
    ("打工一週可以工作幾小時", {"nisa-1095", "nisa-1096"}),
    ("駕照需要更新嗎", {"nisa-923"}),
    ("創業需要工作證嗎", {"nisa-925"}),
    ("休學後居留證怎麼辦", {"nisa-1080", "nisa-1044"}),
    ("報稅", {"nisa-994", "nisa-995"}),
    ("永久居留需要什麼條件", {"nisa-1049", "nisa-1046", "nisa-1101"}),
    ("港澳生可以申請什麼獎學金", {"nisa-906"}),
    ("How long is a work permit valid?", {"nisa-985"}),
    ("How long can I stay after graduation to look for a job?", {"nisa-938", "nisa-1046"}),
    ("driving license renew", {"nisa-923"}),
    ("scholarship for overseas Chinese students", {"nisa-1058", "nisa-906"}),
]


@pytest.fixture(scope="module")
def data() -> DemoDataSource:
    return DemoDataSource.from_file(get_settings().demo_content_path)


@pytest.mark.parametrize(("question", "expected"), CASES)
def test_a_right_answer_is_in_the_top_three(data, question, expected):
    found = [f.id for f in data.search_faqs(question, 3)]
    assert expected & set(found), f"{question}: got {found}"


def test_overall_hit_rate_stays_high(data):
    hits = sum(bool(e & {f.id for f in data.search_faqs(q, 3)}) for q, e in CASES)
    assert hits == len(CASES)


def test_school_and_outdated_questions_never_outrank_student_ones(data):
    for question, _ in CASES:
        found = data.search_faqs(question, 8)
        flags = [f.demoted for f in found]
        assert flags == sorted(flags), f"{question}: {[(f.id, f.demoted) for f in found]}"


def test_a_question_with_no_official_answer_finds_nothing(data):
    assert data.search_faqs("兵役", 3) == []
