# Favorly v2 demo script (hero journey, real output)

Every line below is the actual output of a full run against the seeded
`block` scenario with `MOCK_LLM=1` (2026-09-20, commit on `v2-brain`).
Pitch line: "Favorly does not get your errand done faster. It makes your
building smaller."

## Before going on

1. `./scripts/demo_reset.sh` (reseeds the block, clears agent memory, warms
   both services three times).
2. Ping `/health` on both services once more 60 seconds before you start.
3. Presenter phones: set `LINQ_USER_PHONES="+1<presenter>=Swarit Srivastava,+1<helper>=Elena Vasquez"`
   on the backend and restart it. The first text from each phone writes the
   phone onto the users row, so this heals itself after one message.
4. Linq sandbox limits: inbound first; every demo phone texts "hi" once up
   front; 30 msgs/60s per pair, 100/day. A full run is about 12 messages.

## The run (verbatim)

YOU (text Favorly):

    I need to borrow a ladder for an hour today

FAVORLY (within 2 s):

    Borrow a ladder, today. Finding the right neighbor.

FAVORLY (within 6 s):

    Three neighbors who fit:

    1. Elena · same floor · you know each other
    Has a ladder, and you know each other.

    2. Marcus · 3 floors up · friend of nora
    Has a ladder, and you both know Nora.

    3. Jordan · 1 floor down · new to you
    Has a ladder, and Jordan is 1 floor down.

    Reply 1, 2 or 3 and I will ask them. Or reply EVERYONE.

YOU:

    1

FAVORLY:

    Asked Elena. I will text you as soon as they answer.

FAVORLY (to Elena's phone):

    Swarit on floor 3 is hoping for a hand: borrow a ladder, today.
    Up for it? Reply YES or NO. No pressure either way.

ELENA:

    yes

FAVORLY (to Elena):

    You are on. Swarit is in 3C. Text DONE here when it is wrapped up.

FAVORLY (to you):

    Elena is in. They are in 3D.

ELENA (later):

    done

FAVORLY (to Elena):

    Done. Thanks for showing up for Swarit.

FAVORLY (to you):

    Done. Elena came through for you.

Note: Elena had already helped Swarit once in the seed, so this is not their
first favor. Pick Marcus (reply `2`) for the first-favor ending:

    Done. That was your first favor together. Your building just got a little closer.

and the Marcus invite names the mutual: "Swarit on floor 3, a friend of
Nora, ..." with spark "You both follow Formula 1."

## Other journeys that work (all verified)

- Too big: "help me build a house" -> right-sized offer, reply YES to post it.
- Needs a pro: "can someone rewire my breaker panel" -> steer to an electrician.
- Not ok: "can someone follow my ex..." -> one polite sentence, no lecture.
- Company: "anyone want to walk the reservoir with me around 6" -> Priya and
  Grace surface on shared walking + availability.
- Hands: "can someone help me put up a shelf" -> Marcus, Nora, Tom (the
  retired carpenter clears slot three).
- Errand regression: "can someone grab me oat milk and eggs" -> exactly the
  v1 grocery reply, untouched.
- Offer: "I have a ladder if anyone ever needs one" -> "Noted. I will
  remember that." (claim extracted in the background).
- Nobody fits: "anyone have a pasta maker" -> "Nobody has told me they have
  a pasta maker yet. Want me to ask the whole building? Reply EVERYONE."
- EVERYONE / CANCEL / decline ("no" from the helper offers the next
  neighbor) all answer in one message.

If a judge asks: seeded personas without phones answer in the app; with
`DEMO_AUTOACCEPT_SECONDS` set they accept after that delay (logged as
`[demo] auto-accept for seeded persona`). On stage the hero helper is a real
teammate's phone.
