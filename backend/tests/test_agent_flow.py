"""End-to-end agent flow with the rule-based parser (no network, no keys)."""

from datetime import datetime

import pytest

from agent.handlers import handle_message
from agent.nlu import parse_rules
from agent.store import AgentStore
from matching import assign_section, MATCH_THRESHOLD, rank_trips_for_ask
from shared.contracts.models import StoreSection

NOW = datetime(2026, 9, 19, 13, 30)  # 1:30 pm

ALICE = "+15550000001"
BOB = "+15550000002"


@pytest.fixture()
def store(monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    return AgentStore()


# -- matching -----------------------------------------------------------------

def test_section_assignment():
    assert assign_section("oat milk") == StoreSection.DAIRY
    assert assign_section("2 ripe bananas") == StoreSection.PRODUCE
    assert assign_section("paper towels") == StoreSection.HOUSEHOLD
    assert assign_section("mystery gadget") == StoreSection.OTHER


def test_pharmacy_trip_scores_low_for_groceries(store):
    profile = store.user_for_phone(ALICE)
    trip = store.create_trip(profile.user.id, "CVS", NOW.replace(hour=14))
    ranked = rank_trips_for_ask(
        [StoreSection.DAIRY, StoreSection.PRODUCE], [(trip, 0)], NOW
    )
    grocery = store.create_trip(profile.user.id, "Trader Joe's", NOW.replace(hour=14))
    ranked_grocery = rank_trips_for_ask(
        [StoreSection.DAIRY, StoreSection.PRODUCE], [(grocery, 0)], NOW
    )
    assert ranked_grocery and ranked_grocery[0][1] >= MATCH_THRESHOLD
    grocery_score = ranked_grocery[0][1]
    cvs_score = ranked[0][1] if ranked else 0
    assert grocery_score > cvs_score


# -- NLU rules ----------------------------------------------------------------

def test_parse_ask():
    p = parse_rules("Can someone grab me oat milk and 2 avocados?", NOW)
    assert p.intent == "ask_favor"
    names = {i["name"] for i in p.items}
    assert names == {"oat milk", "avocados"}
    assert {i["qty"] for i in p.items} == {1, 2}


def test_parse_trip_with_time():
    p = parse_rules("I'm heading to Trader Joe's at 3", NOW)
    assert p.intent == "offer_trip"
    assert p.store == "Trader Joe's"
    assert p.depart_minutes_from_now == 90  # 1:30pm -> 3:00pm


def test_parse_recommendations():
    assert parse_rules("What should I pick up for people?", NOW).intent == "get_recommendations"


# -- full conversation ----------------------------------------------------------

def test_ask_then_trip_matches_and_notifies(store):
    # Bob asks before any trip exists -> pending ask
    reply, notes = handle_message(store, BOB, "can someone grab me oat milk and eggs", NOW)
    assert "posted your ask" in reply
    assert len(store.pending_asks()) == 1

    # Alice offers a trip -> pending ask auto-attaches, Bob gets notified
    reply, notes = handle_message(store, ALICE, "I'm going to Trader Joe's at 3", NOW)
    assert "matched these favors" in reply
    assert store.pending_asks() == []
    assert len(notes) == 1 and notes[0][0] == BOB

    # Alice asks for her list -> sees Bob's items with sections
    reply, _ = handle_message(store, ALICE, "what should I pick up?", NOW)
    assert "oat milk" in reply and "dairy" in reply


def test_ask_matches_existing_trip(store):
    handle_message(store, ALICE, "making a Star Market run in 20 min", NOW)
    reply, notes = handle_message(store, BOB, "can someone pick up bananas and bread", NOW)
    assert "Star Market" in reply
    assert len(notes) == 1 and notes[0][0] == ALICE  # shopper notified


def test_set_name_and_status(store):
    handle_message(store, BOB, "call me Bobby", NOW)
    handle_message(store, ALICE, "I'm going to Costco at 4pm", NOW)
    handle_message(store, BOB, "i need paper towels", NOW)
    reply, _ = handle_message(store, BOB, "status", NOW)
    assert "Costco" in reply
