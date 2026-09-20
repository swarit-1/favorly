/// Savings and earnings models for the personal savings meter.
library;

class RequesterSavings {
  const RequesterSavings({
    required this.feesAvoidedThisMonth,
    required this.feesAvoidedAllTime,
    required this.tripsUsedThisMonth,
    required this.deliveryAppEstimate,
    required this.favorlyCost,
  });

  final double feesAvoidedThisMonth;
  final double feesAvoidedAllTime;
  final int tripsUsedThisMonth;
  final double deliveryAppEstimate;
  final double favorlyCost;

  RequesterSavings copyWith({
    double? feesAvoidedThisMonth,
    double? feesAvoidedAllTime,
    int? tripsUsedThisMonth,
    double? deliveryAppEstimate,
    double? favorlyCost,
  }) =>
      RequesterSavings(
        feesAvoidedThisMonth: feesAvoidedThisMonth ?? this.feesAvoidedThisMonth,
        feesAvoidedAllTime: feesAvoidedAllTime ?? this.feesAvoidedAllTime,
        tripsUsedThisMonth: tripsUsedThisMonth ?? this.tripsUsedThisMonth,
        deliveryAppEstimate: deliveryAppEstimate ?? this.deliveryAppEstimate,
        favorlyCost: favorlyCost ?? this.favorlyCost,
      );

  factory RequesterSavings.fromJson(Map<String, dynamic> json) =>
      RequesterSavings(
        feesAvoidedThisMonth:
            (json['fees_avoided_this_month'] as num).toDouble(),
        feesAvoidedAllTime: (json['fees_avoided_all_time'] as num).toDouble(),
        tripsUsedThisMonth: json['trips_used_this_month'] as int,
        deliveryAppEstimate: (json['delivery_app_estimate'] as num).toDouble(),
        favorlyCost: (json['favorly_cost'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'fees_avoided_this_month': feesAvoidedThisMonth,
        'fees_avoided_all_time': feesAvoidedAllTime,
        'trips_used_this_month': tripsUsedThisMonth,
        'delivery_app_estimate': deliveryAppEstimate,
        'favorly_cost': favorlyCost,
      };
}

class CarrierSavings {
  const CarrierSavings({
    required this.perksEarnedThisMonth,
    required this.bulkSavingsThisMonth,
    required this.totalEarnedThisMonth,
    required this.tripsCarriedThisMonth,
  });

  final double perksEarnedThisMonth;
  final double bulkSavingsThisMonth;
  final double totalEarnedThisMonth;
  final int tripsCarriedThisMonth;

  CarrierSavings copyWith({
    double? perksEarnedThisMonth,
    double? bulkSavingsThisMonth,
    double? totalEarnedThisMonth,
    int? tripsCarriedThisMonth,
  }) =>
      CarrierSavings(
        perksEarnedThisMonth:
            perksEarnedThisMonth ?? this.perksEarnedThisMonth,
        bulkSavingsThisMonth:
            bulkSavingsThisMonth ?? this.bulkSavingsThisMonth,
        totalEarnedThisMonth:
            totalEarnedThisMonth ?? this.totalEarnedThisMonth,
        tripsCarriedThisMonth:
            tripsCarriedThisMonth ?? this.tripsCarriedThisMonth,
      );

  factory CarrierSavings.fromJson(Map<String, dynamic> json) =>
      CarrierSavings(
        perksEarnedThisMonth:
            (json['perks_earned_this_month'] as num).toDouble(),
        bulkSavingsThisMonth:
            (json['bulk_savings_this_month'] as num).toDouble(),
        totalEarnedThisMonth:
            (json['total_earned_this_month'] as num).toDouble(),
        tripsCarriedThisMonth: json['trips_carried_this_month'] as int,
      );

  Map<String, dynamic> toJson() => {
        'perks_earned_this_month': perksEarnedThisMonth,
        'bulk_savings_this_month': bulkSavingsThisMonth,
        'total_earned_this_month': totalEarnedThisMonth,
        'trips_carried_this_month': tripsCarriedThisMonth,
      };
}

class PersonalSavings {
  const PersonalSavings({
    this.requesterSavings,
    this.carrierSavings,
    this.hasRequesterData = false,
    this.hasCarrierData = false,
  });

  final RequesterSavings? requesterSavings;
  final CarrierSavings? carrierSavings;
  final bool hasRequesterData;
  final bool hasCarrierData;

  bool get isEmpty => !hasRequesterData && !hasCarrierData;

  double get totalSavingsEarnings {
    double total = 0;
    if (requesterSavings != null) {
      total += requesterSavings!.feesAvoidedThisMonth;
    }
    if (carrierSavings != null) {
      total += carrierSavings!.totalEarnedThisMonth;
    }
    return total;
  }

  PersonalSavings copyWith({
    RequesterSavings? requesterSavings,
    CarrierSavings? carrierSavings,
    bool? hasRequesterData,
    bool? hasCarrierData,
  }) =>
      PersonalSavings(
        requesterSavings: requesterSavings ?? this.requesterSavings,
        carrierSavings: carrierSavings ?? this.carrierSavings,
        hasRequesterData: hasRequesterData ?? this.hasRequesterData,
        hasCarrierData: hasCarrierData ?? this.hasCarrierData,
      );

  factory PersonalSavings.fromJson(Map<String, dynamic> json) =>
      PersonalSavings(
        requesterSavings: json['requester_savings'] != null
            ? RequesterSavings.fromJson(
                json['requester_savings'] as Map<String, dynamic>)
            : null,
        carrierSavings: json['carrier_savings'] != null
            ? CarrierSavings.fromJson(
                json['carrier_savings'] as Map<String, dynamic>)
            : null,
        hasRequesterData: json['has_requester_data'] as bool? ?? false,
        hasCarrierData: json['has_carrier_data'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'requester_savings': requesterSavings?.toJson(),
        'carrier_savings': carrierSavings?.toJson(),
        'has_requester_data': hasRequesterData,
        'has_carrier_data': hasCarrierData,
      };
}
