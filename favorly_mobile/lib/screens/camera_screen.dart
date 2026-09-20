import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../providers/vision_provider.dart';
import '../services/camera_service.dart';
import 'photo_review_screen.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({
    super.key,
    required this.title,
    required this.domainType,
    this.maxPhotos = 4,
    this.minPhotos = 1,
  });

  final String title;
  final String domainType;
  final int maxPhotos;
  final int minPhotos;

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  bool _isCameraInitialized = false;
  String? _initializationError;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameraService = ref.read(cameraServiceProvider);
      await cameraService.initialize();
      await cameraService.initializeCamera();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      setState(() {
        _initializationError = e.toString();
      });
    }
  }

  Future<void> _takePicture() async {
    try {
      final cameraService = ref.read(cameraServiceProvider);
      final imageFile = await cameraService.takePicture();

      if (imageFile != null && mounted) {
        // Save and add to session
        final savedPath = await cameraService.saveImagePermanently(imageFile);
        final photo = CapturedPhoto(
          id: const Uuid().v4(),
          filePath: savedPath,
          capturedAt: DateTime.now(),
          displayName: 'Photo ${ref.read(visionSessionProvider).capturedPhotos.length + 1}',
        );

        ref.read(visionSessionProvider.notifier).addCapturedPhoto(photo);

        // Show feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Photo ${ref.read(visionSessionProvider).capturedPhotos.length} captured',
            ),
            duration: const Duration(milliseconds: 500),
          ),
        );
      }
    } catch (e) {
      _showError('Failed to capture photo: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _proceedToReview() {
    final photos = ref.read(visionSessionProvider).capturedPhotos;
    if (photos.length < widget.minPhotos) {
      _showError(
        'Please capture at least ${widget.minPhotos} photo(s)',
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoReviewScreen(
          photos: photos,
          domainType: widget.domainType,
          title: widget.title,
        ),
      ),
    );
  }

  @override
  void dispose() {
    ref.read(cameraServiceProvider).dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capturedCount =
        ref.watch(visionSessionProvider).capturedPhotos.length;
    final canCapture = capturedCount < widget.maxPhotos;

    if (_initializationError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Camera Error: $_initializationError'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCameraInitialized) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final cameraService = ref.read(cameraServiceProvider);
    final controller = cameraService.controller;

    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(
          child: Text('Camera not initialized'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Camera preview
          CameraPreview(controller),

          // Overlay with hints
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Tap the circle below to capture (${capturedCount}/${widget.maxPhotos})',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (widget.domainType == 'grocery_shopping')
                    const SizedBox(height: 8)
                  else if (widget.domainType == 'home_repair')
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Capture multiple angles of the damage',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else if (widget.domainType == 'yard_work')
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Show the whole area and problem spots',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Capture button
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: canCapture ? _takePicture : null,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: canCapture ? Colors.white : Colors.grey,
                    border: Border.all(
                      color: Colors.white,
                      width: 4,
                    ),
                  ),
                  child: canCapture
                      ? null
                      : const Center(
                          child: Text(
                            'Max',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),

          // Top-right: photo count badge
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
                '$capturedCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),

          // Top-left: gallery button
          if (capturedCount > 0)
            Positioned(
              top: 16,
              left: 16,
              child: FloatingActionButton.small(
                onPressed: _proceedToReview,
                backgroundColor: Colors.black87,
                child: const Icon(Icons.check),
              ),
            ),
        ],
      ),
    );
  }
}
