"""Canonical demo cast - single source of truth for demo characters and circles."""

from uuid import UUID, uuid5, NAMESPACE_DNS
from dataclasses import dataclass

# Generate stable UUIDs using UUID v5 (deterministic from name)
# This ensures the same UUIDs are generated every time from the same names
DEMO_NAMESPACE = uuid5(NAMESPACE_DNS, "favorly.demo")


def make_stable_uuid(name: str) -> UUID:
    """Generate a stable UUID v5 for a character or circle name."""
    return uuid5(DEMO_NAMESPACE, name)


# ============================================================================
# CIRCLE
# ============================================================================

DEMO_CIRCLE_ID = make_stable_uuid("demo-circle-1")
DEMO_INVITE_CODE = "MAPLE7"  # Single source of truth for invite code


@dataclass
class DemoCircle:
    """Demo circle metadata."""
    id: str
    name: str
    invite_code: str


DEMO_CIRCLE = DemoCircle(
    id=str(DEMO_CIRCLE_ID),
    name="Demo Building",
    invite_code=DEMO_INVITE_CODE,
)


# ============================================================================
# CHARACTERS
# ============================================================================

@dataclass
class DemoCharacter:
    """Demo character metadata."""
    id: str
    name: str
    email: str
    role: str  # "shopper", "requester"
    venmo_handle: str


# Character IDs (stable UUIDs)
ANA_ID = make_stable_uuid("ana-delgado")
BEN_ID = make_stable_uuid("ben-okafor")
CHLOE_ID = make_stable_uuid("chloe-marchetti")
MAYA_ID = make_stable_uuid("maya-iyer")

# Characters with realistic names and emails
ANA = DemoCharacter(
    id=str(ANA_ID),
    name="Ana Delgado",
    email="ana@favorly.test",
    role="shopper",
    venmo_handle="ana-delgado",
)

BEN = DemoCharacter(
    id=str(BEN_ID),
    name="Ben Okafor",
    email="ben@favorly.test",
    role="requester",
    venmo_handle="ben-okafor",
)

CHLOE = DemoCharacter(
    id=str(CHLOE_ID),
    name="Chloe Marchetti",
    email="chloe@favorly.test",
    role="requester",
    venmo_handle="chloe-m",
)

MAYA = DemoCharacter(
    id=str(MAYA_ID),
    name="Maya Iyer",
    email="maya@favorly.test",
    role="requester",
    venmo_handle="maya-iyer",
)

# All characters in order (shopper first, then requesters)
ALL_CHARACTERS = [ANA, BEN, CHLOE, MAYA]

# Requesters (excludes shopper for request generation)
REQUESTERS = [BEN, CHLOE, MAYA]


# ============================================================================
# REALISTIC GROCERY DATA
# ============================================================================

@dataclass
class GroceryItem:
    """Item for realistic seed data."""
    name: str
    section: str
    price: float


# Realistic Trader Joe's items with actual prices
REALISTIC_ITEMS = [
    # Produce
    GroceryItem("Bananas", "produce", 0.59),
    GroceryItem("Organic Spinach", "produce", 3.99),
    GroceryItem("Baby Carrots", "produce", 1.49),
    GroceryItem("Cherry Tomatoes", "produce", 3.99),
    GroceryItem("Red Bell Pepper", "produce", 2.49),

    # Dairy
    GroceryItem("Oat Milk", "dairy", 3.49),
    GroceryItem("Greek Yogurt", "dairy", 2.99),
    GroceryItem("Cheddar Cheese", "dairy", 4.99),
    GroceryItem("Organic Eggs", "dairy", 3.99),
    GroceryItem("Butter", "dairy", 4.49),

    # Proteins
    GroceryItem("Salmon Fillet", "frozen", 9.99),
    GroceryItem("Chicken Breast", "frozen", 7.99),
    GroceryItem("Lean Ground Beef", "frozen", 8.49),
    GroceryItem("Tofu", "refrigerated", 2.49),

    # Pantry
    GroceryItem("Organic Whole Wheat Pasta", "pantry", 1.99),
    GroceryItem("Brown Rice", "pantry", 3.49),
    GroceryItem("Peanut Butter", "pantry", 3.99),
    GroceryItem("Olive Oil", "pantry", 7.99),
    GroceryItem("Almond Flour", "pantry", 5.99),

    # Snacks
    GroceryItem("Organic Granola", "snacks", 4.49),
    GroceryItem("Dark Chocolate Almonds", "snacks", 3.99),
    GroceryItem("Tortilla Chips", "snacks", 2.49),

    # Beverages
    GroceryItem("Organic Coffee", "beverages", 5.99),
    GroceryItem("Green Tea", "beverages", 3.49),
    GroceryItem("Sparkling Water", "beverages", 3.49),

    # Frozen
    GroceryItem("Frozen Broccoli", "frozen", 2.49),
    GroceryItem("Frozen Berries", "frozen", 4.99),
    GroceryItem("Frozen Pizza", "frozen", 5.99),

    # Condiments
    GroceryItem("Organic Tomato Sauce", "pantry", 2.49),
    GroceryItem("Soy Sauce", "pantry", 3.99),
    GroceryItem("Hot Sauce", "pantry", 2.99),
]
