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

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/constants.dart';
import '../core/models.dart';

class YoloService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _ready = false;
  bool _isNHWC = false;
  List<int> _outputShape = [];

  // Cached memory arrays so we don't trigger GC lockups every frame
  Object? _outputTensor;

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
    // Check exact shapes
    final inShape = _interpreter!.getInputTensors()[0].shape;
    _outputShape = _interpreter!.getOutputTensors()[0].shape;
    _isNHWC = inShape.last == 3;

    Object allocate(List<int> shape, int index) {
      if (index == shape.length - 1) return List.filled(shape[index], 0.0);
      return List.generate(shape[index], (_) => allocate(shape, index + 1));
    }
    
    _outputTensor = allocate(_outputShape, 0);

    _ready = true;
  }

  // ── Run inference ─────────────────────────────────────────────────────────

  Future<List<Detection>> runOnCameraImage(CameraImage image) async {
    if (!_ready || _interpreter == null) return [];

    // The raw camera buffer is now a JPEG!
    final jpegBytes = image.planes[0].bytes;

    // Offload heavy image decoding and matrix manipulation to an Isolate
    // so the main UI thread never freezes or drops frames again!
    final tensor = await compute(_buildTensorInIsolate, {
      'jpegBytes': jpegBytes,
      'isNHWC': _isNHWC,
      'size': kModelInputSize
    });

    if (tensor.isEmpty || _outputTensor == null) return [];

    _interpreter!.run(tensor, _outputTensor!);

    return _parseOutput(_outputTensor!);
  }

  // ── Parse YOLOv8 output ───────────────────────────────────────────────────

  List<Detection> _parseOutput(Object outputObj) {
    if (_outputShape.length != 3) return [];
    
    final out = outputObj as List<dynamic>;
    final nested = out[0] as List<dynamic>;
    
    final firstDim = _outputShape[1];
    final isTransposed = firstDim >= 1000; // [1, 8400, 84] vs [1, 84, 8400]
    final numAnchors = isTransposed ? _outputShape[1] : _outputShape[2];
    
    final rawDetections = <_RawBox>[];

    for (int a = 0; a < numAnchors; a++) {
      final cx = isTransposed ? nested[a][0] : nested[0][a];
      final cy = isTransposed ? nested[a][1] : nested[1][a];
      final w  = isTransposed ? nested[a][2] : nested[2][a];
      final h  = isTransposed ? nested[a][3] : nested[3][a];

      // Find best class
      double bestScore = 0;
      int bestClass = 0;
      for (int c = 4; c < 84; c++) {
        double score = isTransposed ? nested[a][c] : nested[c][a];
        if (score > bestScore) {
          bestScore = score;
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

// ── ISOLATE TOP-LEVEL FUNCTION ─────────────────────────────────────────────
// This runs on a separate CPU thread to protect the UI!
List<dynamic> _buildTensorInIsolate(Map<String, dynamic> args) {
  final Uint8List jpegBytes = args['jpegBytes'];
  final bool isNHWC = args['isNHWC'];
  final int size = args['size'];

  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) return [];

  // 1. Rotate upright (Sensor is landscape by default)
  final rotated = img.copyRotate(decoded, angle: 90);
  
  // 2. Scale exactly to YOLO requirements (320x320)
  final resized = img.copyResize(rotated, width: size, height: size);

  // 3. Build shape: [1][c][y][x] or [1][y][x][c]
  if (isNHWC) {
    // NHWC: [1][320][320][3]
    return List.generate(1, (_) => List.generate(size, (y) => List.generate(size, (x) {
      final pixel = resized.getPixel(x, y);
      return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
    })));
  } else {
    // CHW: [1][3][320][320]
    return List.generate(1, (_) => List.generate(3, (c) => List.generate(size, (y) => List.generate(size, (x) {
        final pixel = resized.getPixel(x, y);
        if (c == 0) return pixel.r / 255.0;
        if (c == 1) return pixel.g / 255.0;
        return pixel.b / 255.0;
    }))));
  }
}