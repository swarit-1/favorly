import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vision_provider.dart';
import '../providers/auth_provider.dart';
import '../services/vision_api_client.dart';
import '../services/api_config.dart';

class PhotoReviewScreen extends ConsumerStatefulWidget {
  const PhotoReviewScreen({
    super.key,
    required this.photos,
    required this.domainType,
    required this.title,
    this.onAnalysisComplete,
  });

  final List<CapturedPhoto> photos;
  final String domainType;
  final String title;
  final Function(VisionAnalysisResult)? onAnalysisComplete;

  @override
  ConsumerState<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends ConsumerState<PhotoReviewScreen> {
  int _currentPhotoIndex = 0;
  bool _isAnalyzing = false;
  String? _analysisError;

  Future<void> _analyzePhotos() async {
    setState(() {
      _isAnalyzing = true;
      _analysisError = null;
    });

    try {
      // Get auth credentials from auth provider
      final authState = ref.read(authProvider);
      final baseUrl = ApiConfig.baseUrl;

      if (authState.userId == null || authState.accessToken == null) {
        throw Exception('Not authenticated');
      }

      final apiClient = VisionApiClient(
        baseUrl: baseUrl,
        authToken: authState.accessToken!,
      );

      final imageFiles = widget.photos
          .map((photo) => File(photo.filePath))
          .toList();

      late Map<String, dynamic> analysisResult;

      // Route to appropriate analysis method based on domain
      switch (widget.domainType) {
        case 'grocery_shopping':
          analysisResult = await apiClient.analyzePantry(
            imageFiles,
            userId: authState.userId!,
          );
          break;
        case 'home_repair':
          analysisResult = await apiClient.analyzeDamage(
            imageFiles,
            userId: authState.userId!,
            roomOrArea: null,
          );
          break;
        case 'yard_work':
          analysisResult = await apiClient.analyzeYardMaintenance(
            imageFiles,
            userId: authState.userId!,
          );
          break;
        case 'pet_sitting':
          analysisResult = await apiClient.assessPet(
            imageFiles,
            userId: authState.userId!,
            petInfo: {},
          );
          break;
        case 'cleaning':
          analysisResult = await apiClient.analyzeCleaningNeeds(
            imageFiles,
            userId: authState.userId!,
            roomType: null,
          );
          break;
        default:
          throw Exception('Unknown domain type: ${widget.domainType}');
      }

      // Create analysis result
      final result = VisionAnalysisResult(
        analysisId: DateTime.now().millisecondsSinceEpoch.toString(),
        domainType: widget.domainType,
        result: analysisResult,
        analyzedAt: DateTime.now(),
      );

      // Add to state
      ref.read(visionSessionProvider.notifier).addAnalysisResult(result);

      // Call callback
      widget.onAnalysisComplete?.call(result);

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Analysis complete!')));

        // Wait a moment then go back
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.pop(context, result);
        }
      }
    } catch (e) {
      setState(() {
        _analysisError = e.toString();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Analysis failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  void _removePhoto(String photoId) {
    ref.read(visionSessionProvider.notifier).removeCapturedPhoto(photoId);

    if (widget.photos.length <= 1) {
      Navigator.pop(context);
    } else if (_currentPhotoIndex >= widget.photos.length - 1) {
      setState(() {
        _currentPhotoIndex--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(visionSessionProvider).capturedPhotos;

    if (photos.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review Photos')),
        body: const Center(child: Text('No photos captured')),
      );
    }

    final currentPhoto = photos[_currentPhotoIndex];

    return Scaffold(
      appBar: AppBar(title: Text(widget.title), elevation: 0),
      body: Stack(
        children: [
          // Photo viewer
          Column(
            children: [
              Expanded(
                child: Center(
                  child: Image.file(
                    File(currentPhoto.filePath),
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              // Photo carousel indicator
              Container(
                color: Colors.grey[900],
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    photos.length,
                    (index) => GestureDetector(
                      onTap: () {
                        setState(() {
                          _currentPhotoIndex = index;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: index == _currentPhotoIndex
                                ? Colors.white
                                : Colors.grey,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: Image.file(
                            File(photos[index].filePath),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Action buttons
              Container(
                color: Colors.grey[900],
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isAnalyzing
                                ? null
                                : () => _removePhoto(currentPhoto.id),
                            icon: const Icon(Icons.delete),
                            label: const Text('Remove'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isAnalyzing ? null : _analyzePhotos,
                            icon: _isAnalyzing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.send),
                            label: Text(
                              _isAnalyzing ? 'Analyzing...' : 'Analyze Photos',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_analysisError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[900],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _analysisError ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Photo counter
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                '${_currentPhotoIndex + 1}/${photos.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
