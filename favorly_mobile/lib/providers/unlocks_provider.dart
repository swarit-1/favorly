import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/unlocks_models.dart';
import '../services/api_client.dart';
import 'auth_provider.dart';

/// Get circle unlock status (progress toward milestones).
final circleUnlocksProvider =
    FutureProvider<CircleUnlockStatus>((ref) async {
  final authState = ref.watch(authProvider);
  final circleId = authState.circleId;

  if (circleId == null) {
    throw Exception('User not in a circle');
  }

  final accessToken = authState.accessToken;
  if (accessToken == null) {
    throw Exception('No access token');
  }

  try {
    final response = await ApiClient.getUnlockStatus(
      circleId: circleId,
      accessToken: accessToken,
    );
    return CircleUnlockStatus.fromJson(response);
  } catch (e) {
    throw Exception('Failed to fetch unlock status: $e');
  }
});

/// Claim an available unlock for the circle.
final claimUnlockProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, unlockType) async {
  final authState = ref.watch(authProvider);
  final circleId = authState.circleId;

  if (circleId == null) {
    throw Exception('User not in a circle');
  }

  final accessToken = authState.accessToken;
  if (accessToken == null) {
    throw Exception('No access token');
  }

  try {
    final response = await ApiClient.claimUnlock(
      circleId: circleId,
      unlockType: unlockType,
      accessToken: accessToken,
    );
    // Invalidate the cache to refetch status
    ref.invalidate(circleUnlocksProvider);
    return response;
  } catch (e) {
    throw Exception('Failed to claim unlock: $e');
  }
});
