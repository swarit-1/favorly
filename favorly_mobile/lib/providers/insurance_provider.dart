import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/insurance_models.dart';
import '../services/api_client.dart';
import 'auth_provider.dart';

/// Get insurance status for the current user.
final insuranceStatusProvider =
    FutureProvider<InsuranceStatus>((ref) async {
  final authState = ref.watch(authProvider);
  final userId = authState.userId;

  if (userId == null) {
    throw Exception('User not authenticated');
  }

  final accessToken = authState.accessToken;
  if (accessToken == null) {
    throw Exception('No access token');
  }

  try {
    final response = await ApiClient.getInsuranceStatus(
      userId: userId,
      accessToken: accessToken,
    );
    return InsuranceStatus.fromJson(response);
  } catch (e) {
    throw Exception('Failed to fetch insurance status: $e');
  }
});

/// Check if current user is insurance-eligible.
final insuranceEligibleProvider =
    FutureProvider<bool>((ref) async {
  final authState = ref.watch(authProvider);
  final userId = authState.userId;

  if (userId == null) {
    throw Exception('User not authenticated');
  }

  final accessToken = authState.accessToken;
  if (accessToken == null) {
    throw Exception('No access token');
  }

  try {
    final response = await ApiClient.checkInsuranceEligible(
      userId: userId,
      accessToken: accessToken,
    );
    return response['eligible'] as bool? ?? false;
  } catch (e) {
    throw Exception('Failed to check insurance eligibility: $e');
  }
});
