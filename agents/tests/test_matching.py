"""Gate 2: the ranking signals are pure functions -- test them as such."""

from datetime import datetime, timezone

import networkx as nx

import llm
import matching
import seed_data
from matching import CircleContext, Person


def person(pid, name, floor=None, unit=None, availability=None, joined_days=90.0):
    return Person(
        id=pid, display_name=name, first_name=name.split()[0],
        floor=floor, unit=unit, availability=availability or [], joined_days=joined_days,
    )


def claim(kind, label):
    return {"kind": kind, "canonical": label, "raw_label": label, "confidence": 0.8}


NOW = datetime(2026, 9, 19, 13, 30, tzinfo=timezone.utc)


# -- capability ---------------------------------------------------------------

def test_capability_direct_item_match():
    v, headline = matching.capability("borrow", ["ladder"], [claim("has_item", "6 ft ladder")])
    assert v == 1.0
    assert headline == "Has a 6 ft ladder"


def test_capability_synonym():
    v, _ = matching.capability("borrow", ["drill"], [claim("has_item", "toolbox")])
    assert v == 0.7


def test_capability_no_match_borrow():
    v, _ = matching.capability("borrow", ["ladder"], [claim("interest", "chess")])
    assert v == 0.0


def test_capability_company_activity():
    v, _ = matching.capability("company", ["walking"], [claim("interest", "walking")])
    assert v == 1.0


def test_capability_company_shared_interest_fallback():
    v, _ = matching.capability(
        "company", [], [claim("interest", "chess")],
        asker_claims=[claim("interest", "chess")],
    )
    assert v == 0.5


def test_capability_ride_car():
    v, headline = matching.capability("ride", ["car"], [claim("mobility", "has car access")])
    assert v == 1.0


def test_capability_hands_handy():
    v, _ = matching.capability("hands", ["handy"], [claim("skill", "handy with tools")])
    assert v == 1.0
    v2, _ = matching.capability("hands", [], [claim("skill", "handy with tools")])
    assert v2 == 0.6
    v3, _ = matching.capability("hands", [], [])
    assert v3 == 0.3


# -- tie ----------------------------------------------------------------------

def _graph():
    g = nx.Graph()
    for pair, s in ((("a", "n"), 1.0), (("n", "m"), 0.9), (("m", "x"), 0.5)):
        g.add_edge(*pair, strength=s, favors={})
    g.add_node("z")
    return g


PEOPLE = {
    "a": person("a", "Asker Person", 3),
    "n": person("n", "Nora Chen", 4),
    "m": person("m", "Marcus Hill", 6),
    "x": person("x", "Xen Far", 7),
    "z": person("z", "Jordan Reyes", 2, joined_days=5.0),
}


def test_tie_one_hop():
    v, cls, label, hops, _ = matching.tie_signal(_graph(), "a", "n", PEOPLE)
    assert (v, cls, hops) == (1.0, "close", 1)
    assert label == "You know each other"


def test_tie_two_hops_names_mutual():
    v, cls, label, hops, path = matching.tie_signal(_graph(), "a", "m", PEOPLE)
    assert (v, cls, hops) == (0.85, "friend_of_friend", 2)
    assert label == "Friend of Nora"
    assert path == ["a", "n", "m"]


def test_tie_three_hops():
    v, cls, label, hops, _ = matching.tie_signal(_graph(), "a", "x", PEOPLE)
    assert (v, cls) == (0.55, "extended")


def test_tie_no_path_new_to_building():
    v, cls, label, hops, _ = matching.tie_signal(_graph(), "a", "z", PEOPLE)
    assert (v, cls, hops) == (0.15, "new", None)
    assert label == "New to the building"  # joined < 30 days


# -- similarity / reciprocity / nearness / availability -----------------------

def test_similarity_counts():
    a = [claim("interest", "formula 1"), claim("interest", "chess")]
    assert matching.similarity(a, [claim("interest", "formula 1")]) == (0.5, ["formula 1"])
    both = [claim("interest", "formula 1"), claim("interest", "chess")]
    v, shared = matching.similarity(a, both)
    assert v == 1.0 and set(shared) == {"formula 1", "chess"}
    assert matching.similarity(a, [claim("has_item", "ladder")])[0] == 0.0


def test_nearness():
    assert matching.nearness(3, 3) == (1.0, "same floor")
    assert matching.nearness(3, 4) == (0.8, "1 floor up")
    assert matching.nearness(3, 6) == (0.6, "3 floors up")
    assert matching.nearness(3, 2) == (0.8, "1 floor down")
    assert matching.nearness(3, 7)[0] == 0.4
    assert matching.nearness(None, 4) == (0.3, "in the building")
    # never a unit number
    assert "C" not in matching.nearness(3, 6)[1]


def test_availability():
    sat = datetime(2026, 9, 19, 13, 30, tzinfo=timezone.utc)  # a Saturday
    assert matching.availability_signal(["Sat", "Sun"], [], "today", sat) == 1.0
    assert matching.availability_signal(["Mon", "Tue", "Wed", "Thu", "Fri"], [], "today", sat) == 0.2
    assert matching.availability_signal([], [], "today", sat) == 0.5
    assert matching.availability_signal(["every day"], [], "saturday", sat) == 1.0
    assert matching.availability_signal([], [claim("availability", "free weekends")], "saturday", sat) == 1.0


def test_balance_factor():
    assert matching.balance_factor(0.0, 0.0) == 1.0
    assert matching.balance_factor(3.0, 0.0) == 0.4  # far above median -> rested


# -- ranking ------------------------------------------------------------------

def _ctx():
    g = _graph()
    return CircleContext(
        asker_id="a",
        people=dict(PEOPLE),
        claims={
            "a": [claim("interest", "formula 1")],
            "n": [claim("has_item", "step ladder")],
            "m": [claim("has_item", "6 ft ladder"), claim("interest", "formula 1")],
            "x": [claim("has_item", "ladder")],
            "z": [claim("has_item", "ladder")],
        },
        G=g,
        give_balance={pid: 0.0 for pid in PEOPLE},
        busy=set(),
    )


def test_rank_borrow_excludes_no_capability_and_busy():
    ctx = _ctx()
    ctx.claims["n"] = [claim("interest", "chess")]  # Nora has no ladder now
    ctx.busy.add("x")
    top = matching.rank_helpers(ctx, {"category": "borrow", "requires": ["ladder"]}, NOW)
    ids = [c["person_id"] for c in top]
    assert "n" not in ids  # hard filter: nothing to lend
    assert "x" not in ids  # busy
    assert "a" not in ids  # never the asker


def test_rank_signals_never_expose_balance_evidence():
    ctx = _ctx()
    top = matching.rank_helpers(ctx, {"category": "borrow", "requires": ["ladder"]}, NOW)
    for c in top:
        assert "balance" in c["signals"]  # value is fine
        reason = matching.template_reason(c)
        assert "balance" not in reason.lower()
        assert "score" not in reason.lower()


def test_rank_diversity_rule():
    ctx = _ctx()
    top = matching.rank_helpers(ctx, {"category": "borrow", "requires": ["ladder"]}, NOW, limit=3)
    assert len({c["tie"] for c in top}) >= 2


def test_no_dashes_in_template_reasons():
    ctx = _ctx()
    top = matching.rank_helpers(ctx, {"category": "borrow", "requires": ["ladder"]}, NOW)
    for c in top:
        r = matching.template_reason(c)
        assert "—" not in r and "–" not in r


# -- seed invariant (A.3): every block seed message yields its claims --------

EXPECTED_SEED_CLAIMS = {
    "I have a 6 ft ladder and a drill if anyone ever needs them": {"ladder", "drill"},
    "pretty handy with tools, I built most of my own furniture": {"handy with tools"},
    "usually free Sunday afternoons": {"free weekends"},
    "I have a small step ladder for my plants": {"ladder"},
    "just moved in, I still have a ladder and a hand truck from the move": {"ladder", "hand truck"},
    "I have a car and I'm at the store constantly, happy to grab things": {"has car access"},
    "I have a full toolbox": {"tools"},
    "happy to help move furniture, I'm pretty strong": {"moving help"},
    "I walk my dog around the reservoir every evening": {"walking", "dog owner"},
    "I set up the sound system for my band": {"audio setup"},
    "I can sew and hem just about anything": {"sewing"},
    "money is tight this month so I'm sticking to a list": {"budget conscious"},
    "I fix bikes for fun": {"bike repair"},
    "retired carpenter, forty years on the job": {"handy with tools"},
    "I have every tool you can think of": {"tools"},
    "I'm around most days": {"free afternoons"},
    "I have a projector and do movie nights": {"projector"},
    "happy to help with speakers and TVs": {"audio setup"},
    "I have a bike pump and a small toolkit": {"bike pump", "tools"},
    "I have a stand mixer and bake on Sundays": {"stand mixer", "baking"},
    "I do audio engineering, happy to help with speakers": {"audio setup"},
    "I have a folding table and extra chairs": {"folding table"},
    "big F1 fan, I never miss a race weekend": {"formula 1"},
    "I play chess most evenings": {"chess"},
    "I work from home": {"works from home"},
    "I climb at the gym twice a week": {"climbing"},
    "looking for people to run with": {"running"},
}


def test_every_block_seed_message_yields_its_claims():
    all_seeded = [m for msgs in seed_data.BLOCK_MESSAGES.values() for m in msgs]
    for body, expected in EXPECTED_SEED_CLAIMS.items():
        assert body in all_seeded, f"seed message drifted: {body}"
        got = {c["label"] for c in llm._extract_claims_mock(body)}
        assert expected <= got, f"{body!r}: expected {expected}, got {got}"


def test_every_block_message_produces_at_least_one_claim():
    for name, msgs in seed_data.BLOCK_MESSAGES.items():
        for body in msgs:
            claims = llm._extract_claims_mock(body)
            assert claims, f"{name}: {body!r} produced no mock claims"
