/// Domain models. These mirror the backend Pydantic contracts in
/// `backend/shared/contracts/models.py` so wiring the API later is a
/// field-for-field mapping.
library;

enum TripStatus { open, shopping, settling, done }

enum ItemStatus { pending, got, substituted, skipped }

enum IntakeSource { text, voice, photo }

enum StoreSection {
  produce('Produce'),
  bakery('Bakery'),
  meat('Meat'),
  dairy('Dairy'),
  frozen('Frozen'),
  pantry('Pantry'),
  beverages('Drinks'),
  household('Household'),
  personalCare('Personal care'),
  other('Other');

  const StoreSection(this.label);
  final String label;
}

enum MemberTint { blue, green, amber, plum }

class Member {
  const Member({
    required this.id,
    required this.name,
    required this.venmoHandle,
    required this.tint,
  });

  final String id;
  final String name;
  final String venmoHandle;
  final MemberTint tint;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  Member copyWith({String? name, String? venmoHandle}) => Member(
        id: id,
        name: name ?? this.name,
        venmoHandle: venmoHandle ?? this.venmoHandle,
        tint: tint,
      );
}

class TripCaps {
  const TripCaps({
    this.maxRequesters = 5,
    this.maxDollarsPerPerson = 40,
    this.maxItemsPerPerson = 8,
  });

  final int maxRequesters;
  final double maxDollarsPerPerson;
  final int maxItemsPerPerson;

  TripCaps copyWith({
    int? maxRequesters,
    double? maxDollarsPerPerson,
    int? maxItemsPerPerson,
  }) =>
      TripCaps(
        maxRequesters: maxRequesters ?? this.maxRequesters,
        maxDollarsPerPerson: maxDollarsPerPerson ?? this.maxDollarsPerPerson,
        maxItemsPerPerson: maxItemsPerPerson ?? this.maxItemsPerPerson,
      );
}

const _unset = Object();

/// A parsed, not-yet-attached item. `needsConfirmation` mirrors the VLM flag;
/// `hint` is the plain-language reason shown to the requester.
class ItemDraft {
  const ItemDraft({
    required this.name,
    this.qty = 1,
    this.unit,
    this.note,
    this.maxPrice,
    this.needsConfirmation = false,
    this.hint,
  });

  final String name;
  final int qty;
  final String? unit;
  final String? note;
  final double? maxPrice;
  final bool needsConfirmation;
  final String? hint;

  String get qtyLabel => unit == null ? '$qty' : '$qty $unit';

  ItemDraft copyWith({
    String? name,
    int? qty,
    Object? unit = _unset,
    Object? note = _unset,
    Object? maxPrice = _unset,
    bool? needsConfirmation,
    Object? hint = _unset,
  }) =>
      ItemDraft(
        name: name ?? this.name,
        qty: qty ?? this.qty,
        unit: identical(unit, _unset) ? this.unit : unit as String?,
        note: identical(note, _unset) ? this.note : note as String?,
        maxPrice:
            identical(maxPrice, _unset) ? this.maxPrice : maxPrice as double?,
        needsConfirmation: needsConfirmation ?? this.needsConfirmation,
        hint: identical(hint, _unset) ? this.hint : hint as String?,
      );
}

class TripItem {
  const TripItem({
    required this.id,
    required this.requesterId,
    required this.name,
    this.qty = 1,
    this.unit,
    this.note,
    this.maxPrice,
    this.section = StoreSection.other,
    this.status = ItemStatus.pending,
    this.substituteName,
    this.substitutePrice,
  });

  final String id;
  final String requesterId;
  final String name;
  final int qty;
  final String? unit;
  final String? note;
  final double? maxPrice;
  final StoreSection section;
  final ItemStatus status;
  final String? substituteName;
  final double? substitutePrice;

  String get displayName => substituteName ?? name;
  String get qtyLabel => unit == null ? '$qty' : '$qty $unit';
  bool get isOpen => status == ItemStatus.pending;

  TripItem copyWith({
    ItemStatus? status,
    Object? substituteName = _unset,
    Object? substitutePrice = _unset,
  }) =>
      TripItem(
        id: id,
        requesterId: requesterId,
        name: name,
        qty: qty,
        unit: unit,
        note: note,
        maxPrice: maxPrice,
        section: section,
        status: status ?? this.status,
        substituteName: identical(substituteName, _unset)
            ? this.substituteName
            : substituteName as String?,
        substitutePrice: identical(substitutePrice, _unset)
            ? this.substitutePrice
            : substitutePrice as double?,
      );
}

class TripRequest {
  const TripRequest({
    required this.id,
    required this.requesterId,
    required this.items,
    this.taking = true,
  });

  final String id;
  final String requesterId;
  final List<TripItem> items;

  /// Shopper's accept/decline. Declines stay invisible to the requester.
  final bool taking;

  double get cappedTotal =>
      items.fold(0, (sum, i) => sum + (i.maxPrice ?? 0) * i.qty);

  TripRequest copyWith({List<TripItem>? items, bool? taking}) => TripRequest(
        id: id,
        requesterId: requesterId,
        items: items ?? this.items,
        taking: taking ?? this.taking,
      );
}

class Trip {
  const Trip({
    required this.id,
    required this.shopperId,
    required this.store,
    required this.departAt,
    this.caps = const TripCaps(),
    this.status = TripStatus.open,
    this.requests = const [],
  });

  final String id;
  final String shopperId;
  final String store;
  final DateTime departAt;
  final TripCaps caps;
  final TripStatus status;
  final List<TripRequest> requests;

  /// Items the shopper is carrying, across accepted requests.
  List<TripItem> get items =>
      requests.where((r) => r.taking).expand((r) => r.items).toList();

  int get requesterCount => requests.length;
  bool get isLive => status != TripStatus.done;

  Trip copyWith({TripStatus? status, List<TripRequest>? requests}) => Trip(
        id: id,
        shopperId: shopperId,
        store: store,
        departAt: departAt,
        caps: caps,
        status: status ?? this.status,
        requests: requests ?? this.requests,
      );
}

class ShelfCandidate {
  const ShelfCandidate({
    required this.name,
    required this.size,
    required this.price,
    required this.reason,
  });

  final String name;
  final String size;
  final double price;
  final String reason;
}

class SubstitutionPrompt {
  const SubstitutionPrompt({
    required this.id,
    required this.tripId,
    required this.itemId,
    required this.requesterId,
    required this.originalName,
    required this.maxPrice,
    required this.candidates,
    required this.expiresAt,
  });

  final String id;
  final String tripId;
  final String itemId;
  final String requesterId;
  final String originalName;
  final double? maxPrice;
  final List<ShelfCandidate> candidates;
  final DateTime expiresAt;
}

class ReceiptLine {
  const ReceiptLine({
    required this.lineNo,
    required this.description,
    required this.total,
    this.itemId,
    this.assignedTo,
    this.ambiguous = false,
    this.options = const [],
  });

  final int lineNo;
  final String description;
  final double total;
  final String? itemId;

  /// Member id, or null when nobody has been picked yet.
  final String? assignedTo;
  final bool ambiguous;
  final List<String> options;

  ReceiptLine copyWith({Object? assignedTo = _unset}) => ReceiptLine(
        lineNo: lineNo,
        description: description,
        total: total,
        itemId: itemId,
        assignedTo:
            identical(assignedTo, _unset) ? this.assignedTo : assignedTo as String?,
        ambiguous: ambiguous,
        options: options,
      );
}

class ReceiptSplit {
  const ReceiptSplit({
    required this.store,
    required this.lines,
    required this.subtotal,
    required this.tax,
    required this.total,
  });

  final String store;
  final List<ReceiptLine> lines;
  final double subtotal;
  final double tax;
  final double total;

  List<ReceiptLine> get needsReview => lines.where((l) => l.ambiguous).toList();
  List<ReceiptLine> get matched => lines.where((l) => !l.ambiguous).toList();
  bool get resolved => needsReview.every((l) => l.assignedTo != null);

  ReceiptSplit copyWith({List<ReceiptLine>? lines}) => ReceiptSplit(
        store: store,
        lines: lines ?? this.lines,
        subtotal: subtotal,
        tax: tax,
        total: total,
      );
}

class SettlementLine {
  const SettlementLine({required this.description, required this.amount});

  final String description;
  final double amount;
}

class Settlement {
  const Settlement({
    required this.id,
    required this.tripId,
    required this.requesterId,
    required this.lines,
    required this.subtotal,
    required this.taxShare,
    required this.total,
    required this.venmoLink,
    this.paid = false,
  });

  final String id;
  final String tripId;
  final String requesterId;
  final List<SettlementLine> lines;
  final double subtotal;
  final double taxShare;
  final double total;
  final String venmoLink;
  final bool paid;

  Settlement copyWith({bool? paid}) => Settlement(
        id: id,
        tripId: tripId,
        requesterId: requesterId,
        lines: lines,
        subtotal: subtotal,
        taxShare: taxShare,
        total: total,
        venmoLink: venmoLink,
        paid: paid ?? this.paid,
      );
}

class LedgerRow {
  const LedgerRow({
    required this.memberId,
    required this.tripsRun,
    required this.favorsReceived,
    required this.dollarsCarried,
  });

  final String memberId;
  final int tripsRun;
  final int favorsReceived;
  final double dollarsCarried;

  LedgerRow copyWith({
    int? tripsRun,
    int? favorsReceived,
    double? dollarsCarried,
  }) =>
      LedgerRow(
        memberId: memberId,
        tripsRun: tripsRun ?? this.tripsRun,
        favorsReceived: favorsReceived ?? this.favorsReceived,
        dollarsCarried: dollarsCarried ?? this.dollarsCarried,
      );
}

/// Experience rating left after a trip to track collaboration quality.
/// Used by the matching algorithm to reconnect people who work well together.
class ExperienceRating {
  const ExperienceRating({
    required this.id,
    required this.tripId,
    required this.ratedById,
    required this.ratedId,
    required this.overallRating,
    this.reliabilityRating,
    this.accuracyRating,
    this.communicationRating,
    this.comment,
    required this.createdAt,
  });

  final String id;
  final String tripId;
  final String ratedById; // Who gave the rating
  final String ratedId; // Who was rated
  final int overallRating; // 1-5 scale
  final int? reliabilityRating; // 1-5: showed up on time, completed requests
  final int? accuracyRating; // 1-5: got correct items, good substitutions
  final int? communicationRating; // 1-5: clear instructions, responsive
  final String? comment;
  final DateTime createdAt;

  ExperienceRating copyWith({
    int? overallRating,
    int? reliabilityRating,
    int? accuracyRating,
    int? communicationRating,
    String? comment,
  }) =>
      ExperienceRating(
        id: id,
        tripId: tripId,
        ratedById: ratedById,
        ratedId: ratedId,
        overallRating: overallRating ?? this.overallRating,
        reliabilityRating: reliabilityRating ?? this.reliabilityRating,
        accuracyRating: accuracyRating ?? this.accuracyRating,
        communicationRating: communicationRating ?? this.communicationRating,
        comment: comment ?? this.comment,
        createdAt: createdAt,
      );
}

/// Computed compatibility score between two members based on past experiences.
/// Used to recommend trip pairings.
class MemberCompatibility {
  const MemberCompatibility({
    required this.memberId1,
    required this.memberId2,
    required this.score,
    required this.tripsWorkedTogether,
    required this.averageRating,
  });

  final String memberId1;
  final String memberId2;
  final double score; // 0.0 to 1.0
  final int tripsWorkedTogether;
  final double averageRating; // 1.0 to 5.0
}
