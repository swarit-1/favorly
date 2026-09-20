import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../services/camera_service.dart';

part 'vision_provider.freezed.dart';

@freezed
class CapturedPhoto with _$CapturedPhoto {
  const factory CapturedPhoto({
    required String id,
    required String filePath,
    required DateTime capturedAt,
    String? displayName,
  }) = _CapturedPhoto;
}

@freezed
class VisionAnalysisResult with _$VisionAnalysisResult {
  const factory VisionAnalysisResult({
    required String analysisId,
    required String domainType,
    required Map<String, dynamic> result,
    required DateTime analyzedAt,
    @Default(false) bool isFromCache,
  }) = _VisionAnalysisResult;
}

@freezed
class VisionSessionState with _$VisionSessionState {
  const factory VisionSessionState({
    @Default([]) List<CapturedPhoto> capturedPhotos,
    @Default([]) List<VisionAnalysisResult> analysisResults,
    @Default(null) CapturedPhoto? currentlyCapturing,
    @Default(false) bool isUploading,
    @Default(null) String? uploadError,
    @Default(null) VisionAnalysisResult? lastAnalysis,
  }) = _VisionSessionState;
}

// Camera service provider
final cameraServiceProvider = Provider<CameraService>((ref) {
  return CameraService();
});

// Vision session state provider
final visionSessionProvider =
    StateNotifierProvider<VisionSessionNotifier, VisionSessionState>((ref) {
  return VisionSessionNotifier();
});

class VisionSessionNotifier extends StateNotifier<VisionSessionState> {
  VisionSessionNotifier() : super(const VisionSessionState());

  void addCapturedPhoto(CapturedPhoto photo) {
    state = state.copyWith(
      capturedPhotos: [...state.capturedPhotos, photo],
    );
  }

  void removeCapturedPhoto(String photoId) {
    state = state.copyWith(
      capturedPhotos: state.capturedPhotos
          .where((photo) => photo.id != photoId)
          .toList(),
    );
  }

  void clearCapturedPhotos() {
    state = state.copyWith(
      capturedPhotos: [],
      uploadError: null,
    );
  }

  void setUploading(bool isUploading) {
    state = state.copyWith(isUploading: isUploading);
  }

  void setUploadError(String? error) {
    state = state.copyWith(uploadError: error);
  }

  void addAnalysisResult(VisionAnalysisResult result) {
    state = state.copyWith(
      analysisResults: [...state.analysisResults, result],
      lastAnalysis: result,
    );
  }

  void setCurrentlyCapturing(CapturedPhoto? photo) {
    state = state.copyWith(currentlyCapturing: photo);
  }

  void reset() {
    state = const VisionSessionState();
  }
}

// Selected domain for vision analysis
final selectedDomainProvider = StateProvider<String>((ref) {
  return 'grocery_shopping'; // Default domain
});

// Photo gallery provider
final capturedPhotosProvider =
    Provider.family<CapturedPhoto?, String>((ref, photoId) {
  final session = ref.watch(visionSessionProvider);
  return session.capturedPhotos.firstWhere(
    (photo) => photo.id == photoId,
    orElse: () => throw Exception('Photo not found'),
  );
});
