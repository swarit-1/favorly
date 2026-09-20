/// Insurance eligibility and guarantee models.

class InsuranceStatus {
  const InsuranceStatus({
    required this.userId,
    required this.active,
    required this.tripsCarriedThisMonth,
    required this.guaranteedThreshold,
    this.expiresAt,
    this.karmaMultiplierWhenActive = 2,
    this.guaranteeWindowHours = 48,
  });

  final String userId;
  final bool active;
  final int tripsCarriedThisMonth;
  final int guaranteedThreshold;
  final DateTime? expiresAt;
  final int karmaMultiplierWhenActive;
  final int guaranteeWindowHours;

  bool get isEligible => tripsCarriedThisMonth >= guaranteedThreshold;

  String get statusMessage {
    if (active) {
      return 'You\'re guaranteed! Carry 3 times/month and your requests are covered.';
    } else if (isEligible) {
      return 'You\'re guaranteed! All future requests are covered by Favorly.';
    } else {
      final needed = guaranteedThreshold - tripsCarriedThisMonth;
      return 'Carry $needed more time${needed == 1 ? '' : 's'} this month to unlock guaranteed coverage.';
    }
  }

  factory InsuranceStatus.fromJson(Map<String, dynamic> json) {
    return InsuranceStatus(
      userId: json['user_id'] as String,
      active: json['active'] as bool? ?? false,
      tripsCarriedThisMonth: json['trips_carried_this_month'] as int? ?? 0,
      guaranteedThreshold:
          json['guaranteed_threshold'] as int? ?? 3,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      karmaMultiplierWhenActive:
          json['karma_multiplier_when_active'] as int? ?? 2,
      guaranteeWindowHours:
          json['guarantee_window_hours'] as int? ?? 48,
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'active': active,
    'trips_carried_this_month': tripsCarriedThisMonth,
    'guaranteed_threshold': guaranteedThreshold,
    'expires_at': expiresAt?.toIso8601String(),
    'karma_multiplier_when_active': karmaMultiplierWhenActive,
    'guarantee_window_hours': guaranteeWindowHours,
  };

  InsuranceStatus copyWith({
    String? userId,
    bool? active,
    int? tripsCarriedThisMonth,
    int? guaranteedThreshold,
    DateTime? expiresAt,
    int? karmaMultiplierWhenActive,
    int? guaranteeWindowHours,
  }) {
    return InsuranceStatus(
      userId: userId ?? this.userId,
      active: active ?? this.active,
      tripsCarriedThisMonth:
          tripsCarriedThisMonth ?? this.tripsCarriedThisMonth,
      guaranteedThreshold:
          guaranteedThreshold ?? this.guaranteedThreshold,
      expiresAt: expiresAt ?? this.expiresAt,
      karmaMultiplierWhenActive:
          karmaMultiplierWhenActive ?? this.karmaMultiplierWhenActive,
      guaranteeWindowHours:
          guaranteeWindowHours ?? this.guaranteeWindowHours,
    );
  }
}

class GuaranteedRequest {
  const GuaranteedRequest({
    required this.id,
    required this.requesterId,
    required this.requestItems,
    required this.guaranteeDeadline,
    this.filledBy,
    this.filledAt,
    required this.coverageCost,
    required this.createdAt,
  });

  final String id;
  final String requesterId;
  final String requestItems;
  final DateTime guaranteeDeadline;
  final String? filledBy;
  final DateTime? filledAt;
  final double coverageCost;
  final DateTime createdAt;

  bool get isPending => filledAt == null;
  bool get isOverdue => DateTime.now().isAfter(guaranteeDeadline);
  bool get isCoveredByBuilding => filledBy == null && filledAt != null;

  String get statusLabel {
    if (filledAt != null) {
      return filledBy == null ? 'Covered by Favorly' : 'Filled by neighbor';
    }
    return isOverdue ? 'Awaiting guarantee' : 'Pending';
  }

  String get deadlineLabel {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = months[guaranteeDeadline.month - 1];
    final day = guaranteeDeadline.day;
    final hour = guaranteeDeadline.hour % 12 == 0
        ? 12
        : guaranteeDeadline.hour % 12;
    final minute = guaranteeDeadline.minute.toString().padLeft(2, '0');
    final ampm = guaranteeDeadline.hour < 12 ? 'AM' : 'PM';
    return '$month $day, $hour:$minute $ampm';
  }

  factory GuaranteedRequest.fromJson(Map<String, dynamic> json) {
    return GuaranteedRequest(
      id: json['id'] as String,
      requesterId: json['requester_id'] as String,
      requestItems: json['request_items'] as String? ?? '{}',
      guaranteeDeadline:
          DateTime.parse(json['guarantee_deadline'] as String),
      filledBy: json['filled_by'] as String?,
      filledAt: json['filled_at'] != null
          ? DateTime.parse(json['filled_at'] as String)
          : null,
      coverageCost: double.parse(
          (json['coverage_cost'] as dynamic)?.toString() ?? '0'),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'requester_id': requesterId,
    'request_items': requestItems,
    'guarantee_deadline': guaranteeDeadline.toIso8601String(),
    'filled_by': filledBy,
    'filled_at': filledAt?.toIso8601String(),
    'coverage_cost': coverageCost,
    'created_at': createdAt.toIso8601String(),
  };

  GuaranteedRequest copyWith({
    String? id,
    String? requesterId,
    String? requestItems,
    DateTime? guaranteeDeadline,
    String? filledBy,
    DateTime? filledAt,
    double? coverageCost,
    DateTime? createdAt,
  }) {
    return GuaranteedRequest(
      id: id ?? this.id,
      requesterId: requesterId ?? this.requesterId,
      requestItems: requestItems ?? this.requestItems,
      guaranteeDeadline: guaranteeDeadline ?? this.guaranteeDeadline,
      filledBy: filledBy ?? this.filledBy,
      filledAt: filledAt ?? this.filledAt,
      coverageCost: coverageCost ?? this.coverageCost,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
