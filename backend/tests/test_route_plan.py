"""Offline tests for the Favorly Route planner (routes/route.py).

Everything here exercises the pure planner core on plain dicts. No DB, no
network, no FastAPI app.
"""

import random

from routes.route import (
    DEFAULT_ITEM_PRICE,
    baseline_distance,
    build_caps,
    build_plan,
    build_suggestions,
    extract_need_item,
    group_by_section,
    held_karp,
    insertion_delta,
    load_layout,
    manhattan,
    path_length,
    plan_route,
    sections_in_written_order,
)


def _item(name, section, requester_id="r1", requester_first="Grace", max_price=None, qty=1):
    return {
        "name": name,
        "qty": qty,
        "section": section,
        "requester_id": requester_id,
        "requester_first": requester_first,
        "max_price": max_price,
    }


LAYOUT = load_layout()


# ============================================================================
# Held-Karp
# ============================================================================

class TestHeldKarp:
    def test_two_nodes_direct(self):
        pts = [{"x": 0, "y": 0}, {"x": 3, "y": 4}]
        order, dist = held_karp(pts)
        assert order == [0, 1]
        assert dist == 7

    def test_known_optimal_six_nodes(self):
        # entrance (0,0), checkout (10,0); middles form a box above the front.
        # Any tour must climb to y=10 and back (vertical >= 20) and cover
        # x 0 -> 10 (horizontal >= 10), so 30 is a hard lower bound. The order
        # A(1,5) -> C(1,10) -> D(9,10) -> B(9,5) achieves exactly 30.
        E = {"x": 0, "y": 0}
        A = {"x": 1, "y": 5}
        B = {"x": 9, "y": 5}
        C = {"x": 1, "y": 10}
        D = {"x": 9, "y": 10}
        X = {"x": 10, "y": 0}
        order, dist = held_karp([E, A, B, C, D, X])
        assert dist == 30
        assert order == [0, 1, 3, 4, 2, 5]  # E, A, C, D, B, X

    def test_route_never_beats_lower_bound_and_matches_brute_force(self):
        from itertools import permutations

        rng = random.Random(7)
        for _ in range(20):
            pts = [{"x": rng.randint(0, 30), "y": rng.randint(0, 20)} for _ in range(6)]
            _, dist = held_karp(pts)
            mids = list(range(1, 5))
            brute = min(
                path_length([pts[0]] + [pts[i] for i in perm] + [pts[5]])
                for perm in permutations(mids)
            )
            assert abs(dist - brute) < 1e-9


class TestRouteVsBaseline:
    def test_optimal_route_never_longer_than_written_order(self):
        sections = ["produce", "dairy", "meat", "bakery", "frozen", "pantry",
                    "beverages", "household", "personal_care", "other"]
        rng = random.Random(42)
        for _ in range(25):
            picked = rng.sample(sections, rng.randint(1, 8))
            items = [_item(f"thing-{i}", s) for i, s in enumerate(picked)]
            rng.shuffle(items)
            _, _, dist = plan_route(items, LAYOUT)
            assert dist <= baseline_distance(items, LAYOUT) + 1e-9

    def test_empty_trip_still_yields_valid_walk(self):
        stops, path, dist = plan_route([], LAYOUT)
        assert stops == []
        assert path[0] == LAYOUT["nodes"]["entrance"] or (
            path[0]["x"] == LAYOUT["nodes"]["entrance"]["x"]
            and path[0]["y"] == LAYOUT["nodes"]["entrance"]["y"]
        )
        assert len(path) == 2
        assert dist == manhattan(LAYOUT["nodes"]["entrance"], LAYOUT["nodes"]["checkout"])


# ============================================================================
# Grouping
# ============================================================================

class TestGrouping:
    def test_group_by_section(self):
        items = [
            _item("bananas", "produce"),
            _item("milk", "dairy"),
            _item("apples", "produce"),
        ]
        grouped = group_by_section(items)
        assert set(grouped) == {"produce", "dairy"}
        assert [it["name"] for it in grouped["produce"]] == ["bananas", "apples"]

    def test_written_order_keeps_first_mention(self):
        items = [
            _item("milk", "dairy"),
            _item("bananas", "produce"),
            _item("cheese", "dairy"),
            _item("bread", "bakery"),
        ]
        assert sections_in_written_order(items) == ["dairy", "produce", "bakery"]

    def test_missing_section_falls_back_to_other(self):
        grouped = group_by_section([{"name": "mystery", "qty": 1, "section": None}])
        assert "other" in grouped

    def test_stops_carry_items_and_orders_start_at_one(self):
        items = [_item("bananas", "produce"), _item("milk", "dairy")]
        stops, path, _ = plan_route(items, LAYOUT)
        assert [s["order"] for s in stops] == [1, 2]
        assert len(path) == 4  # entrance + 2 stops + checkout
        by_sec = {s["section"]: s for s in stops}
        assert by_sec["produce"]["items"][0]["name"] == "bananas"
        assert by_sec["produce"]["items"][0]["requester_first"] == "Grace"


# ============================================================================
# Suggestions
# ============================================================================

class TestSuggestions:
    def test_neighbor_on_route_adds_zero_metres(self):
        items = [_item("cheese", "dairy")]
        _, path, _ = plan_route(items, LAYOUT)
        sugs = build_suggestions(
            items, [], path, LAYOUT,
            neighbor_needs=[{"name": "milk", "section": "dairy", "requester_first": "Grace"}],
        )
        assert len(sugs) == 1
        sug = sugs[0]
        assert sug["kind"] == "neighbor"
        assert sug["added_distance_m"] == 0.0
        assert sug["requester_first"] == "Grace"
        assert "Grace needs milk" in sug["reason"]
        assert "Adds 0 m" in sug["reason"]

    def test_neighbor_off_route_is_skipped(self):
        items = [_item("bananas", "produce")]
        _, path, _ = plan_route(items, LAYOUT)
        sugs = build_suggestions(
            items, [], path, LAYOUT,
            neighbor_needs=[{"name": "milk", "section": "dairy", "requester_first": "Grace"}],
        )
        assert sugs == []

    def test_future_you_off_route_added_distance_is_insertion_delta(self):
        items = [_item("bananas", "produce")]
        _, path, _ = plan_route(items, LAYOUT)
        sugs = build_suggestions(
            items, [], path, LAYOUT,
            pantry_low=[{"name": "eggs", "section": "dairy"}],
        )
        assert len(sugs) == 1
        expected = insertion_delta(path, LAYOUT["nodes"]["dairy"])
        assert sugs[0]["added_distance_m"] == round(expected, 1)
        assert expected > 0
        assert sugs[0]["kind"] == "future_you"

    def test_forgotten_only_when_section_on_path(self):
        items = [_item("bananas", "produce")]
        _, path, _ = plan_route(items, LAYOUT)
        sugs = build_suggestions(
            items, [], path, LAYOUT,
            forgotten=[
                {"name": "apples", "section": "produce"},
                {"name": "milk", "section": "dairy"},
            ],
        )
        assert [s["item"]["name"] for s in sugs] == ["apples"]
        assert sugs[0]["kind"] == "forgotten"
        assert sugs[0]["added_distance_m"] == 0.0

    def test_never_suggests_items_already_on_list_or_extras(self):
        items = [_item("milk", "dairy")]
        extras = [{"name": "eggs", "qty": 1, "section": "dairy", "requester_id": None, "requester_first": ""}]
        _, path, _ = plan_route(items + extras, LAYOUT)
        sugs = build_suggestions(
            items, extras, path, LAYOUT,
            neighbor_needs=[{"name": "milk", "section": "dairy", "requester_first": "Grace"}],
            pantry_low=[{"name": "eggs", "section": "dairy"}],
            forgotten=[{"name": "Milk", "section": "dairy"}],
        )
        assert sugs == []

    def test_at_most_three_and_neighbor_priority(self):
        items = [_item("cheese", "dairy"), _item("bananas", "produce"), _item("bread", "bakery")]
        _, path, _ = plan_route(items, LAYOUT)
        sugs = build_suggestions(
            items, [], path, LAYOUT,
            neighbor_needs=[
                {"name": "milk", "section": "dairy", "requester_first": "Grace"},
                {"name": "apples", "section": "produce", "requester_first": "Marcus"},
            ],
            pantry_low=[{"name": "bagels", "section": "bakery"}],
            forgotten=[{"name": "yogurt", "section": "dairy"}],
        )
        assert len(sugs) == 3
        assert [s["kind"] for s in sugs] == ["neighbor", "neighbor", "future_you"]

    def test_ids_stable_across_replans(self):
        items = [_item("cheese", "dairy")]
        _, path, _ = plan_route(items, LAYOUT)
        needs = [{"name": "milk", "section": "dairy", "requester_first": "Grace"}]
        first = build_suggestions(items, [], path, LAYOUT, neighbor_needs=needs)
        again = build_suggestions(items, [], path, LAYOUT, neighbor_needs=needs)
        assert first[0]["id"] == again[0]["id"] == "sug-neighbor-milk"

    def test_no_dashes_in_copy(self):
        items = [_item("cheese", "dairy")]
        _, path, _ = plan_route(items, LAYOUT)
        sugs = build_suggestions(
            items, [], path, LAYOUT,
            neighbor_needs=[{"name": "milk", "section": "dairy", "requester_first": "Grace"}],
            pantry_low=[{"name": "eggs", "section": "dairy", "scanned_day": "Thursday"}],
        )
        for s in sugs:
            assert "—" not in s["reason"] and "–" not in s["reason"]
            assert "—" not in s["title"] and "–" not in s["title"]

    def test_extract_need_item(self):
        assert extract_need_item("can someone grab milk on their way home") == ("milk", "dairy")
        assert extract_need_item("we ran out of paper towels") == ("paper towels", "household")
        assert extract_need_item("help me move a couch") is None


# ============================================================================
# Caps
# ============================================================================

class TestCaps:
    def test_default_five_dollar_estimate(self):
        items = [
            _item("milk", "dairy", requester_id="r1", max_price=None),
            _item("cheese", "dairy", requester_id="r1", max_price=None),
        ]
        caps = build_caps(items, [], cap=40.00)
        assert len(caps) == 1
        assert caps[0]["running_total"] == 2 * DEFAULT_ITEM_PRICE
        assert caps[0]["cap"] == 40.00
        assert caps[0]["over"] is False

    def test_mixed_prices_and_over_cap(self):
        items = [
            _item("steak", "meat", requester_id="r1", requester_first="Grace", max_price=22.50),
            _item("salmon", "meat", requester_id="r1", requester_first="Grace", max_price=15.00),
            _item("mystery", "other", requester_id="r1", requester_first="Grace"),  # +5.00 default
        ]
        caps = build_caps(items, [], cap=40.00)
        assert caps[0]["running_total"] == 42.50
        assert caps[0]["over"] is True
        assert caps[0]["requester_first"] == "Grace"

    def test_extras_count_toward_their_requester(self):
        items = [_item("milk", "dairy", requester_id="r1", max_price=3.00)]
        extras = [{"name": "eggs", "qty": 1, "section": "dairy",
                   "requester_id": "r1", "requester_first": "Grace", "max_price": None}]
        caps = build_caps(items, extras, cap=40.00)
        assert caps[0]["running_total"] == 8.00

    def test_extras_without_requester_are_uncapped(self):
        extras = [{"name": "eggs", "qty": 1, "section": "dairy",
                   "requester_id": None, "requester_first": "", "max_price": None}]
        assert build_caps([], extras, cap=40.00) == []

    def test_per_requester_split(self):
        items = [
            _item("milk", "dairy", requester_id="r1", requester_first="Grace", max_price=4.00),
            _item("bread", "bakery", requester_id="r2", requester_first="Marcus", max_price=6.00),
        ]
        caps = {c["requester_id"]: c for c in build_caps(items, [], cap=10.00)}
        assert caps["r1"]["running_total"] == 4.00
        assert caps["r2"]["running_total"] == 6.00


# ============================================================================
# Full plan shape
# ============================================================================

class TestBuildPlan:
    def test_frozen_response_shape(self):
        items = [
            _item("bananas", "produce", requester_id="r1", requester_first="Grace", qty=2),
            _item("milk", "dairy", requester_id="r1", requester_first="Grace", max_price=3.50),
        ]
        plan = build_plan(
            trip_id="t-1", store="Trader Joe's", items=items, extra_items=[],
            layout=LAYOUT, cap=40.00,
            neighbor_needs=[{"name": "eggs", "section": "dairy", "requester_first": "Marcus"}],
        )
        assert set(plan) == {
            "trip_id", "store", "layout", "stops", "path",
            "distance_m", "baseline_distance_m", "suggestions", "caps",
        }
        assert plan["layout"]["width_m"] == 30
        assert {n["key"] for n in plan["layout"]["nodes"]} >= {"entrance", "checkout", "produce", "dairy"}
        assert plan["distance_m"] <= plan["baseline_distance_m"]
        assert plan["stops"][0]["order"] == 1
        assert plan["path"][0] == {"x": 2.0, "y": 18.0}
        assert plan["path"][-1] == {"x": 15.0, "y": 18.0}
        assert plan["suggestions"][0]["id"] == "sug-neighbor-eggs"
        assert plan["caps"][0]["requester_first"] == "Grace"

    def test_empty_trip_returns_valid_plan(self):
        plan = build_plan("t-2", "Star Market", [], [], LAYOUT)
        assert plan["stops"] == []
        assert len(plan["path"]) == 2
        assert plan["distance_m"] > 0
        assert plan["suggestions"] == []
        assert plan["caps"] == []
