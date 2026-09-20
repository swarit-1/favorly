"""LLM calls, scoped to grocery-relevant extraction. All structured output.
Every function has a MOCK_LLM=1 fixture path (rule-based, deterministic,
offline) so the pipeline is fully testable without an API key.

Real calls use an OpenAI-compatible chat completions endpoint with
response_format={"type": "json_object"}.
"""

import json
import re

from config import settings

_client = None


def _get_client():
    global _client
    if _client is None:
        from openai import OpenAI
        _client = OpenAI(api_key=settings.LLM_API_KEY, base_url=settings.LLM_BASE_URL)
    return _client


def _chat_json(system: str, user: str, timeout: float | None = None) -> dict:
    client = _get_client()
    resp = client.chat.completions.create(
        model=settings.LLM_MODEL,
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
        response_format={"type": "json_object"},
        temperature=0.3,
        timeout=timeout,
    )
    return json.loads(resp.choices[0].message.content)


# ============================================================================
# Extraction: grocery-relevant claims only (dietary / mobility / budget /
# preference) -- no capability/need/affinity mining, no matchmaking signal.
# ============================================================================

EXTRACTION_SYSTEM_PROMPT = """You extract grocery-relevant facts from one
message in a neighborhood grocery-run app. Only extract facts that matter for
grocery trips: dietary restrictions or preferences, mobility (car access,
ability to carry bags, need for a ride), budget constraints, or store/brand
preferences. Rules that matter more than the rest:
1. Every claim must quote a literal, verbatim substring of the input as
   `evidence`, with its exact character span. Not a paraphrase.
2. Return an empty array freely -- most messages contain nothing relevant.
   Do not invent a claim rather than returning nothing.
3. Confidence is about the inference, not the writing.
4. Nothing outside dietary/mobility/budget/preference -- no general
   capabilities, hobbies, or life-stage facts unrelated to grocery shopping.
Return JSON: {"claims": [{"kind": "dietary|mobility|budget|preference",
"label": str, "confidence": float, "evidence": str, "span": [start, end]}]}"""

# Compact rule table used by the mock extractor. Scoped to grocery-relevant
# signal only -- exists so the pipeline (span verification, canonicalization,
# corroboration) is exercisable end to end with zero network calls.
_MOCK_RULES = [
    (r"vegetarian|vegan\b", "dietary", "vegetarian", 0.75),
    (r"gluten[- ]free|celiac", "dietary", "gluten free", 0.75),
    (r"lactose[- ]intoler|dairy[- ]free", "dietary", "dairy free", 0.75),
    (r"allergic to \w+|nut allergy|peanut allergy", "dietary", "food allergy", 0.7),
    (r"kosher|halal", "dietary", "dietary observance", 0.7),
    (r"don't have a car|no car|not driving|can't drive", "mobility", "no car access", 0.7),
    (r"\bi have a (car|truck|suv)\b|happy to drive|can drive", "mobility", "has car access", 0.7),
    (r"can't carry|trouble carrying|heavy bags are hard", "mobility", "needs help carrying bags", 0.65),
    (r"tight (on cash|budget)|on a budget|watching my spending", "budget", "budget conscious", 0.6),
    (r"always shop at (trader joe'?s|whole foods|costco|aldi)", "preference", "store preference", 0.6),
    (r"only buy organic|prefer organic", "preference", "prefers organic", 0.6),
    (r"brand loyal|always get the same brand", "preference", "brand preference", 0.55),
]


def _extract_claims_mock(body: str) -> list[dict]:
    claims = []
    seen_labels = set()
    for pattern, kind, label, confidence in _MOCK_RULES:
        m = re.search(pattern, body, re.IGNORECASE)
        if not m:
            continue
        if label in seen_labels:
            continue
        seen_labels.add(label)
        start, end = m.span()
        claims.append({
            "kind": kind,
            "label": label,
            "confidence": confidence,
            "evidence": body[start:end],  # literal substring, by construction
            "span": [start, end],
        })
        if len(claims) >= 5:
            break
    return claims


def extract_claims(body: str) -> list[dict]:
    """One event body in, zero or more raw claim dicts out."""
    if settings.MOCK_LLM:
        return _extract_claims_mock(body)
    try:
        result = _chat_json(EXTRACTION_SYSTEM_PROMPT, body)
        return result.get("claims", [])
    except Exception:
        return []


# ============================================================================
# Favor intake: one lightweight JSON call that parses and right-sizes together.
# Mock path is a deterministic rule table so intake works with zero API keys.
# ============================================================================

PARSE_FAVOR_SYSTEM_PROMPT = """You read one text message sent to Favorly, an agent that helps neighbors in the same building do small favors for each other. Return JSON only.

intent:
- "ask_favor": they want help with something.
- "offer_help": they are telling you about something they own, know how to do, or are willing to do for neighbors, without asking for anything.
- "not_a_favor": greetings, questions about the service, anything else.

category (ask_favor only):
- errand: pick something up on a trip someone is already making (groceries, pharmacy, a package). Fill items.
- borrow: borrow a physical thing (ladder, drill, folding table, air mattress).
- hands: an extra pair of hands (move a couch, put up a shelf, carry boxes, hang a mirror).
- skill: know-how (set up a sound system, fix wifi, tune a bike, hem trousers).
- company: do something together (a walk, a gym session, coffee, watching the game, studying).
- ride: a lift somewhere nearby.
- care: keep an eye on something (water plants, feed a cat, hold a package).
- other: anything else that still fits the size rule.

THE SIZE RULE. A favor is something one neighbor can do for another in about two hours or less, with no licence, no real danger, and no payment.
- scope "ok": it fits.
- scope "too_big": a real need, but too large or too long for one favor (build a house, renovate a kitchen, move a whole apartment, plan my wedding). Do NOT refuse. Put the first useful, concrete, neighbor-sized piece in right_sized, written in the asker's voice, with a rough duration ("help me carry the couch and bed frame down to the truck, about an hour"). scope_reply is one warm sentence that offers it.
- scope "needs_pro": licensed or risky work (electrical panel, gas, roof, tree felling, medical, legal). scope_reply says a professional should do it. right_sized is a safe adjacent favor if one exists ("ask the building who they would recommend as an electrician"), else null.
- scope "not_ok": illegal, harmful, sexual or romantic, watching or tracking a person, or paid labour. scope_reply is one polite sentence. No lecture.
- scope "unclear": you cannot tell what they need. scope_reply is ONE short question.
Never mention rules or policies. Never moralize. One sentence.

fields:
- title: imperative, at most 6 words, no names ("Borrow a ladder", "Put up a shelf together", "Walk the reservoir").
- requires: 0 to 3 lowercase tags a helper would need: things ("ladder", "drill", "car") or skills ("handy", "audio setup", "bike repair"). For company, the activity ("walking", "running"), else empty.
- when_text: their own words for when, else null.
- duration_minutes: honest estimate, 15 to 120.
- items: errand only, [{name, qty, note}].
No em dashes or en dashes anywhere.

Return: {"intent":..., "category":..., "scope":..., "scope_reply":..., "right_sized":..., "title":..., "requires":[...], "when_text":..., "duration_minutes":..., "items":[...]}"""

_WHEN_RE = re.compile(
    r"\b(today|tonight|tomorrow|this (?:morning|afternoon|evening|weekend)|"
    r"(?:mon|tues|wednes|thurs|fri|satur|sun)day(?: morning| afternoon| evening)?|"
    r"at \d{1,2}(?::\d{2})?\s?(?:am|pm)?|around \d{1,2})\b",
    re.IGNORECASE,
)

_DURATION_RE = re.compile(r"\bfor (?:an|a|one) hour\b|\bfor (\d+) ?(hours?|hrs?|min(?:ute)?s?)\b", re.IGNORECASE)

_ARTICLES = {"a", "an", "the", "some", "my", "your", "his", "her", "their", "our"}
_NOUN_STOPWORDS = {
    "for", "to", "today", "tonight", "tomorrow", "this", "at", "around", "on",
    "if", "so", "and", "please", "by", "until", "when", "while", "that", "with",
    "from", "anyone", "someone", "ever", "one",
}

_NOT_OK_RE = re.compile(
    r"follow (my|him|her)|\bspy\b|track (my|his|her)|pay (you|someone)|\bfake\b|prescription",
    re.IGNORECASE,
)
_NEEDS_PRO = [
    (r"rewire|breaker", "an electrician", "ask the building who they would recommend as an electrician"),
    (r"gas (line|leak)", "a licensed gas fitter", None),
    (r"\broof\b", "a roofer", "ask the building who they would recommend as a roofer"),
    (r"cut down .*tree", "an arborist", "ask the building who they would recommend as an arborist"),
    (r"asbestos", "a licensed abatement crew", None),
]
_TOO_BIG = [
    (r"build (a|the) house", "help me put together a materials list and price it out, about an hour"),
    (r"renovate|remodel", "help me clear and prep one room so the work can start, about an hour"),
    (r"move (apartments|out|house)", "help me carry the couch and bed frame down to the truck, about an hour"),
    (r"paint (my|the) (whole|entire)", "help me paint one wall to test the color, about an hour"),
    (r"plan my wedding", "help me fold and stuff the invitations, about an hour"),
]
_OFFER_RE = re.compile(
    r"\bi have (?:a|an|some) .+?(?:if anyone|anyone can|happy to lend)|i can help with",
    re.IGNORECASE,
)

_SKILL_MAP = [
    (r"sound system|speakers|\btv\b", "audio setup"),
    (r"wifi|router|printer", "wifi"),
    (r"\bbike\b", "bike repair"),
]

_ERRAND_RE = re.compile(r"\b(grab|pick up|get me|buy|bring me)\b", re.IGNORECASE)
_BORROW_RE = re.compile(r"\b(?:borrow|lend me|does anyone have|anyone have an?)\b", re.IGNORECASE)
_HANDS_RE = re.compile(
    r"help (?:me |us )?(?:with )?(build|assemble|hang|put up|putting up|move|moving|carry|carrying|lift|lifting|install|installing|mount|mounting)",
    re.IGNORECASE,
)
_SKILL_RE = re.compile(
    r"(set ?up|setting ?up|fix|repair|tune|configure).*(sound system|speakers|wifi|router|bike|printer|tv)",
    re.IGNORECASE,
)
_COMPANY_RE = re.compile(
    r"\b(walk|run|jog|coffee|gym|workout|study|watch the game)\b.{0,24}\bwith me\b|anyone want to",
    re.IGNORECASE,
)
_RIDE_RE = re.compile(r"\b(ride|lift|drive me|drop me)\b", re.IGNORECASE)
_CARE_RE = re.compile(
    r"\b(water my plants|feed my (?:cat|dog|fish)|watch my|hold a package)\b", re.IGNORECASE,
)
_ASKISH_RE = re.compile(r"\b(need|help|can someone|can anyone|could someone|could anyone|anyone)\b", re.IGNORECASE)

_DEFAULT_DURATION = {
    "errand": 30, "borrow": 30, "hands": 60, "skill": 60,
    "company": 60, "ride": 20, "care": 20, "other": 30,
}


def _when_text(text: str) -> str | None:
    m = _WHEN_RE.search(text)
    return m.group(1).lower() if m else None


def _duration(text: str, category: str) -> int:
    m = _DURATION_RE.search(text)
    if m:
        if m.group(1) is None:
            return 60
        n = int(m.group(1))
        if m.group(2).lower().startswith(("hour", "hr")):
            return min(n * 60, 120)
        return max(15, min(n, 120))
    return _DEFAULT_DURATION.get(category, 30)


def _noun_after(text: str, start: int, max_words: int = 3) -> str:
    """The thing being borrowed/fetched: words after the match, articles
    dropped, stopping at the first filler word."""
    words = re.findall(r"[a-z0-9']+", text[start:].lower())
    out: list[str] = []
    for w in words:
        if w in _ARTICLES and not out:
            continue
        if w in _NOUN_STOPWORDS:
            break
        out.append(w)
        if len(out) >= max_words:
            break
    return " ".join(out)


def _strip_when(phrase: str) -> str:
    return _WHEN_RE.sub("", phrase).strip(" ,.")


def _split_items(rest: str) -> list[dict]:
    rest = re.split(r"[.?!]", rest)[0]
    rest = re.sub(r"^\s*me\s+", "", rest)  # "grab me oat milk" -> "oat milk"
    rest = _WHEN_RE.sub("", rest)
    parts = re.split(r",|\band\b|\+|&", rest)
    items = []
    for part in parts:
        name = part.strip(" .!?,")
        name = re.sub(r"^(some|a|an|the)\s+", "", name)
        if name and name not in {"me", "please", "thanks", "thank you"}:
            items.append({"name": name, "qty": 1, "note": None})
    return items[:6]


def _favor(intent="ask_favor", category="other", scope="ok", scope_reply=None,
           right_sized=None, title=None, requires=None, when_text=None,
           duration_minutes=None, items=None) -> dict:
    return {
        "intent": intent, "category": category, "scope": scope,
        "scope_reply": scope_reply, "right_sized": right_sized, "title": title,
        "requires": requires or [], "when_text": when_text,
        "duration_minutes": duration_minutes, "items": items or [],
    }


def _parse_favor_mock(text: str) -> dict:
    lowered = text.lower()
    when = _when_text(text)

    if _NOT_OK_RE.search(lowered):
        return _favor(scope="not_ok",
                      scope_reply="That is not something I can help with, sorry.")

    for pattern, pro, adjacent in _NEEDS_PRO:
        if re.search(pattern, lowered):
            return _favor(
                scope="needs_pro", right_sized=adjacent,
                scope_reply=f"That one really needs {pro}, it is not safe as a neighbor favor.",
            )

    for pattern, right_sized in _TOO_BIG:
        if re.search(pattern, lowered):
            return _favor(
                scope="too_big", right_sized=right_sized,
                scope_reply=(
                    "That is bigger than one favor, but here is a first piece a "
                    f"neighbor could do: {right_sized}."
                ),
            )

    if _OFFER_RE.search(lowered):
        return _favor(intent="offer_help", category="other")

    m = _BORROW_RE.search(lowered)
    if m:
        noun = _noun_after(lowered, m.end()) or "it"
        return _favor(
            category="borrow", title=f"Borrow a {noun}"[:60], requires=[noun],
            when_text=when, duration_minutes=_duration(lowered, "borrow"),
        )

    m = _SKILL_RE.search(lowered)
    if m:
        skill = next((s for p, s in _SKILL_MAP if re.search(p, m.group(2))), m.group(2))
        thing = m.group(2)
        return _favor(
            category="skill", title=f"Set up the {thing}"[:60] if "set" in m.group(1) else f"Fix the {thing}"[:60],
            requires=[skill], when_text=when,
            duration_minutes=_duration(lowered, "skill"),
        )

    m = _HANDS_RE.search(lowered)
    if m:
        verb = m.group(1).lower()
        base = {"putting up": "put up", "moving": "move", "carrying": "carry",
                "lifting": "lift", "installing": "install", "mounting": "mount"}.get(verb, verb)
        requires = ["handy"]
        if base in ("build", "hang", "mount", "put up"):
            requires.append("drill")
        obj = _strip_when(_noun_after(lowered, m.end())) or "something"
        return _favor(
            category="hands", title=f"{base.capitalize()} a {obj} together"[:60],
            requires=requires, when_text=when,
            duration_minutes=_duration(lowered, "hands"),
        )

    m = _COMPANY_RE.search(lowered)
    if m:
        activity_word = (m.group(1) or "").lower()
        activity = {"walk": "walking", "run": "running", "jog": "running"}.get(activity_word, activity_word)
        if not activity:
            n = _noun_after(lowered, m.end())
            activity = {"walk": "walking", "run": "running", "go on a walk": "walking"}.get(n, n)
            if "walk" in n:
                activity = "walking"
            elif "run" in n:
                activity = "running"
        title_bit = activity or "hanging out"
        return _favor(
            category="company", title=f"Go for a {activity_word or 'walk'} together"[:60],
            requires=[title_bit] if title_bit else [], when_text=when,
            duration_minutes=_duration(lowered, "company"),
        )

    m = _RIDE_RE.search(lowered)
    if m:
        dest_m = re.search(r"\b(?:to|into)\s+([a-z0-9' ]+?)(?:\s+at\b|\s+around\b|[.,!?]|$)", lowered[m.end():])
        dest = dest_m.group(1).strip() if dest_m else None
        return _favor(
            category="ride", title=(f"Ride to {dest}" if dest else "Give a ride")[:60],
            requires=["car"], when_text=when,
            duration_minutes=_duration(lowered, "ride"),
        )

    m = _CARE_RE.search(lowered)
    if m:
        phrase = m.group(1)
        title = re.sub(r"\bmy\b", "the", phrase).capitalize()
        return _favor(
            category="care", title=title[:60], when_text=when,
            duration_minutes=_duration(lowered, "care"),
        )

    m = _ERRAND_RE.search(lowered)
    if m:
        items = _split_items(lowered[m.end():])
        if items:
            names = " and ".join(i["name"] for i in items[:2])
            return _favor(
                category="errand", title=f"Grab {names}"[:60],
                when_text=when, duration_minutes=_duration(lowered, "errand"),
                items=items,
            )

    if _ASKISH_RE.search(lowered):
        return _favor(scope="unclear", scope_reply="What do you need a hand with?")
    return _favor(intent="not_a_favor")


_VALID_CATEGORIES = {"errand", "borrow", "hands", "skill", "company", "ride", "care", "other"}
_VALID_SCOPES = {"ok", "too_big", "needs_pro", "not_ok", "unclear"}


def parse_favor(text: str, now=None) -> dict:
    """One message in, a parsed + scope-checked favor out. Real path is a 4 s
    JSON call; any failure (or MOCK_LLM) uses the deterministic rules above."""
    if not settings.MOCK_LLM and settings.LLM_API_KEY:
        try:
            when_str = now.strftime("%A %I:%M %p") if now else ""
            raw = _chat_json(
                PARSE_FAVOR_SYSTEM_PROMPT,
                f"Current local time: {when_str}\nMessage: {text}",
                timeout=4.0,
            )
            out = _favor(
                intent=raw.get("intent") if raw.get("intent") in ("ask_favor", "offer_help", "not_a_favor") else "not_a_favor",
                category=raw.get("category") if raw.get("category") in _VALID_CATEGORIES else "other",
                scope=raw.get("scope") if raw.get("scope") in _VALID_SCOPES else "ok",
                scope_reply=raw.get("scope_reply"),
                right_sized=raw.get("right_sized"),
                title=raw.get("title"),
                requires=[str(r).lower() for r in (raw.get("requires") or [])][:3],
                when_text=raw.get("when_text"),
                duration_minutes=raw.get("duration_minutes"),
                items=[i for i in (raw.get("items") or []) if isinstance(i, dict) and i.get("name")],
            )
            out["parsed_by"] = "model"
            return out
        except Exception:
            pass
    out = _parse_favor_mock(text)
    out["parsed_by"] = "rules"
    return out


# ============================================================================
# Canonicalization adjudication (middle similarity band only)
# ============================================================================

DECIDE_SYSTEM_PROMPT = """You decide which favors a neighbor should do in a
neighborhood favor app.

You are given a `helper` (the person you're advising) and a list of
`candidates` -- open requests from neighbors, each already scored by the
graph. The graph did the retrieval; you make the judgment call about which
are actually worth doing, in what order, and how to frame each one.

The signals attached to each candidate mean:
- trip: the helper already has a grocery trip planned that covers this. This
  is the strongest practical reason -- the errand is nearly free to them.
- reciprocity: that neighbor has done favors FOR THE HELPER recently. Never
  state this the other way round -- the helper has not helped them. Each
  candidate's `true_facts` spells out the direction; copy it faithfully.
- mutual: they share connections in the neighborhood.
- fit: the helper's situation complements the need (e.g. has a car, neighbor
  doesn't).
- freshness: how recently it was posted.

Rules:
- You may reorder, and you may DROP a candidate that isn't worth surfacing.
  You may NOT invent a candidate: every need_id you return must appear in the
  input.
- Each candidate's `true_facts` is the authoritative list of what is true,
  already written in second person. Lift them almost verbatim -- do not
  restate one backwards, embellish it, or add facts of your own. No invented
  names, stores, numbers, times, or details. If you aren't given a store name,
  don't name one.
- Write to the helper as "you". Never say "the helper", and never echo the
  field names or formatting of this input.
- `title`: under 6 words, imperative, names the favor and the neighbor's first
  name, e.g. "Lend Bob a ladder" or "Walk the reservoir with Priya".
- `action`: one short line describing what they'd actually do.
- `reason`: one sentence, under 25 words, saying why this person specifically.
  Never imply debt or obligation -- no "you owe them" or "pay it back".
- Never use em dashes or en dashes. Use commas, colons or full stops.
- Never guess anyone's gender: use their name or "they".
- The favor is the occasion; the connection between two neighbors is the
  point. Frame each one as one person showing up for another, not as a task
  being dispatched. You are pointing, not deciding for them.
- Be concrete, not vague. Use the specifics you were given: name the mutual
  connection ("you both know Maya") rather than saying "mutual friends"; name
  the store; say what they actually asked for. A specific reason is the whole
  point -- a generic one is worse than none.
- `effort`: "low" if it's on a trip they're already making, otherwise judge it.
- Return them best-first.

Return JSON: {"favors": [{"need_id": str, "title": str, "action": str,
"reason": str, "effort": "low"|"medium"|"high"}]}"""


def decide_favors(context: dict) -> list[dict] | None:
    """Let the model choose and frame the favors, using the graph's context.

    Returns None when unavailable (MOCK_LLM, no key, API error, malformed
    output) so the caller falls back to the deterministic graph ranking.
    """
    if settings.MOCK_LLM or not settings.LLM_API_KEY:
        return None
    try:
        result = _chat_json(DECIDE_SYSTEM_PROMPT, json.dumps(context, default=str))
        favors = result.get("favors")
        return favors if isinstance(favors, list) else None
    except Exception:
        return None


def adjudicate_canonical(raw_label: str, candidates: list[tuple[str, float]]) -> str:
    """candidates: top-3 (canonical_label, similarity). Returns a canonical label --
    either one of the candidates, or a decision that this is genuinely new (in which
    case the caller mints raw_label as the new canonical).
    """
    if not candidates:
        return raw_label
    if settings.MOCK_LLM:
        # Heuristic stand-in: snap to the closest candidate since we don't have a
        # real judgment call offline.
        return candidates[0][0]
    try:
        system = (
            "Decide whether a new label refers to the same underlying concept as one "
            "of the candidate canonical labels, or is genuinely distinct. "
            'Return JSON: {"canonical": str} -- either an exact candidate label, or the '
            "raw label itself if none fit."
        )
        user = json.dumps({"raw_label": raw_label, "candidates": [c for c, _ in candidates]})
        result = _chat_json(system, user)
        return result.get("canonical", raw_label)
    except Exception:
        return candidates[0][0]
