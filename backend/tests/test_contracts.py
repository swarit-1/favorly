"""Test Pydantic model validation and serialization."""

import pytest
from datetime import datetime
from decimal import Decimal
from uuid import uuid4

from shared.contracts import models


class TestEnums:
    """Test enum values."""

    def test_trip_status_values(self):
        assert models.TripStatus.OPEN.value == "open"
        assert models.TripStatus.SHOPPING.value == "shopping"
        assert models.TripStatus.SETTLING.value == "settling"
        assert models.TripStatus.DONE.value == "done"

    def test_request_status_values(self):
        assert models.RequestStatus.PENDING.value == "pending"
        assert models.RequestStatus.ACCEPTED.value == "accepted"
        assert models.RequestStatus.DECLINED.value == "declined"

    def test_item_status_values(self):
        assert models.ItemStatus.PENDING.value == "pending"
        assert models.ItemStatus.GOT.value == "got"
        assert models.ItemStatus.SUBSTITUTED.value == "substituted"
        assert models.ItemStatus.SKIPPED.value == "skipped"


class TestDomainModels:
    """Test domain entity models."""

    def test_user_creation(self):
        user = models.User(
            circle_id=uuid4(),
            name="Alice",
            venmo_handle="alice-venmo",
        )
        assert user.name == "Alice"
        assert user.venmo_handle == "alice-venmo"
        assert user.id is not None

    def test_circle_creation(self):
        circle = models.Circle(
            name="Maple St",
            invite_code="ABC123",
        )
        assert circle.name == "Maple St"
        assert circle.invite_code == "ABC123"

    def test_trip_caps_defaults(self):
        caps = models.TripCaps()
        assert caps.max_requesters == 6
        assert caps.max_dollars_per_person == Decimal("40.00")
        assert caps.max_items_per_person == 8

    def test_trip_creation(self):
        trip = models.Trip(
            shopper_id=uuid4(),
            circle_id=uuid4(),
            store="Trader Joe's",
            depart_at=datetime.utcnow(),
        )
        assert trip.store == "Trader Joe's"
        assert trip.status == models.TripStatus.OPEN

    def test_item_creation(self):
        item = models.Item(
            request_id=uuid4(),
            trip_id=uuid4(),
            name="Bananas",
            qty=3,
            max_price=Decimal("5.00"),
        )
        assert item.name == "Bananas"
        assert item.qty == 3
        assert item.status == models.ItemStatus.PENDING


class TestVLMOutputModels:
    """Test VLM output models."""

    def test_item_draft_creation(self):
        item_draft = models.ItemDraft(
            name="Organic Bananas",
            qty=2,
            confidence=0.95,
            needs_confirmation=False,
        )
        assert item_draft.name == "Organic Bananas"
        assert item_draft.qty == 2
        assert item_draft.confidence == 0.95

    def test_parsed_list_creation(self):
        items = [
            models.ItemDraft(
                name="Milk",
                qty=1,
                confidence=0.99,
                needs_confirmation=False,
            ),
            models.ItemDraft(
                name="Bread",
                qty=2,
                confidence=0.85,
                needs_confirmation=True,
            ),
        ]
        parsed_list = models.ParsedList(
            source=models.ParseSource.TEXT,
            items=items,
        )
        assert len(parsed_list.items) == 2
        assert parsed_list.source == models.ParseSource.TEXT

    def test_receipt_split_validation(self):
        """Test that ReceiptSplit validates totals."""
        lines = [
            models.ReceiptLine(
                line_no=1,
                description="Bananas",
                normalized_name="bananas",
                line_total=Decimal("2.50"),
                confidence=0.95,
            ),
            models.ReceiptLine(
                line_no=2,
                description="Milk",
                normalized_name="milk",
                line_total=Decimal("3.50"),
                confidence=0.95,
            ),
        ]

        receipt = models.ReceiptSplit(
            store="Trader Joe's",
            lines=lines,
            subtotal=Decimal("6.00"),
            tax=Decimal("0.50"),
            total=Decimal("6.50"),
        )

        assert receipt.subtotal == Decimal("6.00")
        assert receipt.total == Decimal("6.50")

    def test_receipt_split_reconciliation_fails(self):
        """Test that ReceiptSplit rejects mismatched totals."""
        lines = [
            models.ReceiptLine(
                line_no=1,
                description="Bananas",
                normalized_name="bananas",
                line_total=Decimal("2.50"),
                confidence=0.95,
            ),
        ]

        with pytest.raises(ValueError, match="lines != subtotal"):
            models.ReceiptSplit(
                store="Trader Joe's",
                lines=lines,
                subtotal=Decimal("10.00"),  # Mismatch!
                tax=Decimal("0.50"),
                total=Decimal("10.50"),
            )


class TestSerialization:
    """Test JSON serialization/deserialization."""

    def test_user_serialize_deserialize(self):
        user = models.User(
            circle_id=uuid4(),
            name="Alice",
        )

        # Serialize to dict
        user_dict = user.model_dump(mode="json")
        assert "id" in user_dict
        assert user_dict["name"] == "Alice"

        # Deserialize back
        user2 = models.User(**user_dict)
        assert user2.name == user.name
        assert str(user2.id) == str(user.id)

    def test_decimal_serialization(self):
        """Test that Decimal fields serialize as strings."""
        item = models.Item(
            request_id=uuid4(),
            trip_id=uuid4(),
            name="Milk",
            max_price=Decimal("3.99"),
        )

        item_dict = item.model_dump(mode="json")
        assert isinstance(item_dict["max_price"], str)
        assert item_dict["max_price"] == "3.99"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
