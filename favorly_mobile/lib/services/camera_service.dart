import 'dart:io';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class CameraService {
  late CameraController? _controller;
  List<CameraDescription>? _cameras;

  Future<void> initialize() async {
    _cameras = await availableCameras();
  }

  CameraController? get controller => _controller;
  List<CameraDescription>? get cameras => _cameras;

  Future<void> initializeCamera({
    CameraDescription? camera,
    bool useFrontCamera = false,
  }) async {
    if (_cameras == null || _cameras!.isEmpty) {
      throw Exception('No cameras available');
    }

    final selectedCamera =
        camera ?? _selectCamera(useFrontCamera: useFrontCamera);
    if (selectedCamera == null) {
      throw Exception('Camera not available');
    }

    _controller = CameraController(
      selectedCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _controller!.initialize();
  }

  CameraDescription? _selectCamera({required bool useFrontCamera}) {
    if (_cameras == null || _cameras!.isEmpty) return null;

    if (useFrontCamera) {
      return _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );
    } else {
      return _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
    }
  }

  Future<File?> takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return null;
    }

    try {
      final image = await _controller!.takePicture();
      return File(image.path);
    } on CameraException catch (e) {
      print('Error taking picture: $e');
      return null;
    }
  }

  Future<List<File>?> pickMultipleImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();

    if (images.isEmpty) return null;
    return images.map((img) => File(img.path)).toList();
  }

  Future<File?> pickSingleImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return null;
    return File(image.path);
  }

  Future<String> saveImagePermanently(File imageFile) async {
    final appDir = await getApplicationDocumentsDirectory();
    final filename =
        'vision_${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.split('/').last}';
    final savedImage = await imageFile.copy('${appDir.path}/$filename');
    return savedImage.path;
  }

  void dispose() {
    _controller?.dispose();
  }
}
