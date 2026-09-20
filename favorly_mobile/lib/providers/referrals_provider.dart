import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/referrals_models.dart';
import '../services/api_client.dart';
import 'auth_provider.dart';

/// Get referral stats for the current user.
final referralStatsProvider = FutureProvider<ReferralStats>((ref) async {
  final authState = ref.watch(authProvider);
  final userId = authState.userId;

  if (userId == null) {
    throw Exception('User not logged in');
  }

  final accessToken = authState.accessToken;
  if (accessToken == null) {
    throw Exception('No access token');
  }

  try {
    final response = await ApiClient.getReferralStats(
      userId: userId,
      accessToken: accessToken,
    );
    return ReferralStats.fromJson(response);
  } catch (e) {
    throw Exception('Failed to fetch referral stats: $e');
  }
});

/// Check if user just earned referral rewards (e.g., after a settlement).
final checkReferralRewardsProvider =
    FutureProvider.family<List<ReferralReward>, String>((ref, userId) async {
  final authState = ref.watch(authProvider);
  final accessToken = authState.accessToken;

  if (accessToken == null) {
    throw Exception('No access token');
  }

  try {
    final response = await ApiClient.checkNewReferralRewards(
      userId: userId,
      accessToken: accessToken,
    );
    final rewards = (response['earned_rewards'] as List<dynamic>?)
            ?.map((r) => ReferralReward.fromJson(r as Map<String, dynamic>))
            .toList() ??
        [];
    return rewards;
  } catch (e) {
    throw Exception('Failed to check referral rewards: $e');
  }
});
