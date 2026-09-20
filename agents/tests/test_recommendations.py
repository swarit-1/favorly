"""Graph signals in recommendations.py: pure functions over a FavorGraph, no
database. The cases are the ones that were wrong in live sim testing."""

import recommendations as rec
from recommendations import FavorGraph

ME, NORA, PRIYA, SAM, TOM = "me", "nora", "priya", "sam", "tom"
NAMES = {ME: "Swarit Srivastava", NORA: "Nora Chen", PRIYA: "Priya Raman",
         SAM: "Sam Okonkwo", TOM: "Tom Becker"}


def graph(*edges) -> FavorGraph:
    g = FavorGraph(names=dict(NAMES))
    for src, dst, kind, strength in edges:
        g.add(src, dst, kind, strength)
    return g


# ---------------------------------------------------------------------------
# forward: you helped Y, Y is tied to the asker
# ---------------------------------------------------------------------------


def test_forward_fires_through_someone_you_helped():
    g = graph((ME, NORA, "favor", 0.9), (NORA, PRIYA, "knows", 0.6))
    value, via, reason = rec._forward(g, ME, PRIYA)
    assert via == NORA
    assert value == 0.6  # the weaker leg
    assert reason == "Nora, who you recently helped out, knows Priya"


def test_forward_needs_the_favor_to_be_yours():
    # Nora helped ME. That is reciprocity with Nora, not a reason to help Priya.
    g = graph((NORA, ME, "favor", 0.9), (NORA, PRIYA, "knows", 0.6))
    assert rec._forward(g, ME, PRIYA) == (0.0, None, None)


def test_forward_is_not_reciprocity_with_the_asker():
    # A favor done for the asker herself is not a path *through* anyone.
    g = graph((ME, PRIYA, "favor", 0.9))
    assert rec._forward(g, ME, PRIYA) == (0.0, None, None)


def test_forward_prefers_the_closer_middle_person():
    g = graph(
        (ME, NORA, "favor", 0.9), (NORA, PRIYA, "neighbor", 0.25),
        (ME, SAM, "favor", 0.8), (SAM, PRIYA, "favor", 0.7),
    )
    value, via, reason = rec._forward(g, ME, PRIYA)
    assert (value, via) == (0.7, SAM)
    assert reason == "Sam, who you recently helped out, has traded favors with Priya"


def test_forward_scales_with_the_weaker_tie():
    hallway = graph((ME, NORA, "favor", 1.0), (NORA, PRIYA, "neighbor", 0.25))
    friend = graph((ME, NORA, "favor", 1.0), (NORA, PRIYA, "knows", 0.6))
    assert rec._forward(hallway, ME, PRIYA)[0] < rec._forward(friend, ME, PRIYA)[0]
    assert rec._forward(hallway, ME, PRIYA)[2] == (
        "Nora, who you recently helped out, lives on Priya's floor"
    )


def test_forward_quotes_what_you_did_when_it_is_known():
    g = graph((ME, NORA, "favor", 0.9), (NORA, PRIYA, "knows", 0.6))
    g.favor_titles[(ME, NORA)] = "Borrow a ladder"
    assert rec._forward(g, ME, PRIYA)[2] == "Nora, who you helped to borrow a ladder, knows Priya"


def test_forward_does_not_quote_a_first_person_title():
    g = graph((ME, NORA, "favor", 0.9), (NORA, PRIYA, "knows", 0.6))
    g.favor_titles[(ME, NORA)] = "Help me untangle my bike chain"
    assert rec._forward(g, ME, PRIYA)[2] == "Nora, who you recently helped out, knows Priya"


# ---------------------------------------------------------------------------
# mutual: weighted by the edge, not by a head count
# ---------------------------------------------------------------------------


def test_mutuals_are_weighted_by_the_weaker_leg_and_sorted():
    g = graph(
        (ME, TOM, "neighbor", 0.25), (TOM, PRIYA, "neighbor", 0.25),
        (ME, NORA, "favor", 0.9), (PRIYA, NORA, "knows", 0.6),
    )
    assert rec._mutuals(g, ME, PRIYA) == [(NORA, 0.6), (TOM, 0.25)]


def test_a_shared_hallway_is_worth_less_than_a_shared_friend():
    hallway = graph((ME, TOM, "neighbor", 0.25), (TOM, PRIYA, "neighbor", 0.25))
    friend = graph((ME, NORA, "favor", 0.9), (NORA, PRIYA, "favor", 0.9))
    score = lambda g: min(sum(s for _, s in rec._mutuals(g, ME, PRIYA)), 1.0)
    assert score(hallway) == 0.25
    assert score(friend) == 0.9


def test_mutuals_exclude_the_two_of_you():
    g = graph((ME, PRIYA, "favor", 1.0))
    assert rec._mutuals(g, ME, PRIYA) == []


def test_reciprocity_keeps_direction():
    g = graph((NORA, ME, "favor", 0.8), (NORA, ME, "favor", 0.5))
    assert rec._reciprocity(g, ME, NORA) == (1.0, 2)   # she helped me, twice, capped
    assert rec._reciprocity(g, NORA, ME) == (0.0, 0)   # I never helped her


# ---------------------------------------------------------------------------
# copy
# ---------------------------------------------------------------------------


def _detail(**over):
    base = {
        "favor_count": 0, "mutual_names": [], "forward_reason": None,
        "forward_via_name": None, "fit_reason": None, "affinity_reason": None,
        "trip_reason": None, "capability_reason": None,
        "ask": "milk and eggs this week", "title": "Grab milk and eggs",
        "category": "errand", "age": "2h ago",
    }
    return {**base, **over}


def _parts(**over):
    return {**{k: 0.0 for k in rec.WEIGHTS}, **over}


def test_weights_sum_to_one():
    assert abs(sum(rec.WEIGHTS.values()) - 1.0) < 1e-9


def test_reason_leads_with_the_forward_path_and_does_not_repeat_the_middle_person():
    detail = _detail(
        forward_reason="Nora, who you recently helped out, knows Priya",
        forward_via_name="Nora Chen", mutual_names=["Nora Chen"],
        ask="anyone up for the reservoir loop", title="Walk the reservoir loop",
        category="company",
    )
    reason = rec._build_reason("Priya Raman", _parts(forward=0.6, mutual=0.6), detail)
    assert reason == (
        "Nora, who you recently helped out, knows Priya. "
        "Priya is hoping for a hand: walk the reservoir loop."
    )
    assert "both know" not in reason


def test_a_non_errand_is_not_described_as_something_to_pick_up():
    c = {
        "needer_name": "Priya Raman", "title": "Walk the reservoir loop",
        "category": "company", "ask": "anyone up for the reservoir loop with me…",
        "detail": _detail(),
    }
    assert rec._fallback_action(c, "Priya") == "Walk the reservoir loop with Priya"
    c.update(title="Help me untangle my bike chain", category="other")
    assert rec._fallback_action(c, "Swarit") == "Give Swarit a hand"
    c.update(title="Grab milk and eggs", category="errand", ask="milk and eggs")
    assert rec._fallback_action(c, "Grace") == "Pick up milk and eggs for Grace"


def test_true_facts_carry_every_signal_that_fired_and_nothing_about_a_trip_that_did_not():
    c = {
        "needer_name": "Lina Haddad",
        "detail": _detail(
            capability_reason="you have what they need: handy",
            forward_reason="Marcus, who you recently helped out, lives on Lina's floor",
            forward_via_name="Marcus Hill", mutual_names=["Marcus Hill", "Nora Chen"],
            category="hands",
        ),
    }
    facts = rec._true_facts(c)
    assert "you have what they need: handy" in facts
    assert "Marcus, who you recently helped out, lives on Lina's floor" in facts
    assert "you and Lina both know Nora" in facts  # Marcus is not said twice
    assert not any("going to" in f for f in facts)


def test_validator_accepts_a_possessive_of_a_name_it_was_given():
    allowed = "Swarit Srivastava can someone help me untangle my bike chain"
    assert rec.validate_reason("Untangle Swarit's bike chain", allowed)
    assert rec.validate_reason("Stop by to untangle Swarit's bike chain.", allowed)
    # ...but a possessive is not a free pass for a name that was never given.
    assert not rec.validate_reason("Untangle Marco's bike chain", allowed)
    # A name that owns its apostrophe still has to appear as written.
    assert rec.validate_reason("Going to Trader Joe's.", "you're going to Trader Joe's today")


def test_validator_accepts_a_forward_fact_and_rejects_an_invented_store():
    fact = "Nora, who you recently helped out, knows Priya"
    allowed = f"Priya Raman anyone up for the reservoir loop {fact}"
    assert rec.validate_reason("You recently helped Nora, and Nora knows Priya.", allowed)
    assert not rec.validate_reason("You're already going to Trader Joe's today.", allowed)
