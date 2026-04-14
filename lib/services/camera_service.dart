// lib/services/camera_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// DISHA — Camera frame capture
// Provides a stream of JPEG bytes throttled to kTargetFps
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import '../core/constants.dart';

class CameraService {
  CameraController? _controller;
  bool _processing = false;
  DateTime _lastFrame = DateTime(2000);

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  final _frameController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get frames => _frameController.stream;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init(List<CameraDescription> cameras) async {
    // Prefer back camera
    final cam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      cam,
      ResolutionPreset.medium, // ~640×480; we downscale to 320 for YOLO
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();

    _controller!.startImageStream(_onFrame);
  }

  // ── Frame callback ────────────────────────────────────────────────────────

  void _onFrame(CameraImage cameraImage) {
    // Throttle to kTargetFps
    final now = DateTime.now();
    final minInterval = Duration(
      milliseconds: (1000 / kTargetFps).round(),
    );
    if (now.difference(_lastFrame) < minInterval) return;
    if (_processing) return;

    _processing = true;
    _lastFrame  = now;

    try {
      final jpeg = _cameraImageToJpeg(cameraImage);
      if (jpeg != null && !_frameController.isClosed) {
        _frameController.add(jpeg);
      }
    } finally {
      _processing = false;
    }
  }

  // ── CameraImage → JPEG bytes ──────────────────────────────────────────────

  Uint8List? _cameraImageToJpeg(CameraImage cameraImage) {
    try {
      img.Image image;

      if (cameraImage.format.group == ImageFormatGroup.jpeg) {
        // Already JPEG on some devices
        return Uint8List.fromList(cameraImage.planes[0].bytes);
      } else {
        // YUV420 → RGB
        image = _convertYuv420ToImage(cameraImage);
      }

      // Encode as JPEG (quality 85 — good balance of size vs quality)
      return Uint8List.fromList(img.encodeJpg(image, quality: 85));
    } catch (_) {
      return null;
    }
  }

  img.Image _convertYuv420ToImage(CameraImage cameraImage) {
    final width  = cameraImage.width;
    final height = cameraImage.height;

    final yPlane  = cameraImage.planes[0];
    final uPlane  = cameraImage.planes[1];
    final vPlane  = cameraImage.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 2;

    final image = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIdx = y * yPlane.bytesPerRow + x;
        final uvIdx = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        final yVal = yBytes[yIdx];
        final uVal = uBytes[uvIdx];
        final vVal = vBytes[uvIdx];

        // YUV → RGB
        int r = (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
        int g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
            .round()
            .clamp(0, 255);
        int b = (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);

        image.setPixelRgb(x, y, r, g, b);
      }
    }
    return image;
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _controller?.stopImageStream();
    await _controller?.dispose();
    await _frameController.close();
    _controller = null;
  }
}