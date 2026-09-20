import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/demo_cast.dart';
import '../models/models.dart';

final storeProvider =
    ChangeNotifierProvider<DemoStore>((ref) => DemoStore.seeded());

/// Which root tab is showing. Deep screens use it to land people on the
/// ledger after a handoff.
final tabProvider = StateProvider<int>((ref) => 0);

/// Named positions in [RootShell]'s tab bar. Screens that jump between tabs
/// use these rather than a bare number: inserting a tab has silently sent
/// people to the wrong screen before.
abstract final class FTab {
  static const trips = 0;
  static const circle = 1;
  static const web = 2;
  static const you = 3;
}

class TripDraft {
  const TripDraft({
    required this.store,
    required this.departAt,
    required this.caps,
  });

  final String store;
  final DateTime departAt;
  final TripCaps caps;
}

double _round(double v) => (v * 100).roundToDouble() / 100;

/// In-memory stand-in for the FastAPI + Supabase backend.
///
/// Every mutation maps to one route in `backend/app.py`; the comment above
/// each method names it, so wiring the real API is a one-for-one swap.
class DemoStore extends ChangeNotifier {
  DemoStore.seeded() {
    _seed();
  }

  // Canonical demo cast - matches backend/seed/cast.py
  static const inviteCode = DEMO_INVITE_CODE;
  static const circleName = DEMO_CIRCLE_NAME;
  static const substitutionWindow = Duration(minutes: 3);

  final members = <Member>[];
  final trips = <Trip>[];
  final receipts = <String, ReceiptSplit>{};
  final settlements = <String, List<Settlement>>{};
  final ledger = <String, LedgerRow>{};
  final experiences = <String, ExperienceRating>{}; // tripId -> ratings map, keyed by "tripId:ratedById:ratedId"

  String _meId = ANA_ID;
  bool joined = true;
  bool notificationsOn = true;
  SubstitutionPrompt? pendingPrompt;
  String? lastCompletedTripId;
  int _seq = 0;

  String _id(String prefix) => '${prefix}_${++_seq}';

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Member get me => memberById(_meId);
  String get meId => _meId;
  Member memberById(String id) => members.firstWhere((m) => m.id == id);
  Trip tripById(String id) => trips.firstWhere((t) => t.id == id);

  List<Trip> get _byDeparture =>
      [...trips]..sort((a, b) => a.departAt.compareTo(b.departAt));

  /// The trip that deserves the hero card: anything in progress first, then
  /// the next open trip.
  Trip? get activeTrip {
    final live = _byDeparture.where((t) => t.isLive).toList();
    if (live.isEmpty) return null;
    live.sort((a, b) {
      final ra = a.status == TripStatus.open ? 1 : 0;
      final rb = b.status == TripStatus.open ? 1 : 0;
      return ra != rb ? ra - rb : a.departAt.compareTo(b.departAt);
    });
    return live.first;
  }

  List<Trip> get upcomingTrips {
    final active = activeTrip;
    return _byDeparture.where((t) => t.isLive && t.id != active?.id).toList();
  }

  List<Trip> get recentTrips =>
      _byDeparture.where((t) => !t.isLive).toList().reversed.toList();

  bool isShopper(Trip t) => t.shopperId == _meId;

  TripRequest? requestFor(Trip t, String memberId) {
    for (final r in t.requests) {
      if (r.requesterId == memberId) return r;
    }
    return null;
  }

  TripRequest? myRequest(Trip t) => requestFor(t, _meId);

  int spotsLeft(Trip t) =>
      math.max(0, t.caps.maxRequesters - t.requests.length);

  List<LedgerRow> get ledgerRows => ledger.values.toList()
    ..sort((a, b) => b.tripsRun != a.tripsRun
        ? b.tripsRun.compareTo(a.tripsRun)
        : b.dollarsCarried.compareTo(a.dollarsCarried));

  SubstitutionPrompt? get promptForMe {
    final p = pendingPrompt;
    return p != null && p.requesterId == _meId ? p : null;
  }

  ReceiptSplit? receiptFor(String tripId) => receipts[tripId];

  List<Settlement> settlementsFor(String tripId) =>
      settlements[tripId] ?? const [];

  Settlement? settlementFor(String tripId, String memberId) {
    for (final s in settlementsFor(tripId)) {
      if (s.requesterId == memberId) return s;
    }
    return null;
  }

  TripItem itemById(String tripId, String itemId) => tripById(tripId)
      .requests
      .expand((r) => r.items)
      .firstWhere((i) => i.id == itemId);

  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  // POST /circles/join
  bool join({required String name, required String code}) {
    if (code.trim().toUpperCase() != inviteCode) return false;
    final trimmed = name.trim();
    Member? existing;
    for (final m in members) {
      if (m.name.toLowerCase() == trimmed.toLowerCase() ||
          m.firstName.toLowerCase() == trimmed.toLowerCase()) {
        existing = m;
        break;
      }
    }
    if (existing != null) {
      _meId = existing.id;
    } else {
      final id = _id('member');
      members.add(Member(
        id: id,
        name: trimmed,
        venmoHandle:
            trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
        tint: MemberTint.values[members.length % MemberTint.values.length],
      ));
      ledger[id] = LedgerRow(
        memberId: id,
        tripsRun: 0,
        favorsReceived: 0,
        dollarsCarried: 0,
      );
      _meId = id;
    }
    joined = true;
    notifyListeners();
    return true;
  }

  void signOut() {
    joined = false;
    notifyListeners();
  }

  /// Demo only: look at the circle through another neighbor's eyes.
  void viewAs(String memberId) {
    if (memberId == _meId) return;
    _meId = memberId;
    notifyListeners();
  }

  void updateVenmo(String handle) {
    final i = members.indexWhere((m) => m.id == _meId);
    members[i] = members[i]
        .copyWith(venmoHandle: handle.trim().replaceFirst('@', ''));
    notifyListeners();
  }

  void updateProfile({
    String? photoPath,
    String? bio,
    MemberAddress? address,
    List<String>? dietary,
    List<String>? stores,
    List<String>? availability,
    ShopperRole? role,
  }) {
    final i = members.indexWhere((m) => m.id == _meId);
    members[i] = members[i].copyWith(
      photoPath: photoPath,
      bio: bio,
      address: address,
      dietary: dietary,
      stores: stores,
      availability: availability,
      role: role,
    );
    notifyListeners();
  }

  void setNotifications(bool on) {
    notificationsOn = on;
    notifyListeners();
  }

  void resetDemo() {
    _seed();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Trips
  // ---------------------------------------------------------------------------

  // POST /trips
  Trip postTrip({
    required String store,
    required DateTime departAt,
    required TripCaps caps,
  }) {
    final trip = Trip(
      id: _id('trip'),
      shopperId: _meId,
      circleId: DEMO_CIRCLE_ID,
      store: store.trim(),
      departAt: departAt,
      caps: caps,
    );
    trips.add(trip);
    notifyListeners();
    return trip;
  }

  static const voiceTripTranscript =
      '“I’m going to Trader Joe’s at three. Max five people, forty bucks each.”';

  // POST /parses source=voice, then the TripDraft parse. Canned for the demo.
  TripDraft tripDraftFromVoice() => TripDraft(
        store: "Trader Joe's",
        departAt: todayAt(15, 0),
        caps: const TripCaps(
          maxRequesters: 5,
          maxDollarsPerPerson: 40,
          maxItemsPerPerson: 8,
        ),
      );

  static DateTime todayAt(int hour, int minute) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, hour, minute);
  }

  // PATCH /trips/{id}/status shopping
  void startShopping(String tripId) {
    final t = tripById(tripId);
    if (t.status != TripStatus.open) return;
    _replaceTrip(t.copyWith(status: TripStatus.shopping));
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Request intake (AI surface #1)
  // ---------------------------------------------------------------------------

  static const handwrittenLines = [
    'Bananas',
    'Oat milk',
    'Sourdough',
    'Unsalted butter',
    'Lemons  2',
  ];

  static const handwrittenDrafts = [
    ItemDraft(name: 'Bananas', unit: 'bunch', maxPrice: 4),
    ItemDraft(name: 'Oat milk', maxPrice: 5),
    ItemDraft(name: 'Sourdough', unit: 'loaf', maxPrice: 6),
    ItemDraft(name: 'Unsalted butter', maxPrice: 6),
    ItemDraft(
      name: 'Lemons',
      qty: 2,
      maxPrice: 6,
      needsConfirmation: true,
      hint: 'Read “2”, but it could be a 4',
    ),
  ];

  static const voiceListTranscript =
      '“Bananas, a carton of oat milk, a sourdough loaf, unsalted butter, '
      'and two lemons. Nothing over six bucks each.”';

  static List<ItemDraft> get voiceDrafts => [
        for (final d in handwrittenDrafts)
          d.copyWith(
            maxPrice: 6.0,
            needsConfirmation: d.name == 'Lemons',
            hint: d.name == 'Lemons' ? 'Heard “two”. Double-check the count' : null,
          ),
      ];

  // POST /parses (text | photo | voice)
  List<ItemDraft> drafts(IntakeSource source, {String text = ''}) =>
      switch (source) {
        IntakeSource.text => parseText(text),
        IntakeSource.photo => List.of(handwrittenDrafts),
        IntakeSource.voice => voiceDrafts,
      };

  static const _numberWords = {
    'a': 1,
    'an': 1,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'dozen': 12,
    'a dozen': 12,
  };

  static const _units = [
    'bunch', 'loaf', 'loaves', 'carton', 'bag', 'box', 'pack', 'bottle',
    'can', 'jar', 'lb', 'lbs', 'pound', 'pounds', 'gallon', 'quart', 'pint',
    'head', 'bar', 'dozen',
  ];

  /// Deterministic text parse. The real app sends the text to the VLM; this
  /// keeps the typed path working offline.
  List<ItemDraft> parseText(String raw) {
    final fragments = raw
        .split(RegExp(r'[\n,;]+|\s+and\s+|\s+&\s+', caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return fragments.map(_draftFromFragment).toList();
  }

  ItemDraft _draftFromFragment(String fragment) {
    var text = fragment.replaceAll(RegExp(r'^[-•*]+\s*'), '').trim();
    final flagged = text.contains('?');
    text = text.replaceAll('?', '').trim();
    var qty = 1;
    String? unit;
    String? note;
    double? maxPrice;

    final paren = RegExp(r'\(([^)]+)\)').firstMatch(text);
    if (paren != null) {
      note = paren.group(1)!.trim();
      text = text.replaceFirst(paren.group(0)!, '').trim();
    }

    final price = RegExp(
      r'(?:under|max|up to|no more than|<)?\s*\$\s*(\d+(?:\.\d{1,2})?)\s*(?:max|each|tops)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (price != null) {
      maxPrice = double.tryParse(price.group(1)!);
      text = text.replaceFirst(price.group(0)!, '').trim();
    }

    final lead = RegExp(r'^(\d+)\s*[xX]?\s+(.+)$').firstMatch(text);
    if (lead != null) {
      qty = int.parse(lead.group(1)!);
      text = lead.group(2)!;
    } else {
      final word = RegExp(
        r'^(a dozen|dozen|one|two|three|four|five|six|an|a)\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(text);
      if (word != null) {
        qty = _numberWords[word.group(1)!.toLowerCase()] ?? 1;
        text = word.group(2)!;
      } else {
        final trail = RegExp(r'^(.+?)\s*(?:[xX]\s*(\d+)|\s(\d+))$').firstMatch(text);
        if (trail != null) {
          qty = int.parse((trail.group(2) ?? trail.group(3))!);
          text = trail.group(1)!;
        }
      }
    }

    final unitPattern = _units.join('|');
    final unitLead = RegExp('^($unitPattern)\\s+of\\s+(.+)\$', caseSensitive: false)
        .firstMatch(text);
    if (unitLead != null) {
      unit = unitLead.group(1)!.toLowerCase();
      text = unitLead.group(2)!;
    } else {
      final unitTrail =
          RegExp('^(.+?)\\s+($unitPattern)\$', caseSensitive: false).firstMatch(text);
      if (unitTrail != null) {
        unit = unitTrail.group(2)!.toLowerCase();
        text = unitTrail.group(1)!;
      }
    }

    final dash = RegExp(r'^(.+?)\s*[-–:]\s*(.+)$').firstMatch(text);
    if (dash != null) {
      text = dash.group(1)!;
      note ??= dash.group(2)!.trim();
    }

    text = text.trim();
    final name = text.isEmpty
        ? fragment
        : text[0].toUpperCase() + text.substring(1);
    final ambiguous = flagged || name.length < 3;
    return ItemDraft(
      name: name,
      qty: qty,
      unit: unit,
      note: note,
      maxPrice: maxPrice,
      needsConfirmation: ambiguous,
      hint: !ambiguous
          ? null
          : flagged
              ? 'You marked this with a question mark'
              : 'Too short to be sure what it is',
    );
  }

  double estimatedMax(Iterable<ItemDraft> drafts) => _round(drafts.fold(
        0.0,
        (sum, d) => sum + (d.maxPrice ?? unitPriceFor(d.name) * d.qty),
      ));

  // PATCH /parses/{id}/confirm, then POST /trips/{id}/requests
  TripRequest attachRequest(String tripId, List<ItemDraft> drafts) {
    final trip = tripById(tripId);
    final items = [
      for (final d in drafts)
        TripItem(
          id: _id('item'),
          requesterId: _meId,
          name: d.name,
          qty: d.qty,
          unit: d.unit,
          note: d.note,
          maxPrice: d.maxPrice,
          section: sectionFor(d.name),
        ),
    ];
    final existing = requestFor(trip, _meId);
    final request = existing == null
        ? TripRequest(id: _id('req'), requesterId: _meId, items: items)
        : existing.copyWith(items: items);
    final requests = existing == null
        ? [...trip.requests, request]
        : [for (final r in trip.requests) r.id == request.id ? request : r];
    _replaceTrip(trip.copyWith(requests: requests));
    notifyListeners();
    return request;
  }

  // PATCH /requests/{id} accept | decline
  void setTaking(String tripId, String requestId, bool taking) {
    final trip = tripById(tripId);
    _replaceTrip(trip.copyWith(requests: [
      for (final r in trip.requests)
        r.id == requestId ? r.copyWith(taking: taking) : r,
    ]));
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Shopping
  // ---------------------------------------------------------------------------

  // PATCH /items/{id}
  void toggleGot(String tripId, String itemId) {
    _updateItem(
      tripId,
      itemId,
      (i) => i.copyWith(
        status: i.status == ItemStatus.got ? ItemStatus.pending : ItemStatus.got,
      ),
    );
    notifyListeners();
  }

  void skipItem(String tripId, String itemId) {
    _updateItem(tripId, itemId, (i) => i.copyWith(status: ItemStatus.skipped));
    notifyListeners();
  }

  void skipRemaining(String tripId) {
    for (final item in tripById(tripId).items) {
      if (item.isOpen) {
        _updateItem(tripId, item.id, (i) => i.copyWith(status: ItemStatus.skipped));
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Substitution (AI surface #2)
  // ---------------------------------------------------------------------------

  // POST /items/{id}/substitution: shelf photo in, prompt out
  SubstitutionPrompt askForSubstitute(String tripId, String itemId) {
    final item = itemById(tripId, itemId);
    final prompt = SubstitutionPrompt(
      id: _id('sub'),
      tripId: tripId,
      itemId: itemId,
      requesterId: item.requesterId,
      originalName: item.name,
      maxPrice: item.maxPrice,
      candidates: candidatesFor(item),
      expiresAt: DateTime.now().add(substitutionWindow),
    );
    pendingPrompt = prompt;
    notifyListeners();
    return prompt;
  }

  // PATCH /substitutions/{id}: choose, skip, or timeout_skip
  void resolveSubstitution(String promptId, {int? chosenIndex}) {
    final p = pendingPrompt;
    if (p == null || p.id != promptId) return;
    if (chosenIndex == null) {
      _updateItem(p.tripId, p.itemId, (i) => i.copyWith(status: ItemStatus.skipped));
    } else {
      final c = p.candidates[chosenIndex];
      _updateItem(
        p.tripId,
        p.itemId,
        (i) => i.copyWith(
          status: ItemStatus.substituted,
          substituteName: c.name,
          substitutePrice: c.price,
        ),
      );
    }
    pendingPrompt = null;
    notifyListeners();
  }

  static List<ShelfCandidate> candidatesFor(TripItem item) {
    final n = item.name.toLowerCase();
    if (n.contains('butter')) {
      return const [
        ShelfCandidate(
          name: 'Irish unsalted butter',
          size: '8 oz',
          price: 4.49,
          reason: 'Unsalted and within your limit',
        ),
        ShelfCandidate(
          name: 'European-style butter',
          size: '8 oz',
          price: 5.29,
          reason: 'Unsalted, a little pricier',
        ),
        ShelfCandidate(
          name: 'Store-brand unsalted',
          size: '16 oz',
          price: 5.99,
          reason: 'Bigger pack, still under your cap',
        ),
      ];
    }
    if (n.contains('milk')) {
      return const [
        ShelfCandidate(
          name: 'Oat milk, barista blend',
          size: '32 oz',
          price: 4.49,
          reason: 'Same brand, creamier',
        ),
        ShelfCandidate(
          name: 'Almond milk, unsweetened',
          size: '32 oz',
          price: 3.29,
          reason: 'Different base, cheaper',
        ),
        ShelfCandidate(
          name: 'Organic whole milk',
          size: 'half gallon',
          price: 4.79,
          reason: 'Dairy, if that works for you',
        ),
      ];
    }
    if (n.contains('sourdough') || n.contains('bread')) {
      return const [
        ShelfCandidate(
          name: 'Country white loaf',
          size: '24 oz',
          price: 3.99,
          reason: 'Closest crust and crumb',
        ),
        ShelfCandidate(
          name: 'Whole wheat sourdough',
          size: '20 oz',
          price: 4.99,
          reason: 'Sourdough, wheat flour',
        ),
        ShelfCandidate(
          name: 'Ciabatta',
          size: '16 oz',
          price: 3.49,
          reason: 'Different shape, same use',
        ),
      ];
    }
    final base = unitPriceFor(item.name);
    final cap = item.maxPrice ?? base * 1.5;
    final lower = item.name.toLowerCase();
    return [
      ShelfCandidate(
        name: 'Store-brand $lower',
        size: 'standard',
        price: _round(base * 0.9),
        reason: 'Cheapest match on the shelf',
      ),
      ShelfCandidate(
        name: 'Organic $lower',
        size: 'standard',
        price: _round(math.min(cap, base * 1.25)),
        reason: 'Organic, near your cap',
      ),
      ShelfCandidate(
        name: '${item.name}, larger pack',
        size: 'family size',
        price: _round(base * 1.6),
        reason: 'More for the money',
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Receipt split (AI surface #3)
  // ---------------------------------------------------------------------------

  // POST /trips/{id}/receipt: image in, reconciled split out
  ReceiptSplit scanReceipt(String tripId) {
    final split = buildReceipt(tripId);
    receipts[tripId] = split;
    notifyListeners();
    return split;
  }

  /// Pure: what the receipt for this trip looks like right now. Used for the
  /// camera preview and by [scanReceipt].
  ReceiptSplit buildReceipt(String tripId) {
    final trip = tripById(tripId);
    final lines = <ReceiptLine>[];
    var n = 0;
    final requesterIds = [
      for (final r in trip.requests)
        if (r.taking) r.requesterId,
    ];
    for (final item in trip.items) {
      if (item.status != ItemStatus.got &&
          item.status != ItemStatus.substituted) {
        continue;
      }
      final substituted = item.status == ItemStatus.substituted;
      final price = substituted
          ? (item.substitutePrice ?? unitPriceFor(item.name))
          : _round(unitPriceFor(item.name) * item.qty);
      lines.add(ReceiptLine(
        lineNo: ++n,
        description: receiptLabel(item.displayName, qty: substituted ? 1 : item.qty),
        total: price,
        itemId: item.id,
        assignedTo: substituted ? null : item.requesterId,
        ambiguous: substituted,
        options: substituted ? [trip.shopperId, ...requesterIds] : const [],
      ));
    }
    for (final own in const [
      ('COFFEE BEANS 12OZ', 8.99),
      ('PIZZA MARGHERITA FRZ', 5.49),
    ]) {
      lines.add(ReceiptLine(
        lineNo: ++n,
        description: own.$1,
        total: own.$2,
        assignedTo: trip.shopperId,
      ));
    }
    final subtotal = _round(lines.fold(0.0, (s, l) => s + l.total));
    final tax = _round(subtotal * 0.0325);
    return ReceiptSplit(
      store: trip.store,
      lines: lines,
      subtotal: subtotal,
      tax: tax,
      total: _round(subtotal + tax),
    );
  }

  // PATCH /receipts/{id}/assignments
  void assignLine(String tripId, int lineNo, String memberId) {
    final split = receipts[tripId]!;
    receipts[tripId] = split.copyWith(lines: [
      for (final l in split.lines)
        l.lineNo == lineNo ? l.copyWith(assignedTo: memberId) : l,
    ]);
    notifyListeners();
  }

  // Confirm assignments → settlements, PATCH /trips/{id}/status settling
  List<Settlement> confirmSplit(String tripId) {
    final trip = tripById(tripId);
    final split = receipts[tripId]!;
    final shopper = memberById(trip.shopperId);
    final result = <Settlement>[];
    for (final r in trip.requests.where((r) => r.taking)) {
      final mine =
          split.lines.where((l) => l.assignedTo == r.requesterId).toList();
      if (mine.isEmpty) continue;
      final subtotal = _round(mine.fold(0.0, (s, l) => s + l.total));
      final taxShare = _round(split.tax * subtotal / split.subtotal);
      final total = _round(subtotal + taxShare);
      final note = Uri.encodeComponent('Favorly · ${trip.store}');
      result.add(Settlement(
        id: _id('settle'),
        tripId: tripId,
        requesterId: r.requesterId,
        lines: [
          for (final l in mine)
            SettlementLine(description: _prettyLine(trip, l), amount: l.total),
        ],
        subtotal: subtotal,
        taxShare: taxShare,
        total: total,
        venmoLink:
            'https://venmo.com/${shopper.venmoHandle}?txn=pay&amount=${total.toStringAsFixed(2)}&note=$note',
      ));
    }
    settlements[tripId] = result;
    _replaceTrip(trip.copyWith(status: TripStatus.settling));
    notifyListeners();
    return result;
  }

  String _prettyLine(Trip trip, ReceiptLine l) {
    if (l.itemId == null) return l.description;
    final item = trip.items.firstWhere((i) => i.id == l.itemId);
    if (item.status == ItemStatus.substituted) {
      return '${item.substituteName} · swap';
    }
    return item.qty > 1 ? '${item.name} · ${item.qtyLabel}' : item.name;
  }

  // PATCH /settlements/{id}/paid
  void markPaid(String tripId, String settlementId) {
    settlements[tripId] = [
      for (final s in settlementsFor(tripId))
        s.id == settlementId ? s.copyWith(paid: true) : s,
    ];
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Handoff + ledger
  // ---------------------------------------------------------------------------

  // POST /trips/{id}/handoff
  void confirmHandoff(String tripId) {
    final trip = tripById(tripId);
    final carried = settlementsFor(tripId).fold(0.0, (s, x) => s + x.total);
    _bump(
      trip.shopperId,
      (r) => r.copyWith(
        tripsRun: r.tripsRun + 1,
        dollarsCarried: _round(r.dollarsCarried + carried),
      ),
    );
    for (final r in trip.requests.where((r) => r.taking)) {
      _bump(r.requesterId, (x) => x.copyWith(favorsReceived: x.favorsReceived + 1));
    }
    _replaceTrip(trip.copyWith(status: TripStatus.done));
    lastCompletedTripId = tripId;
    notifyListeners();
  }

  void dismissLedgerBanner() {
    if (lastCompletedTripId == null) return;
    lastCompletedTripId = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Experience ratings + matching algorithm
  // ---------------------------------------------------------------------------

  // POST /experiences
  ExperienceRating submitRating({
    required String tripId,
    required String ratedId,
    required int overallRating,
    int? reliabilityRating,
    int? accuracyRating,
    int? communicationRating,
    String? comment,
  }) {
    final rating = ExperienceRating(
      id: _id('exp'),
      tripId: tripId,
      ratedById: _meId,
      ratedId: ratedId,
      overallRating: overallRating,
      reliabilityRating: reliabilityRating,
      accuracyRating: accuracyRating,
      communicationRating: communicationRating,
      comment: comment,
      createdAt: DateTime.now(),
    );
    final key = '$tripId:$_meId:$ratedId';
    experiences[key] = rating;
    notifyListeners();
    return rating;
  }

  /// GET /experiences?ratedId={memberId}
  List<ExperienceRating> ratingsFor(String memberId) => experiences.values
      .where((e) => e.ratedId == memberId)
      .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// GET /experiences?ratedById={memberId}
  List<ExperienceRating> ratingsFrom(String memberId) => experiences.values
      .where((e) => e.ratedById == memberId)
      .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Compute compatibility score between two members (0.0 to 1.0).
  /// Factors: number of trips together, average rating given to each other,
  /// directional feedback balance.
  MemberCompatibility compatibilityScore(String id1, String id2) {
    final ratings1to2 =
        experiences.values.where((e) => e.ratedById == id1 && e.ratedId == id2).toList();
    final ratings2to1 =
        experiences.values.where((e) => e.ratedById == id2 && e.ratedId == id1).toList();

    final tripsWorked = {...ratings1to2.map((r) => r.tripId), ...ratings2to1.map((r) => r.tripId)}.length;

    if (tripsWorked == 0) {
      return MemberCompatibility(
        memberId1: id1,
        memberId2: id2,
        score: 0.0,
        tripsWorkedTogether: 0,
        averageRating: 0.0,
      );
    }

    final allRatings = [...ratings1to2, ...ratings2to1];
    final avgRating = allRatings.isEmpty
        ? 0.0
        : allRatings.fold(0.0, (sum, r) => sum + r.overallRating) / allRatings.length;

    // Score factor: frequency (max 0.6) + quality (max 0.4)
    // More trips = better, higher ratings = better
    final frequencyScore = math.min(tripsWorked / 3.0, 1.0) * 0.6;
    final qualityScore = (avgRating / 5.0) * 0.4;
    final score = frequencyScore + qualityScore;

    return MemberCompatibility(
      memberId1: id1,
      memberId2: id2,
      score: _round(score),
      tripsWorkedTogether: tripsWorked,
      averageRating: _round(avgRating),
    );
  }

  /// Recommend members who would be good trip partners for [memberId]
  /// based on past experience. Returns sorted by compatibility score.
  List<(Member, MemberCompatibility)> recommendedPartners(String memberId, {int limit = 3}) {
    final scores = <MemberCompatibility>[];
    for (final other in members) {
      if (other.id == memberId) continue;
      final compat = compatibilityScore(memberId, other.id);
      if (compat.tripsWorkedTogether > 0) {
        scores.add(compat);
      }
    }
    scores.sort((a, b) => b.score.compareTo(a.score));
    return [
      for (final score in scores.take(limit)) (memberById(score.memberId2), score),
    ];
  }

  // ---------------------------------------------------------------------------
  // Deterministic helpers (mirror backend/shared matching code)
  // ---------------------------------------------------------------------------

  static StoreSection sectionFor(String name) {
    final n = name.toLowerCase();
    bool has(List<String> words) => words.any(n.contains);
    if (has(const [
      'banana', 'lemon', 'apple', 'avocado', 'berr', 'tomato', 'onion',
      'garlic', 'lettuce', 'spinach', 'kale', 'cilantro', 'lime', 'orange',
      'grape', 'pepper', 'potato', 'carrot', 'cucumber', 'herb', 'salad',
    ])) {
      return StoreSection.produce;
    }
    if (has(const ['sourdough', 'bread', 'bagel', 'loaf', 'croissant', 'muffin', 'tortilla', 'bun'])) {
      return StoreSection.bakery;
    }
    if (has(const ['chicken', 'beef', 'pork', 'turkey', 'salmon', 'fish', 'shrimp', 'steak', 'sausage', 'bacon'])) {
      return StoreSection.meat;
    }
    if (has(const ['milk', 'butter', 'yogurt', 'cheese', 'egg', 'cream', 'kefir'])) {
      return StoreSection.dairy;
    }
    if (has(const ['frozen', 'dumpling', 'gyoza', 'ice cream', 'pizza', 'waffle'])) {
      return StoreSection.frozen;
    }
    if (has(const ['water', 'sparkling', 'juice', 'coffee', 'tea', 'soda', 'kombucha', 'beer', 'wine'])) {
      return StoreSection.beverages;
    }
    if (has(const ['paper towel', 'toilet', 'detergent', 'sponge', 'trash', 'foil', 'soap', 'dish'])) {
      return StoreSection.household;
    }
    if (has(const ['shampoo', 'toothpaste', 'deodorant', 'lotion', 'razor', 'floss', 'sunscreen'])) {
      return StoreSection.personalCare;
    }
    if (has(const [
      'chocolate', 'rice', 'pasta', 'bean', 'cereal', 'oat', 'granola',
      'peanut', 'almond', 'honey', 'oil', 'flour', 'sugar', 'salt', 'sauce',
      'chips', 'cracker', 'snack', 'nut', 'soup',
    ])) {
      return StoreSection.pantry;
    }
    return StoreSection.other;
  }

  static const _unitPrices = <String, double>{
    'banana': 2.31,
    'oat milk': 4.29,
    'sourdough': 4.49,
    'butter': 4.99,
    'lemon': 1.17,
    'dark chocolate': 3.99,
    'chocolate': 3.49,
    'sparkling': 2.99,
    'yogurt': 5.49,
    'dumpling': 4.99,
    'paper towel': 7.99,
    'egg': 4.49,
    'avocado': 1.29,
    'bread': 3.99,
    'milk': 3.79,
    'coffee': 8.99,
    'cheese': 5.99,
    'apple': 0.89,
    'chicken': 7.49,
    'rice': 4.99,
    'pasta': 1.99,
    'water': 2.99,
    'tomato': 2.49,
    'onion': 0.99,
    'spinach': 2.99,
    'juice': 3.99,
    'cereal': 3.99,
    'olive oil': 12.99,
    'almond': 9.99,
  };

  static double unitPriceFor(String name) {
    final n = name.toLowerCase();
    for (final e in _unitPrices.entries) {
      if (n.contains(e.key)) return e.value;
    }
    return 3.99;
  }

  static const _receiptNames = <String, String>{
    'banana': 'ORG BANANAS 1.79LB',
    'oat milk': 'OAT BEVERAGE 32OZ',
    'sourdough': 'SOURDOUGH LOAF',
    'irish unsalted butter': 'IRISH BUTTER UNSLTD 8OZ',
    'european-style butter': 'EURO STYLE BUTTER 8OZ',
    'store-brand unsalted': 'TJ UNSALTED BUTTER 16OZ',
    'butter': 'BUTTER UNSLTD 16OZ',
    'lemon': 'LEMONS',
    'dark chocolate': 'DK CHOC 72% BAR',
    'sparkling': 'SPARKLING WTR 1L',
    'yogurt': 'GREEK YOGURT PLAIN 32OZ',
    'dumpling': 'PORK GYOZA FRZ',
    'paper towel': 'PAPER TOWELS 2PK',
    'coffee': 'COFFEE BEANS 12OZ',
  };

  static String receiptLabel(String name, {int qty = 1}) {
    final n = name.toLowerCase();
    var label = name.toUpperCase();
    for (final e in _receiptNames.entries) {
      if (n.contains(e.key)) {
        label = e.value;
        break;
      }
    }
    return qty > 1
        ? '$label $qty @ ${unitPriceFor(name).toStringAsFixed(2)}'
        : label;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _replaceTrip(Trip trip) {
    final i = trips.indexWhere((t) => t.id == trip.id);
    trips[i] = trip;
  }

  void _updateItem(
    String tripId,
    String itemId,
    TripItem Function(TripItem) update,
  ) {
    final t = tripById(tripId);
    _replaceTrip(t.copyWith(requests: [
      for (final r in t.requests)
        r.copyWith(items: [
          for (final i in r.items) i.id == itemId ? update(i) : i,
        ]),
    ]));
  }

  void _bump(String memberId, LedgerRow Function(LedgerRow) update) {
    final row = ledger[memberId] ??
        LedgerRow(memberId: memberId, tripsRun: 0, favorsReceived: 0, dollarsCarried: 0);
    ledger[memberId] = update(row);
  }

  TripItem _item(
    String requesterId,
    String name, {
    int qty = 1,
    String? unit,
    String? note,
    double? maxPrice,
    ItemStatus status = ItemStatus.pending,
  }) =>
      TripItem(
        id: _id('item'),
        requesterId: requesterId,
        name: name,
        qty: qty,
        unit: unit,
        note: note,
        maxPrice: maxPrice,
        section: sectionFor(name),
        status: status,
      );

  void _seed() {
    _seq = 0;
    // Use canonical cast data from backend/seed/cast.py
    members
      ..clear()
      ..addAll([
        Member(id: ANA_ID, name: ANA_NAME, venmoHandle: ANA_VENMO, tint: MemberTint.blue),
        Member(id: BEN_ID, name: BEN_NAME, venmoHandle: BEN_VENMO, tint: MemberTint.green),
        Member(id: CHLOE_ID, name: CHLOE_NAME, venmoHandle: CHLOE_VENMO, tint: MemberTint.amber),
        Member(id: MAYA_ID, name: MAYA_NAME, venmoHandle: MAYA_VENMO, tint: MemberTint.plum),
      ]);
    _meId = ANA_ID;
    joined = true;
    notificationsOn = true;
    pendingPrompt = null;
    lastCompletedTripId = null;
    receipts.clear();
    settlements.clear();

    final now = DateTime.now();
    DateTime at(int dayOffset, int hour, int minute) =>
        DateTime(now.year, now.month, now.day + dayOffset, hour, minute);
    // The live trip always leaves a couple of hours from now, on the hour, so
    // the demo reads the same at 10 AM or 10 PM.
    final leaves = DateTime(now.year, now.month, now.day, now.hour).add(const Duration(hours: 2));
    var sinceSaturday = (now.weekday - DateTime.saturday) % 7;
    if (sinceSaturday == 0) sinceSaturday = 7;

    trips
      ..clear()
      ..addAll([
        Trip(
          id: 'trip_tj',
          shopperId: ANA_ID,
          circleId: DEMO_CIRCLE_ID,
          store: "Trader Joe's",
          departAt: leaves,
          caps: const TripCaps(maxRequesters: 5, maxDollarsPerPerson: 40, maxItemsPerPerson: 8),
          requests: [
            TripRequest(id: 'req_ben', requesterId: BEN_ID, items: [
              _item(BEN_ID, 'Oat Milk', maxPrice: 3.49),
              _item(BEN_ID, 'Dark Chocolate Almonds', note: '70% or darker', maxPrice: 3.99),
              _item(BEN_ID, 'Sparkling Water', qty: 2, maxPrice: 3.49),
            ]),
            TripRequest(id: 'req_maya', requesterId: MAYA_ID, items: [
              _item(MAYA_ID, 'Greek Yogurt', note: 'plain, full fat', maxPrice: 2.99),
              _item(MAYA_ID, 'Organic Coffee', maxPrice: 5.99),
              _item(MAYA_ID, 'Frozen Berries', maxPrice: 4.99),
            ]),
          ],
        ),
        Trip(
          id: 'trip_cvs',
          shopperId: MAYA_ID,
          circleId: DEMO_CIRCLE_ID,
          store: 'CVS',
          departAt: at(1, 10, 30),
          caps: const TripCaps(maxRequesters: 4, maxDollarsPerPerson: 25, maxItemsPerPerson: 5),
        ),
        Trip(
          id: 'trip_costco',
          shopperId: CHLOE_ID,
          circleId: DEMO_CIRCLE_ID,
          store: 'Costco',
          departAt: at(-sinceSaturday, 9, 0),
          status: TripStatus.done,
          caps: const TripCaps(maxRequesters: 6, maxDollarsPerPerson: 60, maxItemsPerPerson: 10),
          requests: [
            TripRequest(id: 'req_c_ana', requesterId: ANA_ID, items: [
              _item(ANA_ID, 'Olive Oil', maxPrice: 7.99, status: ItemStatus.got),
              _item(ANA_ID, 'Almond Flour', maxPrice: 5.99, status: ItemStatus.got),
            ]),
            TripRequest(id: 'req_c_ben', requesterId: BEN_ID, items: [
              _item(BEN_ID, 'Organic Whole Wheat Pasta', maxPrice: 1.99, status: ItemStatus.got),
              _item(BEN_ID, 'Organic Coffee', qty: 2, maxPrice: 5.99, status: ItemStatus.got),
            ]),
            TripRequest(id: 'req_c_maya', requesterId: MAYA_ID, items: [
              _item(MAYA_ID, 'Chicken Breast', maxPrice: 7.99, status: ItemStatus.got),
            ]),
          ],
        ),
      ]);

    ledger
      ..clear()
      ..addAll({
        ANA_ID: LedgerRow(memberId: ANA_ID, tripsRun: 3, favorsReceived: 1, dollarsCarried: 104.16),
        BEN_ID: LedgerRow(memberId: BEN_ID, tripsRun: 1, favorsReceived: 4, dollarsCarried: 31.40),
        CHLOE_ID: LedgerRow(memberId: CHLOE_ID, tripsRun: 2, favorsReceived: 3, dollarsCarried: 58.75),
        MAYA_ID: LedgerRow(memberId: MAYA_ID, tripsRun: 1, favorsReceived: 2, dollarsCarried: 22.10),
      });

    // Sample experience ratings for the completed Costco trip
    // Ana rates Ben and Maya
    experiences
      ..clear()
      ..addAll({
        'trip_costco:$ANA_ID:$BEN_ID': ExperienceRating(
          id: 'exp_1',
          tripId: 'trip_costco',
          ratedById: ANA_ID,
          ratedId: BEN_ID,
          overallRating: 5,
          reliabilityRating: 5,
          accuracyRating: 5,
          communicationRating: 4,
          comment: 'Ben is always reliable. Got everything right.',
          createdAt: now.subtract(const Duration(days: 5)),
        ),
        'trip_costco:$ANA_ID:$MAYA_ID': ExperienceRating(
          id: 'exp_2',
          tripId: 'trip_costco',
          ratedById: ANA_ID,
          ratedId: MAYA_ID,
          overallRating: 4,
          reliabilityRating: 5,
          accuracyRating: 4,
          communicationRating: 4,
          comment: 'Great communicator. One substitution was close.',
          createdAt: now.subtract(const Duration(days: 5)),
        ),
        // Ben rates Ana
        'trip_costco:$BEN_ID:$ANA_ID': ExperienceRating(
          id: 'exp_3',
          tripId: 'trip_costco',
          ratedById: BEN_ID,
          ratedId: ANA_ID,
          overallRating: 5,
          reliabilityRating: 5,
          accuracyRating: 5,
          communicationRating: 5,
          comment: 'Perfect trip. Ana is the best shopper in the building.',
          createdAt: now.subtract(const Duration(days: 5)),
        ),
        // Maya rates Ana
        'trip_costco:$MAYA_ID:$ANA_ID': ExperienceRating(
          id: 'exp_4',
          tripId: 'trip_costco',
          ratedById: MAYA_ID,
          ratedId: ANA_ID,
          overallRating: 5,
          reliabilityRating: 5,
          accuracyRating: 5,
          communicationRating: 5,
          comment: 'Amazing. She texted me updates the whole time.',
          createdAt: now.subtract(const Duration(days: 5)),
        ),
      });
  }
}
