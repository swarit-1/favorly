"""Gate 3 (offline half): the full SMS loop against a scripted Trellis.

ask -> MATCHES -> "1" -> WAIT + INVITE -> "yes" (helper phone) -> both ACCEPTs
-> "done" -> both DONEs. trellis_client is monkeypatched with a tiny stateful
fake so no network, no keys, no database.
"""

import asyncio
from datetime import datetime

import pytest

from agent.favor_flow import handle_inbound
from agent.store import AgentStore
from services import trellis_client

NOW = datetime(2026, 9, 19, 13, 30)
ASKER_PHONE = "+15550000001"
HELPER_PHONE = "+15550000002"


class FakeTrellis:
    """Just enough state to drive the loop."""

    def __init__(self, asker_id, helper_id):
        self.asker_id, self.helper_id = asker_id, helper_id
        self.need = None
        self.invited = False
        self.accepted = False
        self.fulfilled = False

    async def intake(self, person_id, text, confirm_right_sized=False, source="sms"):
        self.need = {
            "id": "need-1", "category": "borrow", "title": "Borrow a ladder",
            "body": text, "requires": ["ladder"], "when_text": "today",
            "duration_minutes": 60, "items": [],
        }
        return {"intent": "ask_favor", "scope": "ok", "need": self.need, "parsed_by": "rules"}

    async def helpers(self, need_id, limit=3):
        return {"need_id": need_id, "decided_by": "graph", "helpers": [
            {"person": {"id": self.helper_id, "first_name": "Marcus", "display_name": "Marcus Hill"},
             "rank": 1, "tie": "friend_of_friend", "tie_label": "Friend of Nora",
             "where": "3 floors up", "headline": "Has a 6 ft ladder",
             "reason": "Has a 6 ft ladder. You both know Nora.", "spark": "You both follow Formula 1."},
            {"person": {"id": "p-elena", "first_name": "Elena", "display_name": "Elena Vasquez"},
             "rank": 2, "tie": "close", "tie_label": "You know each other",
             "where": "same floor", "headline": "Has a step ladder",
             "reason": "Has a step ladder. Elena helped you out last week.", "spark": None},
        ]}

    async def invite(self, need_id, helper_id):
        self.invited = True
        return {"status": "pending"}

    async def respond_invite(self, need_id, helper_id, accept):
        self.accepted = accept
        return {"status": "accepted" if accept else "declined", "next": None}

    async def fulfill(self, need_id):
        self.fulfilled = True
        return {"id": need_id, "status": "fulfilled", "favor_logged": True,
                "first_favor_together": True,
                "separation": {"before": 2.61, "after": 2.33}}

    async def state(self, person_id):
        if person_id == self.asker_id:
            if self.accepted and not self.fulfilled:
                return {"person": None, "open_ask": None, "pending_invite": None,
                        "active_favor": {"need_id": "need-1", "title": "Borrow a ladder",
                                         "role": "asker",
                                         "other": {"id": self.helper_id, "first_name": "Marcus", "unit": "6C"},
                                         "spark": "You both follow Formula 1."}}
            if self.need:
                return {"person": None, "pending_invite": None, "active_favor": None,
                        "open_ask": {"need_id": "need-1", "title": "Borrow a ladder",
                                     "category": "borrow",
                                     "shortlist": [
                                         {"rank": 1, "person_id": self.helper_id,
                                          "first_name": "Marcus",
                                          "invite_status": "pending" if self.invited else None},
                                         {"rank": 2, "person_id": "p-elena",
                                          "first_name": "Elena", "invite_status": None},
                                     ]}}
            return {"person": None, "open_ask": None, "pending_invite": None, "active_favor": None}
        # helper side
        if self.accepted and not self.fulfilled:
            return {"person": None, "open_ask": None, "pending_invite": None,
                    "active_favor": {"need_id": "need-1", "title": "Borrow a ladder",
                                     "role": "helper",
                                     "other": {"id": self.asker_id, "first_name": "Swarit", "unit": "3C"},
                                     "spark": "You both follow Formula 1."}}
        if self.invited and not self.accepted:
            return {"person": None, "open_ask": None, "active_favor": None,
                    "pending_invite": {"need_id": "need-1", "title": "Borrow a ladder",
                                       "category": "borrow", "when_text": "today",
                                       "asker": {"id": self.asker_id, "first_name": "Swarit", "floor": 3},
                                       "mutual_first_name": "Nora"}}
        return {"person": None, "open_ask": None, "pending_invite": None, "active_favor": None}

    async def log_event(self, *a, **k):
        return None

    async def broadcast(self, need_id):
        return {"status": "open", "broadcast": True}

    async def cancel(self, need_id):
        return {"status": "cancelled"}


@pytest.fixture()
def loop_env(monkeypatch):
    monkeypatch.delenv("MUSE_API_KEY", raising=False)
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.delenv("DEMO_AUTOACCEPT_SECONDS", raising=False)
    store = AgentStore()
    asker = store.user_for_phone(ASKER_PHONE)
    helper = store.user_for_phone(HELPER_PHONE)
    helper.user.name = "Marcus Hill"
    fake = FakeTrellis(str(asker.user.id), str(helper.user.id))
    for name in ("intake", "helpers", "invite", "respond_invite", "fulfill",
                 "state", "log_event", "broadcast", "cancel"):
        monkeypatch.setattr(trellis_client, name, getattr(fake, name))
    return store, fake


def run(coro):
    return asyncio.run(coro)


def test_full_loop(loop_env):
    store, fake = loop_env

    # 1. ask -> ACK + MATCHES
    replies, notes = run(handle_inbound(store, ASKER_PHONE, "I need to borrow a ladder for an hour today", NOW))
    assert replies[0] == "Borrow a ladder, today. Finding the right neighbor."
    assert "Two neighbors who fit:" in replies[1]
    assert "Marcus · 3 floors up · friend of nora" in replies[1]
    assert "Reply 1 or 2 and I will ask them. Or reply EVERYONE." in replies[1]

    # 2. "1" -> WAIT to asker, INVITE to helper phone
    replies, notes = run(handle_inbound(store, ASKER_PHONE, "1", NOW))
    assert replies == ["Asked Marcus. I will text you as soon as they answer."]
    assert fake.invited
    assert len(notes) == 1 and notes[0][0] == HELPER_PHONE
    invite_msg = notes[0][1]
    assert "Swarit on floor 3, a friend of Nora," in invite_msg
    assert "borrow a ladder, today" in invite_msg
    assert "Reply YES or NO. No pressure either way." in invite_msg

    # 3. helper says yes -> ACCEPT both sides, unit revealed only now
    replies, notes = run(handle_inbound(store, HELPER_PHONE, "yes", NOW))
    assert fake.accepted
    assert replies[0].startswith("You are on. Swarit is in 3C.")
    assert "Text DONE here" in replies[0]
    assert len(notes) == 1 and notes[0][0] == ASKER_PHONE
    assert notes[0][1].startswith("Marcus is in. They are in 6C.")

    # 4. helper says done -> DONE to both, first favor together
    replies, notes = run(handle_inbound(store, HELPER_PHONE, "done", NOW))
    assert fake.fulfilled
    assert replies[0] == "Done. That was your first favor together. Your building just got a little closer."
    assert len(notes) == 1 and notes[0][0] == ASKER_PHONE
    assert notes[0][1] == replies[0]

    # no scores anywhere in the whole journey
    # (WAIT/INVITE/ACCEPT/DONE checked above contain none)


def test_decline_offers_next(loop_env):
    store, fake = loop_env
    run(handle_inbound(store, ASKER_PHONE, "I need to borrow a ladder for an hour today", NOW))
    run(handle_inbound(store, ASKER_PHONE, "1", NOW))

    async def decline(need_id, helper_id, accept):
        return {"status": "declined", "next": {
            "person": {"id": "p-elena", "first_name": "Elena", "display_name": "Elena Vasquez"},
            "rank": 2, "tie": "close", "invite_status": None}}
    fake.respond_invite = decline
    import services.trellis_client as tc
    tc.respond_invite = decline

    replies, notes = run(handle_inbound(store, HELPER_PHONE, "no", NOW))
    assert replies == ["All good, thanks for answering. I will ask someone else."]
    assert len(notes) == 1 and notes[0][0] == ASKER_PHONE
    assert notes[0][1] == "Marcus can't make it today. Want me to ask Elena? Reply YES, or pick a number."


def test_everyone_broadcasts_and_cancel_cancels(loop_env):
    store, fake = loop_env
    run(handle_inbound(store, ASKER_PHONE, "I need to borrow a ladder for an hour today", NOW))
    replies, _ = run(handle_inbound(store, ASKER_PHONE, "everyone", NOW))
    assert "whole building" in replies[0]
    replies, _ = run(handle_inbound(store, ASKER_PHONE, "cancel", NOW))
    assert replies[0].startswith("Cancelled.")
