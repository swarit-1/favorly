import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/camera_service.dart';

class CapturedPhoto {
  const CapturedPhoto({
    required this.id,
    required this.filePath,
    required this.capturedAt,
    this.displayName,
  });

  final String id;
  final String filePath;
  final DateTime capturedAt;
  final String? displayName;

  CapturedPhoto copyWith({
    String? id,
    String? filePath,
    DateTime? capturedAt,
    String? displayName,
  }) {
    return CapturedPhoto(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      capturedAt: capturedAt ?? this.capturedAt,
      displayName: displayName ?? this.displayName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CapturedPhoto &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          filePath == other.filePath &&
          capturedAt == other.capturedAt &&
          displayName == other.displayName;

  @override
  int get hashCode =>
      id.hashCode ^
      filePath.hashCode ^
      capturedAt.hashCode ^
      displayName.hashCode;
}

class VisionAnalysisResult {
  const VisionAnalysisResult({
    required this.analysisId,
    required this.domainType,
    required this.result,
    required this.analyzedAt,
    this.isFromCache = false,
  });

  final String analysisId;
  final String domainType;
  final Map<String, dynamic> result;
  final DateTime analyzedAt;
  final bool isFromCache;

  VisionAnalysisResult copyWith({
    String? analysisId,
    String? domainType,
    Map<String, dynamic>? result,
    DateTime? analyzedAt,
    bool? isFromCache,
  }) {
    return VisionAnalysisResult(
      analysisId: analysisId ?? this.analysisId,
      domainType: domainType ?? this.domainType,
      result: result ?? this.result,
      analyzedAt: analyzedAt ?? this.analyzedAt,
      isFromCache: isFromCache ?? this.isFromCache,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VisionAnalysisResult &&
          runtimeType == other.runtimeType &&
          analysisId == other.analysisId &&
          domainType == other.domainType &&
          result == other.result &&
          analyzedAt == other.analyzedAt &&
          isFromCache == other.isFromCache;

  @override
  int get hashCode =>
      analysisId.hashCode ^
      domainType.hashCode ^
      result.hashCode ^
      analyzedAt.hashCode ^
      isFromCache.hashCode;
}

class VisionSessionState {
  const VisionSessionState({
    this.capturedPhotos = const [],
    this.analysisResults = const [],
    this.currentlyCapturing,
    this.isUploading = false,
    this.uploadError,
    this.lastAnalysis,
  });

  final List<CapturedPhoto> capturedPhotos;
  final List<VisionAnalysisResult> analysisResults;
  final CapturedPhoto? currentlyCapturing;
  final bool isUploading;
  final String? uploadError;
  final VisionAnalysisResult? lastAnalysis;

  VisionSessionState copyWith({
    List<CapturedPhoto>? capturedPhotos,
    List<VisionAnalysisResult>? analysisResults,
    CapturedPhoto? currentlyCapturing,
    bool? isUploading,
    String? uploadError,
    VisionAnalysisResult? lastAnalysis,
  }) {
    return VisionSessionState(
      capturedPhotos: capturedPhotos ?? this.capturedPhotos,
      analysisResults: analysisResults ?? this.analysisResults,
      currentlyCapturing: currentlyCapturing ?? this.currentlyCapturing,
      isUploading: isUploading ?? this.isUploading,
      uploadError: uploadError ?? this.uploadError,
      lastAnalysis: lastAnalysis ?? this.lastAnalysis,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VisionSessionState &&
          runtimeType == other.runtimeType &&
          capturedPhotos == other.capturedPhotos &&
          analysisResults == other.analysisResults &&
          currentlyCapturing == other.currentlyCapturing &&
          isUploading == other.isUploading &&
          uploadError == other.uploadError &&
          lastAnalysis == other.lastAnalysis;

  @override
  int get hashCode =>
      capturedPhotos.hashCode ^
      analysisResults.hashCode ^
      currentlyCapturing.hashCode ^
      isUploading.hashCode ^
      uploadError.hashCode ^
      lastAnalysis.hashCode;
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
