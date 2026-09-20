import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/demo_cast.dart';
import '../models/demo_seed_data.dart';
import '../models/models.dart';
import '../models/savings_models.dart';
import '../models/insurance_models.dart';
import '../models/unlocks_models.dart';
import '../models/referrals_models.dart';

final storeProvider = ChangeNotifierProvider<DemoStore>(
  (ref) => DemoStore.seeded(),
);

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
  final experiences =
      <
        String,
        ExperienceRating
      >{}; // tripId -> ratings map, keyed by "tripId:ratedById:ratedId"
  final _pendingRequests = <List<ItemDraft>>[];

  String _meId = ANA_ID;
  bool joined = true;
  bool notificationsOn = true;
  SubstitutionPrompt? pendingPrompt;
  String? lastCompletedTripId;
  int _seq = 0;

  // Storm mode state
  bool stormModeActive = false;
  String? stormType;
  DateTime? stormExpiresAt;
  int stormKarmaMultiplier = 1;

  // Insurance eligibility state
  final insuranceStatuses = <String, InsuranceStatus>{};

  // Collective unlocks state
  final claimedUnlocks = <String>{}; // Set of claimed unlock types
  CircleUnlockStatus? _cachedUnlockStatus;

  // Referral state
  final referralRewards = <String, ReferralReward>{}; // userId -> rewards

  String _id(String prefix) => '${prefix}_${++_seq}';

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Member get me => memberById(_meId);
  String get meId => _meId;

  Member memberById(String id) {
    try {
      return members.firstWhere((m) => m.id == id);
    } catch (e) {
      // Fallback: return first member if not found (shouldn't happen in demo)
      if (members.isEmpty) {
        throw Exception('No members available in demo store');
      }
      debugPrint('⚠️ Member $id not found. Using first member as fallback.');
      return members.first;
    }
  }

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

  List<List<ItemDraft>> get pendingRequests =>
      List.unmodifiable(_pendingRequests);

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
    ..sort(
      (a, b) => b.tripsRun != a.tripsRun
          ? b.tripsRun.compareTo(a.tripsRun)
          : b.dollarsCarried.compareTo(a.dollarsCarried),
    );

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

  // ---------------------------------------------------------------------------
  // Savings Meter
  // ---------------------------------------------------------------------------

  /// Delivery app pricing benchmarks for savings computation.
  static const double _markupRate = 0.20; // 20% item markup
  static const double _deliveryFee = 5.99;
  static const double _serviceFeeRate = 0.08; // 8% service fee
  static const double _tipRate = 0.18; // 18% tip
  static const double _bulkSavingsRate = 0.12; // 12% bulk savings

  /// Compute requester savings for this month.
  PersonalSavings savingsFor(String memberId) {
    // Get all settlements for this member as requester from this month
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    double totalSubtotal = 0;
    double totalTax = 0;
    double totalPaid = 0;
    int tripsCount = 0;

    for (final tripSettlements in settlements.values) {
      for (final settlement in tripSettlements) {
        if (settlement.requesterId == memberId) {
          // Check if trip is recent (this month approximation)
          Trip? trip;
          try {
            trip = trips.firstWhere((t) => t.id == settlement.tripId);
          } catch (e) {
            trip = null;
          }
          if (trip != null && trip.departAt.isAfter(monthStart)) {
            totalSubtotal += settlement.subtotal;
            totalTax += settlement.taxShare;
            totalPaid += settlement.total;
            tripsCount++;
          }
        }
      }
    }

    // Compute delivery-app estimate
    double deliveryAppEstimate = 0;
    double feesAvoided = 0;

    if (totalSubtotal > 0) {
      final markup = totalSubtotal * _markupRate;
      final serviceFee = totalSubtotal * _serviceFeeRate;
      final tip = (totalSubtotal + totalTax) * _tipRate;

      deliveryAppEstimate =
          totalSubtotal + totalTax + markup + _deliveryFee + serviceFee + tip;
      feesAvoided = math.max(0, deliveryAppEstimate - totalPaid);
    }

    final requesterSavings = totalSubtotal > 0
        ? RequesterSavings(
            feesAvoidedThisMonth: _round(feesAvoided),
            feesAvoidedAllTime: _round(feesAvoided),
            tripsUsedThisMonth: tripsCount,
            deliveryAppEstimate: _round(deliveryAppEstimate),
            favorlyCost: _round(totalPaid),
          )
        : null;

    // Compute carrier savings
    final carrierLedger = ledger[memberId];
    final carrierTripsThisMonth = trips
        .where((t) => t.shopperId == memberId && t.status == TripStatus.done)
        .length;
    final tripsRun = carrierLedger?.tripsRun ?? 0;
    final dollarsCarried = carrierLedger?.dollarsCarried ?? 0;

    final perkValue = (tripsRun > 0 ? tripsRun : carrierTripsThisMonth) * 2.0;
    final bulkSavings = dollarsCarried * _bulkSavingsRate;

    final carrierSavings = (tripsRun > 0 || dollarsCarried > 0)
        ? CarrierSavings(
            perksEarnedThisMonth: _round(perkValue),
            bulkSavingsThisMonth: _round(bulkSavings),
            totalEarnedThisMonth: _round(perkValue + bulkSavings),
            tripsCarriedThisMonth: carrierTripsThisMonth > 0
                ? carrierTripsThisMonth
                : tripsRun,
          )
        : null;

    return PersonalSavings(
      requesterSavings: requesterSavings,
      carrierSavings: carrierSavings,
      hasRequesterData: requesterSavings != null,
      hasCarrierData: carrierSavings != null,
    );
  }

  TripItem itemById(String tripId, String itemId) =>
      tripById(tripId).requests
          .expand((r) => r.items)
          .firstWhere((i) => i.id == itemId);

  // ---------------------------------------------------------------------------
  // Storm Mode
  // ---------------------------------------------------------------------------

  /// Activate storm mode (demo trigger).
  void activateStormMode({String type = 'snowstorm'}) {
    stormModeActive = true;
    stormType = type;
    stormKarmaMultiplier = 2;
    stormExpiresAt = DateTime.now().add(const Duration(hours: 4));
    notifyListeners();
  }

  /// Deactivate storm mode.
  void deactivateStormMode() {
    stormModeActive = false;
    stormType = null;
    stormKarmaMultiplier = 1;
    stormExpiresAt = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Insurance Eligibility
  // ---------------------------------------------------------------------------

  /// Get insurance status for a member.
  InsuranceStatus insuranceFor(String memberId) {
    // Check if already computed
    if (insuranceStatuses.containsKey(memberId)) {
      return insuranceStatuses[memberId]!;
    }

    // Compute based on trips carried this month
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    final tripsCarried = trips
        .where(
          (t) =>
              t.shopperId == memberId &&
              t.status == TripStatus.done &&
              t.departAt.isAfter(monthStart),
        )
        .length;

    final status = InsuranceStatus(
      userId: memberId,
      active: tripsCarried >= 3,
      tripsCarriedThisMonth: tripsCarried,
      guaranteedThreshold: 3,
      expiresAt: tripsCarried >= 3 ? now.add(const Duration(days: 1)) : null,
    );

    insuranceStatuses[memberId] = status;
    return status;
  }

  /// Check if a member is insurance-eligible (3+ carries this month).
  bool isInsuranceEligible(String memberId) => insuranceFor(memberId).active;

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
      members.add(
        Member(
          id: id,
          name: trimmed,
          venmoHandle: trimmed.toLowerCase().replaceAll(
            RegExp(r'[^a-z0-9]+'),
            '-',
          ),
          tint: MemberTint.values[members.length % MemberTint.values.length],
        ),
      );
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
    members[i] = members[i].copyWith(
      venmoHandle: handle.trim().replaceFirst('@', ''),
    );
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
  // Pending Requests (trip-independent saves)
  // ---------------------------------------------------------------------------

  void savePendingRequest(List<ItemDraft> items) {
    _pendingRequests.add(items);
    notifyListeners();
  }

  void clearPendingRequests() {
    _pendingRequests.clear();
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
    'bunch',
    'loaf',
    'loaves',
    'carton',
    'bag',
    'box',
    'pack',
    'bottle',
    'can',
    'jar',
    'lb',
    'lbs',
    'pound',
    'pounds',
    'gallon',
    'quart',
    'pint',
    'head',
    'bar',
    'dozen',
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
        final trail = RegExp(r'^(.+?)\s*(?:[xX]\s*(\d+)|\s(\d+))$')
            .firstMatch(text);
        if (trail != null) {
          qty = int.parse((trail.group(2) ?? trail.group(3))!);
          text = trail.group(1)!;
        }
      }
    }

    final unitPattern = _units.join('|');
    final unitLead = RegExp(
      '^($unitPattern)\\s+of\\s+(.+)\$',
      caseSensitive: false,
    ).firstMatch(text);
    if (unitLead != null) {
      unit = unitLead.group(1)!.toLowerCase();
      text = unitLead.group(2)!;
    } else {
      final unitTrail = RegExp(
        '^(.+?)\\s+($unitPattern)\$',
        caseSensitive: false,
      ).firstMatch(text);
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

  double estimatedMax(Iterable<ItemDraft> drafts) => _round(
    drafts.fold(
      0.0,
      (sum, d) => sum + (d.maxPrice ?? unitPriceFor(d.name) * d.qty),
    ),
  );

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
    _replaceTrip(
      trip.copyWith(
        requests: [
          for (final r in trip.requests)
            r.id == requestId ? r.copyWith(taking: taking) : r,
        ],
      ),
    );
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
        status: i.status == ItemStatus.got
            ? ItemStatus.pending
            : ItemStatus.got,
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
        _updateItem(
          tripId,
          item.id,
          (i) => i.copyWith(status: ItemStatus.skipped),
        );
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
      _updateItem(
        p.tripId,
        p.itemId,
        (i) => i.copyWith(status: ItemStatus.skipped),
      );
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
      lines.add(
        ReceiptLine(
          lineNo: ++n,
          description: receiptLabel(
            item.displayName,
            qty: substituted ? 1 : item.qty,
          ),
          total: price,
          itemId: item.id,
          assignedTo: substituted ? null : item.requesterId,
          ambiguous: substituted,
          options: substituted ? [trip.shopperId, ...requesterIds] : const [],
        ),
      );
    }
    for (final own in const [
      ('COFFEE BEANS 12OZ', 8.99),
      ('PIZZA MARGHERITA FRZ', 5.49),
    ]) {
      lines.add(
        ReceiptLine(
          lineNo: ++n,
          description: own.$1,
          total: own.$2,
          assignedTo: trip.shopperId,
        ),
      );
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

  // ---------------------------------------------------------------------------
  // Distance calculation (Haversine formula)
  // ---------------------------------------------------------------------------

  static const double _earthRadiusKm = 6371;

  /// Compute distance in meters between two lat/lng coordinates using Haversine.
  static double _computeDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dlat = (lat2 - lat1) * math.pi / 180;
    final dlng = (lng2 - lng1) * math.pi / 180;
    final a =
        math.sin(dlat / 2) * math.sin(dlat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dlng / 2) *
            math.sin(dlng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusKm * c * 1000; // return meters
  }

  /// Compute distance in meters between two members using their address coordinates.
  /// Returns null if either member lacks coordinates.
  double? distanceBetween(Member a, Member b) {
    final aLat = a.address?.lat;
    final aLng = a.address?.lng;
    final bLat = b.address?.lat;
    final bLng = b.address?.lng;
    if (aLat == null || aLng == null || bLat == null || bLng == null) {
      return null;
    }
    return _computeDistance(aLat, aLng, bLat, bLng);
  }

  /// Resolve a store name to its geographic coordinates using BostonDemoData.
  /// Uses fuzzy matching (substring search) to handle slight variations.
  /// Returns null if the store is not found.
  LatLng? storeCoordinates(String storeName) {
    if (storeName.isEmpty) return null;

    // Exact match first
    for (final (name, lat, lng) in BostonDemoData.stores) {
      if (name.toLowerCase() == storeName.toLowerCase()) {
        return LatLng(lat, lng);
      }
    }

    // Fuzzy match: substring search (case-insensitive)
    final queryLower = storeName.toLowerCase();
    for (final (name, lat, lng) in BostonDemoData.stores) {
      if (name.toLowerCase().contains(queryLower)) {
        return LatLng(lat, lng);
      }
    }

    // No match found
    return null;
  }

  // PATCH /receipts/{id}/assignments
  void assignLine(String tripId, int lineNo, String memberId) {
    final split = receipts[tripId]!;
    receipts[tripId] = split.copyWith(
      lines: [
        for (final l in split.lines)
          l.lineNo == lineNo ? l.copyWith(assignedTo: memberId) : l,
      ],
    );
    notifyListeners();
  }

  // Confirm assignments → settlements, PATCH /trips/{id}/status settling
  List<Settlement> confirmSplit(String tripId) {
    final trip = tripById(tripId);
    final split = receipts[tripId]!;
    final shopper = memberById(trip.shopperId);
    final result = <Settlement>[];
    for (final r in trip.requests.where((r) => r.taking)) {
      final mine = split.lines
          .where((l) => l.assignedTo == r.requesterId)
          .toList();
      if (mine.isEmpty) continue;
      final subtotal = _round(mine.fold(0.0, (s, l) => s + l.total));
      final taxShare = _round(split.tax * subtotal / split.subtotal);
      final total = _round(subtotal + taxShare);
      final note = Uri.encodeComponent('Favorly · ${trip.store}');
      result.add(
        Settlement(
          id: _id('settle'),
          tripId: tripId,
          requesterId: r.requesterId,
          lines: [
            for (final l in mine)
              SettlementLine(
                description: _prettyLine(trip, l),
                amount: l.total,
              ),
          ],
          subtotal: subtotal,
          taxShare: taxShare,
          total: total,
          venmoLink:
              'https://venmo.com/${shopper.venmoHandle}?txn=pay&amount=${total.toStringAsFixed(2)}&note=$note',
        ),
      );
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
      _bump(
        r.requesterId,
        (x) => x.copyWith(favorsReceived: x.favorsReceived + 1),
      );
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
  List<ExperienceRating> ratingsFor(String memberId) =>
      experiences.values.where((e) => e.ratedId == memberId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// GET /experiences?ratedById={memberId}
  List<ExperienceRating> ratingsFrom(String memberId) =>
      experiences.values.where((e) => e.ratedById == memberId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Compute compatibility score between two members (0.0 to 1.0).
  /// Factors: number of trips together, average rating given to each other,
  /// directional feedback balance.
  MemberCompatibility compatibilityScore(String id1, String id2) {
    final ratings1to2 = experiences.values
        .where((e) => e.ratedById == id1 && e.ratedId == id2)
        .toList();
    final ratings2to1 = experiences.values
        .where((e) => e.ratedById == id2 && e.ratedId == id1)
        .toList();

    final tripsWorked = {
      ...ratings1to2.map((r) => r.tripId),
      ...ratings2to1.map((r) => r.tripId),
    }.length;

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
        : allRatings.fold(0.0, (sum, r) => sum + r.overallRating) /
              allRatings.length;

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
  List<(Member, MemberCompatibility)> recommendedPartners(
    String memberId, {
    int limit = 3,
  }) {
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
      for (final score in scores.take(limit))
        (memberById(score.memberId2), score),
    ];
  }

  // ---------------------------------------------------------------------------
  // Deterministic helpers (mirror backend/shared matching code)
  // ---------------------------------------------------------------------------

  static StoreSection sectionFor(String name) {
    final n = name.toLowerCase();
    bool has(List<String> words) => words.any(n.contains);
    if (has(const [
      'banana',
      'lemon',
      'apple',
      'avocado',
      'berr',
      'tomato',
      'onion',
      'garlic',
      'lettuce',
      'spinach',
      'kale',
      'cilantro',
      'lime',
      'orange',
      'grape',
      'pepper',
      'potato',
      'carrot',
      'cucumber',
      'herb',
      'salad',
    ])) {
      return StoreSection.produce;
    }
    if (has(const [
      'sourdough',
      'bread',
      'bagel',
      'loaf',
      'croissant',
      'muffin',
      'tortilla',
      'bun',
    ])) {
      return StoreSection.bakery;
    }
    if (has(const [
      'chicken',
      'beef',
      'pork',
      'turkey',
      'salmon',
      'fish',
      'shrimp',
      'steak',
      'sausage',
      'bacon',
    ])) {
      return StoreSection.meat;
    }
    if (has(const [
      'milk',
      'butter',
      'yogurt',
      'cheese',
      'egg',
      'cream',
      'kefir',
    ])) {
      return StoreSection.dairy;
    }
    if (has(const [
      'frozen',
      'dumpling',
      'gyoza',
      'ice cream',
      'pizza',
      'waffle',
    ])) {
      return StoreSection.frozen;
    }
    if (has(const [
      'water',
      'sparkling',
      'juice',
      'coffee',
      'tea',
      'soda',
      'kombucha',
      'beer',
      'wine',
    ])) {
      return StoreSection.beverages;
    }
    if (has(const [
      'paper towel',
      'toilet',
      'detergent',
      'sponge',
      'trash',
      'foil',
      'soap',
      'dish',
    ])) {
      return StoreSection.household;
    }
    if (has(const [
      'shampoo',
      'toothpaste',
      'deodorant',
      'lotion',
      'razor',
      'floss',
      'sunscreen',
    ])) {
      return StoreSection.personalCare;
    }
    if (has(const [
      'chocolate',
      'rice',
      'pasta',
      'bean',
      'cereal',
      'oat',
      'granola',
      'peanut',
      'almond',
      'honey',
      'oil',
      'flour',
      'sugar',
      'salt',
      'sauce',
      'chips',
      'cracker',
      'snack',
      'nut',
      'soup',
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
    _replaceTrip(
      t.copyWith(
        requests: [
          for (final r in t.requests)
            r.copyWith(
              items: [for (final i in r.items) i.id == itemId ? update(i) : i],
            ),
        ],
      ),
    );
  }

  void _bump(String memberId, LedgerRow Function(LedgerRow) update) {
    final row =
        ledger[memberId] ??
        LedgerRow(
          memberId: memberId,
          tripsRun: 0,
          favorsReceived: 0,
          dollarsCarried: 0,
        );
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
  }) => TripItem(
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

  List<Trip> _generateTrips(
    DateTime now,
    DateTime Function(int dayOffset, int hour, int minute) at,
    int sinceSaturday,
    DateTime leaves,
  ) {
    // Guard: ensure members are loaded before generating trips
    if (members.isEmpty) {
      debugPrint('⚠️ Warning: members list is empty in _generateTrips');
      return [];
    }

    final itemSamples = {
      'groceries': [
        'Oat Milk',
        'Almond Milk',
        'Greek Yogurt',
        'Organic Coffee',
        'Frozen Berries',
        'Spinach',
        'Organic Kale',
        'Olive Oil',
        'Almond Flour',
        'Pasta',
        'Hummus',
        'Cheese',
        'Eggs',
      ],
      'snacks': [
        'Dark Chocolate',
        'Almonds',
        'Sparkling Water',
        'Granola',
        'Protein Bar',
        'Trail Mix',
        'Crackers',
        'Chips',
      ],
      'household': [
        'Toilet Paper',
        'Paper Towels',
        'Dish Soap',
        'Laundry Detergent',
        'Toothpaste',
        'Shampoo',
        'Deodorant',
        'Trash Bags',
      ],
    };

    final trips = <Trip>[];

    // Completed trips from past week (for settlements and history)
    final completedStores = [
      'Costco',
      'Whole Foods',
      "Trader Joe's",
      'Market Basket',
    ];
    for (var i = 0; i < 12; i++) {
      final shopper = members[i % members.length];
      final store = completedStores[i % completedStores.length];
      final dayOffset = -(7 - (i % 6)); // Spread across last week

      // Add 3-5 requests per completed trip
      final requestCount = 3 + (i % 3);
      final tripRequests = <TripRequest>[];
      for (var j = 0; j < requestCount; j++) {
        final requester = members[(i + j + 1) % members.length];
        final itemCategory = itemSamples.entries
            .toList()[j % itemSamples.length];
        final itemCount = 2 + (j % 3);

        tripRequests.add(
          TripRequest(
            id: _id('req'),
            requesterId: requester.id,
            items: [
              for (var k = 0; k < itemCount; k++)
                _item(
                  requester.id,
                  itemCategory.value[k % itemCategory.value.length],
                  maxPrice: 5.0 + (k * 2.0),
                  status: ItemStatus.got,
                ),
            ],
          ),
        );
      }

      trips.add(
        Trip(
          id: _id('trip'),
          shopperId: shopper.id,
          circleId: DEMO_CIRCLE_ID,
          store: store,
          departAt: at(dayOffset, 9 + (i % 12), (i * 15) % 60),
          status: TripStatus.done,
          caps: const TripCaps(
            maxRequesters: 6,
            maxDollarsPerPerson: 50,
            maxItemsPerPerson: 10,
          ),
          requests: tripRequests,
        ),
      );
    }

    // Active/upcoming trips (today and tomorrow)
    final activeStores = [
      "Trader Joe's",
      'Whole Foods',
      'CVS',
      'Market Basket',
      'Target',
    ];
    for (var i = 0; i < 5; i++) {
      final shopper = members[(i * 3) % members.length];
      final store = activeStores[i % activeStores.length];
      final dayOffset = i ~/ 2; // Some today, some tomorrow
      final hour = 9 + (i * 2);

      final requestCount = 2 + (i % 3);
      final tripRequests = <TripRequest>[];
      for (var j = 0; j < requestCount; j++) {
        final requester = members[(i + j + 2) % members.length];
        final itemCategory = itemSamples.entries
            .toList()[j % itemSamples.length];
        final itemCount = 1 + (j % 3);

        tripRequests.add(
          TripRequest(
            id: _id('req'),
            requesterId: requester.id,
            items: [
              for (var k = 0; k < itemCount; k++)
                _item(
                  requester.id,
                  itemCategory.value[k % itemCategory.value.length],
                  maxPrice: 4.0 + (k * 2.0),
                ),
            ],
          ),
        );
      }

      trips.add(
        Trip(
          id: _id('trip'),
          shopperId: shopper.id,
          circleId: DEMO_CIRCLE_ID,
          store: store,
          departAt: at(dayOffset, hour, 0),
          caps: const TripCaps(
            maxRequesters: 5,
            maxDollarsPerPerson: 40,
            maxItemsPerPerson: 8,
          ),
          requests: tripRequests,
        ),
      );
    }

    return trips;
  }

  void _seed() {
    _seq = 0;
    // Load 25+ diverse members from Boston area seed data
    members
      ..clear()
      ..addAll([
        for (final (
              id,
              name,
              venmo,
              tint,
              _,
              __,
              address,
              bio,
              dietary,
              stores,
              availability,
              role,
            )
            in BostonDemoData.members)
          Member(
            id: id,
            name: name,
            venmoHandle: venmo,
            tint: tint,
            address: address,
            bio: bio,
            dietary: dietary,
            stores: stores,
            availability: availability,
            role: role ?? ShopperRole.both,
          ),
      ]);
    _meId = ANA_ID;
    joined = true;
    notificationsOn = true;
    pendingPrompt = null;
    lastCompletedTripId = null;
    receipts.clear();
    settlements.clear();
    insuranceStatuses.clear();
    referralRewards.clear();
    claimedUnlocks.clear();
    _pendingRequests.clear();

    final now = DateTime.now();
    DateTime at(int dayOffset, int hour, int minute) =>
        DateTime(now.year, now.month, now.day + dayOffset, hour, minute);
    // The live trip always leaves a couple of hours from now, on the hour, so
    // the demo reads the same at 10 AM or 10 PM.
    final leaves = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
    ).add(const Duration(hours: 2));
    var sinceSaturday = (now.weekday - DateTime.saturday) % 7;
    if (sinceSaturday == 0) sinceSaturday = 7;

    trips
      ..clear()
      ..addAll(_generateTrips(now, at, sinceSaturday, leaves));

    // Initialize ledger for all members with varied activity
    ledger
      ..clear()
      ..addAll({
        for (var i = 0; i < members.length; i++)
          members[i].id: LedgerRow(
            memberId: members[i].id,
            tripsRun: math.Random(i).nextInt(8),
            favorsReceived: math.Random(i + 1).nextInt(10),
            dollarsCarried: math.Random(i + 2).nextDouble() * 150,
          ),
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

    // Generate settlements for all completed trips with varied payment states
    settlements.clear();
    for (final trip in trips.where((t) => t.status == TripStatus.done)) {
      final tripSettlements = <Settlement>[];
      for (final request in trip.requests) {
        // Calculate settlement amounts based on items
        double subtotal = 0;
        for (final item in request.items) {
          subtotal += (item.maxPrice ?? 5.0) * item.qty;
        }
        final taxShare = _round(subtotal * 0.08);
        final total = _round(subtotal + taxShare);

        // Vary payment state: 70% paid, 20% unpaid, 10% pending
        final paymentRand = math.Random(request.id.hashCode).nextDouble();
        final paid = paymentRand < 0.7;

        tripSettlements.add(
          Settlement(
            id: _id('settle'),
            tripId: trip.id,
            requesterId: request.requesterId,
            subtotal: _round(subtotal),
            taxShare: taxShare,
            total: total,
            lines: [],
            venmoLink:
                'venmo.com/${memberById(trip.shopperId).venmoHandle}?txn=${trip.store}',
            paid: paid,
          ),
        );
      }
      settlements[trip.id] = tripSettlements;
    }
  }

  // ---------------------------------------------------------------------------
  // Collective Unlocks
  // ---------------------------------------------------------------------------

  /// Get collective unlock status for a circle.
  CircleUnlockStatus unlocksFor(String circleId) {
    // Check if cached
    if (_cachedUnlockStatus != null) {
      return _cachedUnlockStatus!;
    }

    // Count all settlements from this month
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    int favorsThisMonth = 0;
    for (final tripSettlements in settlements.values) {
      for (final settlement in tripSettlements) {
        // Check if trip is this month
        Trip? trip;
        try {
          trip = trips.firstWhere((t) => t.id == settlement.tripId);
        } catch (e) {
          trip = null;
        }
        if (trip != null && trip.departAt.isAfter(monthStart)) {
          favorsThisMonth++;
        }
      }
    }

    // Determine progress toward milestones
    int? nextMilestoneThreshold;
    String? nextMilestoneDescription;
    int? nextMilestoneFavorsRemaining;
    final List<String> availableUnlocks = [];

    if (favorsThisMonth < 25) {
      nextMilestoneThreshold = 25;
      nextMilestoneDescription = 'Pizza Night 🍕';
      nextMilestoneFavorsRemaining = 25 - favorsThisMonth;
      availableUnlocks.add(UnlockType.pizzaNight);
    } else if (favorsThisMonth < 50) {
      nextMilestoneThreshold = 50;
      nextMilestoneDescription = 'Coffee Machine ☕';
      nextMilestoneFavorsRemaining = 50 - favorsThisMonth;
      availableUnlocks.addAll([
        UnlockType.pizzaNight,
        UnlockType.coffeeMachine,
      ]);
    } else if (favorsThisMonth < 100) {
      nextMilestoneThreshold = 100;
      nextMilestoneDescription = 'Lobby Upgrade 🏢';
      nextMilestoneFavorsRemaining = 100 - favorsThisMonth;
      availableUnlocks.addAll([
        UnlockType.pizzaNight,
        UnlockType.coffeeMachine,
        UnlockType.lobbyUpgrade,
      ]);
    } else {
      // All unlocked
      availableUnlocks.addAll([
        UnlockType.pizzaNight,
        UnlockType.coffeeMachine,
        UnlockType.lobbyUpgrade,
        UnlockType.communityLunch,
      ]);
    }

    // Compute progress percentage
    final milestone = nextMilestoneThreshold ?? 100;
    final progressPercentage = (favorsThisMonth / milestone * 100).clamp(
      0.0,
      100.0,
    );

    final status = CircleUnlockStatus(
      circleId: circleId,
      favorsThisMonth: favorsThisMonth,
      progressPercentage: progressPercentage,
      nextMilestoneThreshold: nextMilestoneThreshold,
      nextMilestoneDescription: nextMilestoneDescription,
      nextMilestoneFavorsRemaining: nextMilestoneFavorsRemaining,
      claimedUnlocks: [
        // Map claimed unlock types to CircleUnlock objects
        for (final unlockedType in claimedUnlocks)
          _createCircleUnlock(unlockedType),
      ],
      availableUnlocks: availableUnlocks,
    );

    _cachedUnlockStatus = status;
    return status;
  }

  /// Create a CircleUnlock model from an unlock type string.
  CircleUnlock _createCircleUnlock(String unlockType) {
    String rewardDescription;

    switch (unlockType) {
      case UnlockType.pizzaNight:
        rewardDescription = 'Pizza night sponsored by building';
      case UnlockType.coffeeMachine:
        rewardDescription = 'Coffee machine for lobby';
      case UnlockType.lobbyUpgrade:
        rewardDescription = 'Lobby renovation project';
      case UnlockType.communityLunch:
        rewardDescription = 'Community lunch gathering';
      default:
        rewardDescription = 'Mystery reward';
    }

    return CircleUnlock(
      id: _id('unlock'),
      circleId: DEMO_CIRCLE_ID,
      unlockType: unlockType,
      rewardDescription: rewardDescription,
      favorsAtUnlock: unlockType == UnlockType.pizzaNight
          ? 25
          : unlockType == UnlockType.coffeeMachine
          ? 50
          : unlockType == UnlockType.lobbyUpgrade
          ? 100
          : 0,
      claimedAt: DateTime.now(),
    );
  }

  /// Demo only: claim an unlock.
  void claimUnlock(String unlockType) {
    if (!claimedUnlocks.contains(unlockType)) {
      claimedUnlocks.add(unlockType);
      _cachedUnlockStatus = null; // Invalidate cache
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Referrals & Invite Codes
  // ---------------------------------------------------------------------------

  /// Get referral stats for a member (includes invite code and earned karma).
  ReferralStats referralStatsFor(String memberId) {
    // Generate deterministic invite code from member ID
    final inviteCode = 'INVITE_${memberId.substring(0, 4).toUpperCase()}';

    // Count referral rewards for this member
    final memberRewards = referralRewards.values
        .where((r) => r.referrerId == memberId)
        .toList();

    final totalReferred = memberRewards.length;
    final totalKarmaEarned = memberRewards.fold(
      0,
      (sum, r) => sum + r.karmaEarned,
    );

    return ReferralStats(
      userId: memberId,
      inviteCode: inviteCode,
      totalReferred: totalReferred,
      totalKarmaEarned: totalKarmaEarned,
      referrals: memberRewards,
    );
  }

  /// Demo only: award a referral reward to a referrer.
  void awardReferralReward({
    required String referrerId,
    required String referreeId,
    int karmaAmount = 20,
  }) {
    final rewardId = _id('referral_reward');
    referralRewards[rewardId] = ReferralReward(
      id: rewardId,
      referrerId: referrerId,
      referreeId: referreeId,
      karmaEarned: karmaAmount,
      completedFavorId: _id('favor'),
      earnedAt: DateTime.now(),
    );
    notifyListeners();
  }
}
