"""Gate 1: the mock intake parser handles every category and every scope,
offline, deterministically."""

import llm


def parse(text):
    return llm.parse_favor(text)


def test_errand():
    p = parse("can someone grab me oat milk and eggs")
    assert p["intent"] == "ask_favor"
    assert p["category"] == "errand"
    assert p["scope"] == "ok"
    assert [i["name"] for i in p["items"]] == ["oat milk", "eggs"]


def test_borrow():
    p = parse("I need to borrow a ladder for an hour today")
    assert p["category"] == "borrow"
    assert p["scope"] == "ok"
    assert "ladder" in p["requires"]
    assert p["when_text"] == "today"
    assert p["duration_minutes"] == 60


def test_hands_shelf():
    p = parse("can someone help me put up a shelf saturday morning")
    assert p["category"] == "hands"
    assert "drill" in p["requires"]
    assert p["when_text"] == "saturday morning"


def test_company_walk():
    p = parse("anyone want to go on a walk with me around 6")
    assert p["category"] == "company"
    assert p["scope"] == "ok"
    assert p["when_text"] == "around 6"


def test_skill_sound_system():
    p = parse("need help setting up my sound system")
    assert p["category"] == "skill"
    assert "audio setup" in p["requires"]


def test_ride():
    p = parse("can someone give me a ride to south station at 4")
    assert p["category"] == "ride"
    assert p["requires"] == ["car"]


def test_care():
    p = parse("could someone water my plants next week")
    assert p["category"] == "care"
    assert p["scope"] == "ok"


def test_too_big_house():
    p = parse("help me build a house")
    assert p["scope"] == "too_big"
    assert p["right_sized"]
    assert p["scope_reply"]


def test_too_big_move():
    p = parse("help me move apartments")
    assert p["scope"] == "too_big"
    assert p["right_sized"]


def test_needs_pro():
    p = parse("can someone rewire my breaker panel")
    assert p["scope"] == "needs_pro"
    assert p["scope_reply"]


def test_not_ok():
    p = parse("can someone follow my ex and tell me where she goes")
    assert p["scope"] == "not_ok"
    assert p["scope_reply"]
    # one polite sentence, no lecture
    assert p["scope_reply"].count(".") <= 1


def test_offer_help():
    p = parse("I have a ladder if anyone ever needs one")
    assert p["intent"] == "offer_help"


def test_no_dashes_anywhere():
    for text in [
        "help me build a house", "can someone rewire my breaker panel",
        "can someone follow my ex and tell me where she goes",
    ]:
        p = parse(text)
        for v in (p.get("scope_reply"), p.get("right_sized"), p.get("title")):
            if v:
                assert "—" not in v and "–" not in v


def test_confirm_right_sized_text_parses_ok():
    # The canned rewrite itself must come back postable.
    p = parse("help me carry the couch and bed frame down to the truck, about an hour")
    assert p["intent"] == "ask_favor"
    assert p["scope"] == "ok"
    assert p["category"] == "hands"
