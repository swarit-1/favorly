/// Invite codes and referral reward models.

class ReferralReward {
  const ReferralReward({
    required this.id,
    required this.referrerId,
    required this.referreeId,
    required this.karmaEarned,
    required this.completedFavorId,
    required this.earnedAt,
    this.description = 'Recruit-a-neighbor bonus',
  });

  final String id;
  final String referrerId;
  final String referreeId;
  final int karmaEarned;
  final String completedFavorId;
  final DateTime earnedAt;
  final String description;

  factory ReferralReward.fromJson(Map<String, dynamic> json) {
    return ReferralReward(
      id: json['id'] as String,
      referrerId: json['referrer_id'] as String,
      referreeId: json['referree_id'] as String,
      karmaEarned: json['karma_earned'] as int,
      completedFavorId: json['completed_favor_id'] as String,
      earnedAt: DateTime.parse(json['earned_at'] as String),
      description: json['description'] as String? ?? 'Recruit-a-neighbor bonus',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'referrer_id': referrerId,
    'referree_id': referreeId,
    'karma_earned': karmaEarned,
    'completed_favor_id': completedFavorId,
    'earned_at': earnedAt.toIso8601String(),
    'description': description,
  };
}

class ReferralStats {
  const ReferralStats({
    required this.userId,
    required this.inviteCode,
    required this.totalReferred,
    required this.totalKarmaEarned,
    this.referrals = const [],
  });

  final String userId;
  final String inviteCode;
  final int totalReferred;
  final int totalKarmaEarned;
  final List<ReferralReward> referrals;

  String get karmaLabel =>
      totalKarmaEarned == 0 ? 'No karma yet' : '+$totalKarmaEarned karma earned';

  factory ReferralStats.fromJson(Map<String, dynamic> json) {
    return ReferralStats(
      userId: json['user_id'] as String,
      inviteCode: json['invite_code'] as String,
      totalReferred: json['total_referred'] as int,
      totalKarmaEarned: json['total_karma_earned'] as int,
      referrals: (json['referrals'] as List<dynamic>?)
              ?.map((r) => ReferralReward.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'invite_code': inviteCode,
    'total_referred': totalReferred,
    'total_karma_earned': totalKarmaEarned,
    'referrals': referrals.map((r) => r.toJson()).toList(),
  };

  ReferralStats copyWith({
    String? userId,
    String? inviteCode,
    int? totalReferred,
    int? totalKarmaEarned,
    List<ReferralReward>? referrals,
  }) {
    return ReferralStats(
      userId: userId ?? this.userId,
      inviteCode: inviteCode ?? this.inviteCode,
      totalReferred: totalReferred ?? this.totalReferred,
      totalKarmaEarned: totalKarmaEarned ?? this.totalKarmaEarned,
      referrals: referrals ?? this.referrals,
    );
  }
}
