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
    role: str  # "shopper", "requester", or "both"
    venmo_handle: str
    bio: str = ""
    dietary: list = None
    preferred_stores: list = None
    availability: list = None
    address_unit: str = None
    address_floor: str = None
    address_buzzer: str = None
    address_notes: str = None
    address_lat: float = None
    address_lng: float = None

    def __post_init__(self):
        if self.dietary is None:
            self.dietary = []
        if self.preferred_stores is None:
            self.preferred_stores = []
        if self.availability is None:
            self.availability = []


# Character IDs (stable UUIDs)
ANA_ID = make_stable_uuid("ana-delgado")
BEN_ID = make_stable_uuid("ben-okafor")
CHLOE_ID = make_stable_uuid("chloe-marchetti")
MAYA_ID = make_stable_uuid("maya-iyer")

# Characters with realistic names, emails, and profiles
# Cambridge, MA coordinates (all in the Harvard Square area)
ANA = DemoCharacter(
    id=str(ANA_ID),
    name="Ana Delgado",
    email="ana@favorly.test",
    role="both",
    venmo_handle="ana-delgado",
    bio="Weekday runner to Trader Joe's. Regular at produce section.",
    dietary=["vegetarian"],
    preferred_stores=["Trader Joe's", "Whole Foods"],
    availability=["Mon", "Wed", "Fri", "Sat"],
    address_unit="3B",
    address_floor="3",
    address_buzzer="#123",
    address_notes="Leave with doorman",
    address_lat=42.3736,
    address_lng=-71.1190,
)

BEN = DemoCharacter(
    id=str(BEN_ID),
    name="Ben Okafor",
    email="ben@favorly.test",
    role="requester",
    venmo_handle="ben-okafor",
    bio="Works from home, flexible timing for deliveries.",
    dietary=["gluten-free", "dairy-free"],
    preferred_stores=["Trader Joe's", "Costco"],
    availability=["Mon", "Tue", "Wed", "Thu", "Fri"],
    address_unit="5A",
    address_floor="5",
    address_buzzer="Apt 5A",
    address_lat=42.3750,
    address_lng=-71.1150,
)

CHLOE = DemoCharacter(
    id=str(CHLOE_ID),
    name="Chloe Marchetti",
    email="chloe@favorly.test",
    role="both",
    venmo_handle="chloe-m",
    bio="Saturday shopper. Always looking for deals on fresh produce.",
    dietary=["vegan"],
    preferred_stores=["Whole Foods", "Trader Joe's"],
    availability=["Sat", "Sun"],
    address_unit="2C",
    address_floor="2",
    address_buzzer="Ring bell twice",
    address_notes="Building has gate, buzzer under maintenance",
    address_lat=42.3720,
    address_lng=-71.1210,
)

MAYA = DemoCharacter(
    id=str(MAYA_ID),
    name="Maya Iyer",
    email="maya@favorly.test",
    role="shopper",
    venmo_handle="maya-iyer",
    bio="Frequent Costco shopper. Bulk buy specialist.",
    dietary=["nut-free"],
    preferred_stores=["Costco", "Safeway"],
    availability=["Tue", "Thu", "Sat", "Sun"],
    address_unit="7F",
    address_floor="7",
    address_buzzer="#789",
    address_notes="Leave at reception desk",
    address_lat=42.3770,
    address_lng=-71.1170,
)

# ============================================================================
# v2 BLOCK CAST -- the 16-person building for the any-favor demo.
# The canonical four above keep their ids; the rest get stable ids too, but
# the v2 seeder adopts a pre-existing users row by exact name when one exists
# (the shared database predates this cast), so ids in the DB may differ.
# ============================================================================


def _block_char(name: str, unit: str, floor: str, availability: list[str],
                email: str, role: str = "both") -> DemoCharacter:
    return DemoCharacter(
        id=str(make_stable_uuid(name.lower().replace(" ", "-"))),
        name=name, email=email, role=role,
        venmo_handle=name.lower().replace(" ", "-"),
        availability=availability, address_unit=unit, address_floor=floor,
    )


MARCUS = _block_char("Marcus Hill", "6C", "6", ["Sat", "Sun"], "marcus.hill@favorly.test")
ELENA = _block_char("Elena Vasquez", "3D", "3", ["Mon", "Tue", "Wed", "Thu", "Fri"], "elena.vasquez@favorly.test")
JORDAN = _block_char("Jordan Reyes", "2A", "2", ["Sat", "Sun"], "jordan.reyes@favorly.test")
NORA = _block_char("Nora Chen", "4B", "4", ["Mon", "Tue", "Wed", "Thu", "Fri"], "nora.chen@favorly.test")
SAM = _block_char("Sam Okonkwo", "5C", "5", ["every day"], "sam.okonkwo@favorly.test")
PRIYA = _block_char("Priya Raman", "4D", "4", ["evenings"], "priya.raman@favorly.test")
GRACE = _block_char("Grace Adebayo", "1A", "1", ["every day"], "grace.adebayo@favorly.test")
DEV = _block_char("Dev Patel", "2D", "2", ["Sat", "Sun"], "dev.patel@favorly.test")
TOM = _block_char("Tom Becker", "7A", "7", ["every day"], "tom.becker@favorly.test")
LINA = _block_char("Lina Haddad", "6A", "6", ["evenings"], "lina.haddad@favorly.test")
NOAH = _block_char("Noah Kim", "1C", "1", ["Mon", "Tue", "Wed", "Thu", "Fri"], "noah.kim@favorly.test")

# Units/floors for the canonical four in the block (kept from their profiles).
for _c, _unit, _floor in ((ANA, "3B", "3"), (BEN, "5A", "5"), (CHLOE, "2C", "2"), (MAYA, "7F", "7")):
    _c.address_unit, _c.address_floor = _unit, _floor

# 15 fixed residents; the 16th is the presenter, added by the seeder under
# their real name (env DEMO_ASKER_NAME, unit 3C / floor 3).
BLOCK_CHARACTERS = [
    MARCUS, ELENA, JORDAN, NORA, SAM, PRIYA, GRACE, DEV, TOM, LINA, NOAH,
    ANA, BEN, CHLOE, MAYA,
]

# All characters (canonical four first -- seed_demo depends on that order),
# then the rest of the v2 block.
ALL_CHARACTERS = [ANA, BEN, CHLOE, MAYA,
                  MARCUS, ELENA, JORDAN, NORA, SAM, PRIYA, GRACE, DEV, TOM, LINA, NOAH]

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
