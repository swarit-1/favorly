/// Plain data classes for the backend's JSON shapes (see
/// backend/shared/contracts/models.py). No freezed/codegen -- kept simple
/// since this is the first real wiring pass.
library;

class TripCaps {
  const TripCaps({
    required this.maxRequesters,
    required this.maxDollarsPerPerson,
    required this.maxItemsPerPerson,
  });

  final int maxRequesters;
  final String maxDollarsPerPerson;
  final int maxItemsPerPerson;

  factory TripCaps.fromJson(Map<String, dynamic> json) => TripCaps(
        maxRequesters: json['max_requesters'] as int,
        maxDollarsPerPerson: json['max_dollars_per_person'].toString(),
        maxItemsPerPerson: json['max_items_per_person'] as int,
      );

  static const TripCaps defaults = TripCaps(
    maxRequesters: 5,
    maxDollarsPerPerson: '40.00',
    maxItemsPerPerson: 8,
  );
}

class Trip {
  const Trip({
    required this.id,
    required this.shopperId,
    required this.circleId,
    required this.store,
    required this.departAt,
    required this.status,
    required this.caps,
  });

  final String id;
  final String shopperId;
  final String circleId;
  final String store;
  final DateTime departAt;
  final String status;
  final TripCaps caps;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String,
        shopperId: json['shopper_id'] as String,
        circleId: json['circle_id'] as String,
        store: json['store'] as String,
        departAt: DateTime.parse(json['depart_at'] as String),
        status: json['status'] as String,
        caps: TripCaps.fromJson(json['caps'] as Map<String, dynamic>),
      );

  bool get isActive => status == 'open' || status == 'shopping';
}

class LedgerRow {
  const LedgerRow({
    required this.userId,
    required this.name,
    required this.tripsRun,
    required this.favorsReceived,
  });

  final String userId;
  final String name;
  final int tripsRun;
  final int favorsReceived;

  factory LedgerRow.fromJson(Map<String, dynamic> json) => LedgerRow(
        userId: json['user_id'] as String,
        name: json['name'] as String,
        tripsRun: json['trips_run'] as int,
        favorsReceived: json['favors_received'] as int,
      );
}
