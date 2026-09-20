import 'package:uuid/uuid.dart';

/// Canonical demo cast - single source of truth matching backend/seed/cast.py
/// Uses UUID v5 for deterministic stable UUIDs

const DEMO_NAMESPACE_URL = 'favorly.demo';

String _makeStableUuid(String name) {
  const uuid = Uuid();
  return uuid.v5(Uuid.NAMESPACE_DNS, name);
}

// ============================================================================
// CIRCLE
// ============================================================================

final DEMO_CIRCLE_ID = _makeStableUuid('demo-circle-1');
const DEMO_INVITE_CODE = 'MAPLE7';
const DEMO_CIRCLE_NAME = 'Demo Building';

// ============================================================================
// CHARACTERS
// ============================================================================

final ANA_ID = _makeStableUuid('ana-delgado');
final BEN_ID = _makeStableUuid('ben-okafor');
final CHLOE_ID = _makeStableUuid('chloe-marchetti');
final MAYA_ID = _makeStableUuid('maya-iyer');

const ANA_NAME = 'Ana Delgado';
const ANA_EMAIL = 'ana@favorly.test';
const ANA_VENMO = 'ana-delgado';

const BEN_NAME = 'Ben Okafor';
const BEN_EMAIL = 'ben@favorly.test';
const BEN_VENMO = 'ben-okafor';

const CHLOE_NAME = 'Chloe Marchetti';
const CHLOE_EMAIL = 'chloe@favorly.test';
const CHLOE_VENMO = 'chloe-m';

const MAYA_NAME = 'Maya Iyer';
const MAYA_EMAIL = 'maya@favorly.test';
const MAYA_VENMO = 'maya-iyer';

// All character IDs in order (for iteration)
List<String> get ALL_CHARACTER_IDS => [ANA_ID, BEN_ID, CHLOE_ID, MAYA_ID];

// Realistic grocery item prices (from backend/seed/cast.py REALISTIC_ITEMS)
const REALISTIC_ITEMS = {
  // Produce
  'Bananas': 0.59,
  'Organic Spinach': 3.99,
  'Baby Carrots': 1.49,
  'Cherry Tomatoes': 3.99,
  'Red Bell Pepper': 2.49,
  // Dairy
  'Oat Milk': 3.49,
  'Greek Yogurt': 2.99,
  'Cheddar Cheese': 4.99,
  'Organic Eggs': 3.99,
  'Butter': 4.49,
  // Proteins
  'Salmon Fillet': 9.99,
  'Chicken Breast': 7.99,
  'Lean Ground Beef': 8.49,
  'Tofu': 2.49,
  // Pantry
  'Organic Whole Wheat Pasta': 1.99,
  'Brown Rice': 3.49,
  'Peanut Butter': 3.99,
  'Olive Oil': 7.99,
  'Almond Flour': 5.99,
  // Snacks
  'Organic Granola': 4.49,
  'Dark Chocolate Almonds': 3.99,
  'Tortilla Chips': 2.49,
  // Beverages
  'Organic Coffee': 5.99,
  'Green Tea': 3.49,
  'Sparkling Water': 3.49,
  // Frozen
  'Frozen Broccoli': 2.49,
  'Frozen Berries': 4.99,
  'Frozen Pizza': 5.99,
  // Condiments
  'Organic Tomato Sauce': 2.49,
  'Soy Sauce': 3.99,
  'Hot Sauce': 2.99,
};
