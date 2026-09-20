/// Collective unlocks and building-wide milestone models.

class UnlockType {
  static const pizzaNight = 'pizza_night';
  static const coffeeMachine = 'coffee_machine';
  static const lobbyUpgrade = 'lobby_upgrade';
  static const communityLunch = 'community_lunch';
}

class CircleUnlock {
  const CircleUnlock({
    required this.id,
    required this.circleId,
    required this.unlockType,
    required this.rewardDescription,
    required this.favorsAtUnlock,
    required this.claimedAt,
  });

  final String id;
  final String circleId;
  final String unlockType;
  final String rewardDescription;
  final int favorsAtUnlock;
  final DateTime claimedAt;

  String get emoji {
    switch (unlockType) {
      case UnlockType.pizzaNight:
        return '🍕';
      case UnlockType.coffeeMachine:
        return '☕';
      case UnlockType.communityLunch:
        return '🎉';
      case UnlockType.lobbyUpgrade:
        return '🏢';
      default:
        return '🎁';
    }
  }

  factory CircleUnlock.fromJson(Map<String, dynamic> json) {
    return CircleUnlock(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      unlockType: json['unlock_type'] as String,
      rewardDescription: json['reward_description'] as String,
      favorsAtUnlock: json['favors_at_unlock'] as int,
      claimedAt: DateTime.parse(json['claimed_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'circle_id': circleId,
    'unlock_type': unlockType,
    'reward_description': rewardDescription,
    'favors_at_unlock': favorsAtUnlock,
    'claimed_at': claimedAt.toIso8601String(),
  };
}

class CircleUnlockStatus {
  const CircleUnlockStatus({
    required this.circleId,
    required this.favorsThisMonth,
    required this.progressPercentage,
    this.nextMilestoneThreshold,
    this.nextMilestoneDescription,
    this.nextMilestoneFavorsRemaining,
    required this.claimedUnlocks,
    required this.availableUnlocks,
  });

  final String circleId;
  final int favorsThisMonth;
  final double progressPercentage;
  final int? nextMilestoneThreshold;
  final String? nextMilestoneDescription;
  final int? nextMilestoneFavorsRemaining;
  final List<CircleUnlock> claimedUnlocks;
  final List<String> availableUnlocks;

  bool get hasAvailableUnlocks => availableUnlocks.isNotEmpty;

  String get progressLabel {
    if (nextMilestoneThreshold == null) {
      return '🌟 All milestones unlocked!';
    }
    return '${favorsThisMonth}/${nextMilestoneThreshold} favors';
  }

  factory CircleUnlockStatus.fromJson(Map<String, dynamic> json) {
    return CircleUnlockStatus(
      circleId: json['circle_id'] as String,
      favorsThisMonth: json['favors_this_month'] as int,
      progressPercentage:
          double.parse((json['progress_percentage'] as dynamic).toString()),
      nextMilestoneThreshold:
          json['next_milestone_threshold'] as int?,
      nextMilestoneDescription:
          json['next_milestone_description'] as String?,
      nextMilestoneFavorsRemaining:
          json['next_milestone_favors_remaining'] as int?,
      claimedUnlocks: (json['claimed_unlocks'] as List<dynamic>?)
              ?.map((u) => CircleUnlock.fromJson(u as Map<String, dynamic>))
              .toList() ??
          [],
      availableUnlocks:
          (json['available_unlocks'] as List<dynamic>?)
              ?.map((u) => u as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'circle_id': circleId,
    'favors_this_month': favorsThisMonth,
    'progress_percentage': progressPercentage,
    'next_milestone_threshold': nextMilestoneThreshold,
    'next_milestone_description': nextMilestoneDescription,
    'next_milestone_favors_remaining': nextMilestoneFavorsRemaining,
    'claimed_unlocks':
        claimedUnlocks.map((u) => u.toJson()).toList(),
    'available_unlocks': availableUnlocks,
  };

  CircleUnlockStatus copyWith({
    String? circleId,
    int? favorsThisMonth,
    double? progressPercentage,
    int? nextMilestoneThreshold,
    String? nextMilestoneDescription,
    int? nextMilestoneFavorsRemaining,
    List<CircleUnlock>? claimedUnlocks,
    List<String>? availableUnlocks,
  }) {
    return CircleUnlockStatus(
      circleId: circleId ?? this.circleId,
      favorsThisMonth: favorsThisMonth ?? this.favorsThisMonth,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      nextMilestoneThreshold:
          nextMilestoneThreshold ?? this.nextMilestoneThreshold,
      nextMilestoneDescription:
          nextMilestoneDescription ?? this.nextMilestoneDescription,
      nextMilestoneFavorsRemaining: nextMilestoneFavorsRemaining ??
          this.nextMilestoneFavorsRemaining,
      claimedUnlocks: claimedUnlocks ?? this.claimedUnlocks,
      availableUnlocks: availableUnlocks ?? this.availableUnlocks,
    );
  }
}
