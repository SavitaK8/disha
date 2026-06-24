import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraService {
  CameraController? _controller;
  bool _isInit = false;
  final StreamController<CameraImage> _frameController =
      StreamController<CameraImage>.broadcast();

  CameraController? get controller => _controller;
  Stream<CameraImage> get frames => _frameController.stream;
  bool get isInitialized => _isInit;

  Future<void> init() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw Exception('No cameras available');
    }

    // Use standard back camera
    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      backCamera,
      ResolutionPreset.low, // 240p is fastest for CNN and prevents Out of Memory crashes
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
    _isInit = true;

    // Start streaming raw YUV immediately
    _controller!.startImageStream((image) {
      if (!_frameController.isClosed) {
        _frameController.add(image);
      }
    });
  }

  Future<void> dispose() async {
    _isInit = false;
    await _frameController.close();
    await _controller?.stopImageStream();
    await _controller?.dispose();
  }
}
