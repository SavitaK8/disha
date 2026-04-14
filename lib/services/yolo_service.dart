// lib/services/yolo_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// DISHA — YOLOv8n TFLite inference
//
// Model layout (YOLOv8n exported with --imgsz 320):
//   Input : [1, 3, 320, 320]  float32   (RGB, normalised 0–1)
//   Output: [1, 84, 8400]     float32
//            84 = 4 (cx,cy,w,h) + 80 COCO classes
//            8400 = anchors
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/constants.dart';
import '../core/models.dart';

class YoloService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _ready = false;

  bool get isReady => _ready;

  // ── Initialise ────────────────────────────────────────────────────────────

  Future<void> init() async {
    // Load labels
    final raw = await rootBundle.loadString('assets/labels/coco_labels.txt');
    _labels = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Load model
    final interpreterOptions = InterpreterOptions()..threads = 4;
    _interpreter = await Interpreter.fromAsset(
      'assets/models/yolov8n_320.tflite',
      options: interpreterOptions,
    );

    _ready = true;
  }

  // ── Run inference ─────────────────────────────────────────────────────────

  /// [jpegBytes] — raw JPEG/PNG from CameraImage converted to bytes
  List<Detection> runOnBytes(Uint8List jpegBytes) {
    if (!_ready || _interpreter == null) return [];

    // Decode → resize to 320×320
    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) return [];
    final resized = img.copyResize(
      decoded,
      width: kModelInputSize,
      height: kModelInputSize,
    );

    // Build float32 tensor [1, 3, 320, 320]  (CHW, 0-1 normalised)
    final input = _buildInputTensor(resized);

    // Output: [1, 84, 8400]
    final outputShape = [1, 84, 8400];
    final outputData =
        List.generate(1, (_) => List.generate(84, (_) => Float32List(8400)));

    _interpreter!.run(input, outputData);

    return _parseOutput(outputData[0]);
  }

  // ── Tensor builder ────────────────────────────────────────────────────────

  List<List<List<List<double>>>> _buildInputTensor(img.Image image) {
    // Shape [1][3][320][320]
    final tensor = List.generate(
      1,
      (_) => List.generate(
        3,
        (c) => List.generate(
          kModelInputSize,
          (y) => List.generate(kModelInputSize, (x) {
            final pixel = image.getPixel(x, y);
            if (c == 0) return pixel.r / 255.0;
            if (c == 1) return pixel.g / 255.0;
            return pixel.b / 255.0;
          }),
        ),
      ),
    );
    return tensor;
  }

  // ── Parse YOLOv8 output ───────────────────────────────────────────────────

  List<Detection> _parseOutput(List<List<double>> output) {
    // output[row][anchor]  row 0-3 = cx,cy,w,h   row 4-83 = class scores
    final numAnchors = output[0].length; // 8400
    final rawDetections = <_RawBox>[];

    for (int a = 0; a < numAnchors; a++) {
      final cx = output[0][a];
      final cy = output[1][a];
      final w  = output[2][a];
      final h  = output[3][a];

      // Find best class
      double bestScore = 0;
      int bestClass = 0;
      for (int c = 4; c < 84; c++) {
        if (output[c][a] > bestScore) {
          bestScore = output[c][a];
          bestClass = c - 4;
        }
      }

      if (bestScore < kConfidenceThreshold) continue;
      if (bestClass >= _labels.length) continue;

      rawDetections.add(_RawBox(
        cx: cx,
        cy: cy,
        w: w,
        h: h,
        score: bestScore,
        classIdx: bestClass,
        label: _labels[bestClass],
      ));
    }

    return _nms(rawDetections);
  }

  // ── Non-maximum suppression ───────────────────────────────────────────────

  List<Detection> _nms(List<_RawBox> boxes) {
    boxes.sort((a, b) => b.score.compareTo(a.score));
    final kept = <_RawBox>[];

    for (final box in boxes) {
      bool suppressed = false;
      for (final k in kept) {
        if (k.label != box.label) continue;
        if (_iou(box, k) > kIouThreshold) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) kept.add(box);
    }

    return kept.map((b) {
      final x = (b.cx - b.w / 2).clamp(0.0, kModelInputSize.toDouble());
      final y = (b.cy - b.h / 2).clamp(0.0, kModelInputSize.toDouble());
      return Detection(
        label: b.label,
        confidence: b.score,
        bbox: BoundingBox(x: x, y: y, width: b.w, height: b.h),
      );
    }).toList();
  }

  double _iou(_RawBox a, _RawBox b) {
    final ax1 = a.cx - a.w / 2, ay1 = a.cy - a.h / 2;
    final ax2 = a.cx + a.w / 2, ay2 = a.cy + a.h / 2;
    final bx1 = b.cx - b.w / 2, by1 = b.cy - b.h / 2;
    final bx2 = b.cx + b.w / 2, by2 = b.cy + b.h / 2;

    final ix1 = math.max(ax1, bx1), iy1 = math.max(ay1, by1);
    final ix2 = math.min(ax2, bx2), iy2 = math.min(ay2, by2);
    if (ix2 < ix1 || iy2 < iy1) return 0;

    final inter = (ix2 - ix1) * (iy2 - iy1);
    final areaA = a.w * a.h, areaB = b.w * b.h;
    return inter / (areaA + areaB - inter);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _ready = false;
  }
}

class _RawBox {
  final double cx, cy, w, h, score;
  final int classIdx;
  final String label;
  const _RawBox({
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
    required this.score,
    required this.classIdx,
    required this.label,
  });
}