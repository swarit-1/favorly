"""Gate 1 (backend side): favor_flow routing, fully offline.

Trellis is monkeypatched; the grocery loop must behave exactly as before and
everything else must branch on the intake contract.
"""

import asyncio
from datetime import datetime

import pytest

from agent.favor_flow import handle_inbound
from agent.store import AgentStore
from services import trellis_client

NOW = datetime(2026, 9, 19, 13, 30)
ASKER = "+15550000001"


@pytest.fixture()
def store(monkeypatch):
    monkeypatch.delenv("MUSE_API_KEY", raising=False)
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.delenv("DEMO_AUTOACCEPT_SECONDS", raising=False)
    return AgentStore()


def run(coro):
    return asyncio.run(coro)


def fake_intake(response):
    async def _intake(person_id, text, confirm_right_sized=False, source="sms"):
        _intake.calls.append({"text": text, "confirm_right_sized": confirm_right_sized})
        return response
    _intake.calls = []
    return _intake


@pytest.fixture(autouse=True)
def quiet_trellis(monkeypatch):
    async def _none(*a, **k):
        return None
    monkeypatch.setattr(trellis_client, "state", _none)
    monkeypatch.setattr(trellis_client, "log_event", _none)
    monkeypatch.setattr(trellis_client, "helpers", _none)


def test_grocery_ask_unchanged(store, monkeypatch):
    called = fake_intake(None)
    monkeypatch.setattr(trellis_client, "intake", called)
    replies, notes = run(handle_inbound(store, ASKER, "can someone grab me oat milk and eggs", NOW))
    assert len(replies) == 1
    assert "posted your ask" in replies[0]
    assert called.calls == []  # never went near intake
    assert len(store.pending_asks()) == 1


def test_moving_couch_is_not_a_trip(store, monkeypatch):
    need = {"id": "n1", "category": "hands", "title": "Move a couch together",
            "body": "x", "requires": ["handy"], "when_text": None,
            "duration_minutes": 60, "items": []}
    monkeypatch.setattr(trellis_client, "intake", fake_intake(
        {"intent": "ask_favor", "scope": "ok", "need": need, "parsed_by": "rules"}))
    replies, _ = run(handle_inbound(store, ASKER, "I'm going to need help moving a couch", NOW))
    assert "Finding the right neighbor" in replies[0]
    assert store.trips == {}  # no phantom trip to "Need Help Moving A Couch"


def test_borrow_ack_then_matches(store, monkeypatch):
    need = {"id": "n2", "category": "borrow", "title": "Borrow a ladder",
            "body": "x", "requires": ["ladder"], "when_text": "today",
            "duration_minutes": 60, "items": []}
    monkeypatch.setattr(trellis_client, "intake", fake_intake(
        {"intent": "ask_favor", "scope": "ok", "need": need, "parsed_by": "rules"}))

    async def fake_helpers(need_id, limit=3):
        return {"need_id": need_id, "decided_by": "graph", "helpers": [
            {"person": {"id": "p1", "first_name": "Marcus", "display_name": "Marcus Hill"},
             "rank": 1, "tie": "friend_of_friend", "tie_label": "Friend of Nora",
             "where": "3 floors up", "headline": "Has a 6 ft ladder",
             "reason": "Has a 6 ft ladder. You both know Nora.", "spark": None},
        ]}
    monkeypatch.setattr(trellis_client, "helpers", fake_helpers)

    replies, _ = run(handle_inbound(store, ASKER, "I need to borrow a ladder for an hour today", NOW))
    assert replies[0] == "Borrow a ladder, today. Finding the right neighbor."
    assert "Marcus" in replies[1] and "3 floors up" in replies[1]
    assert "friend of nora" in replies[1]
    assert "score" not in replies[1].lower()


def test_nobody_fits(store, monkeypatch):
    need = {"id": "n3", "category": "borrow", "title": "Borrow a pasta maker",
            "body": "x", "requires": ["pasta maker"], "when_text": None,
            "duration_minutes": 30, "items": []}
    monkeypatch.setattr(trellis_client, "intake", fake_intake(
        {"intent": "ask_favor", "scope": "ok", "need": need, "parsed_by": "rules"}))
    replies, _ = run(handle_inbound(store, ASKER, "anyone have a pasta maker", NOW))
    assert "pasta maker" in replies[1]
    assert "EVERYONE" in replies[1]


def test_too_big_then_yes_confirms(store, monkeypatch):
    rs = "help me carry the couch and bed frame down to the truck, about an hour"
    intake_calls = []

    async def _intake(person_id, text, confirm_right_sized=False, source="sms"):
        intake_calls.append((text, confirm_right_sized))
        if confirm_right_sized:
            return {"intent": "ask_favor", "scope": "ok", "parsed_by": "rules",
                    "need": {"id": "n4", "category": "hands", "title": "Carry the couch down",
                             "body": rs, "requires": ["handy"], "when_text": None,
                             "duration_minutes": 60, "items": []}}
        return {"intent": "ask_favor", "scope": "too_big",
                "scope_reply": "That is bigger than one favor.",
                "right_sized": rs, "need": None, "parsed_by": "rules"}
    monkeypatch.setattr(trellis_client, "intake", _intake)

    replies, _ = run(handle_inbound(store, ASKER, "help me move apartments", NOW))
    assert "Reply YES to post that" in replies[0]

    replies, _ = run(handle_inbound(store, ASKER, "yes", NOW))
    assert intake_calls[-1] == (rs, True)
    assert "Finding the right neighbor" in replies[0]


def test_not_ok_single_sentence(store, monkeypatch):
    monkeypatch.setattr(trellis_client, "intake", fake_intake(
        {"intent": "ask_favor", "scope": "not_ok",
         "scope_reply": "That is not something I can help with, sorry.",
         "need": None, "parsed_by": "rules"}))
    replies, _ = run(handle_inbound(store, ASKER, "can someone follow my ex", NOW))
    assert replies == ["That is not something I can help with, sorry."]


def test_offer_help_noted(store, monkeypatch):
    monkeypatch.setattr(trellis_client, "intake", fake_intake(
        {"intent": "offer_help", "scope": "ok", "need": None, "parsed_by": "rules"}))
    replies, _ = run(handle_inbound(store, ASKER, "I have a ladder if anyone ever needs one", NOW))
    assert replies == ["Noted. I will remember that."]


def test_trellis_unreachable_falls_back(store, monkeypatch):
    monkeypatch.setattr(trellis_client, "intake", fake_intake(None))
    replies, _ = run(handle_inbound(store, ASKER, "I need to borrow a ladder today", NOW))
    assert replies  # local parse still answers something
    assert isinstance(replies[0], str) and replies[0]


def test_trip_offer_still_routes_to_grocery(store, monkeypatch):
    called = fake_intake(None)
    monkeypatch.setattr(trellis_client, "intake", called)
    replies, _ = run(handle_inbound(store, ASKER, "I'm going to Trader Joe's at 3", NOW))
    assert "Trader Joe's" in replies[0]
    assert called.calls == []
