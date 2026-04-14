// lib/ui/detection_painter.dart
// ─────────────────────────────────────────────────────────────────────────────
// DISHA — CustomPainter that overlays bounding boxes on the camera preview
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/models.dart';

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final List<ConfirmedObstacle> confirmed;
  final Size previewSize; // native camera frame size

  DetectionPainter({
    required this.detections,
    required this.confirmed,
    required this.previewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width  / kModelInputSize;
    final scaleY = size.height / kModelInputSize;

    for (final d in detections) {
      final isConfirmed = confirmed.any((c) => c.label == d.label);
      _drawBox(canvas, d, scaleX, scaleY, isConfirmed);
    }

    // Draw path zone indicator (centre 40% vertical lines)
    _drawPathZone(canvas, size);
  }

  void _drawBox(
    Canvas canvas,
    Detection d,
    double scaleX,
    double scaleY,
    bool isConfirmed,
  ) {
    final color = _colorForLabel(d.label, isConfirmed);

    final rect = Rect.fromLTWH(
      d.bbox.x * scaleX,
      d.bbox.y * scaleY,
      d.bbox.width * scaleX,
      d.bbox.height * scaleY,
    );

    // Box stroke
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isConfirmed ? 2.5 : 1.5,
    );

    // Semi-transparent fill
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withAlpha(isConfirmed ? 40 : 15)
        ..style = PaintingStyle.fill,
    );

    // Label chip
    final label =
        '${d.label} ${(d.confidence * 100).toStringAsFixed(0)}%';
    final tp = TextPainter(
      text: TextSpan(
        text: ' $label ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight:
              isConfirmed ? FontWeight.bold : FontWeight.normal,
          backgroundColor: color.withAlpha(200),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(rect.left, rect.top - 16));
  }

  void _drawPathZone(Canvas canvas, Size size) {
    final margin = size.width * (1 - kPathCenterFraction) / 2;
    final paint = Paint()
      ..color = Colors.white.withAlpha(25)
      ..style = PaintingStyle.fill;

    // Left exclusion zone
    canvas.drawRect(Rect.fromLTWH(0, 0, margin, size.height), paint);
    // Right exclusion zone
    canvas.drawRect(
        Rect.fromLTWH(size.width - margin, 0, margin, size.height), paint);

    // Centre line (dashed) — just a thin vertical line for simplicity
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      Paint()
        ..color = Colors.white.withAlpha(40)
        ..strokeWidth = 1,
    );
  }

  Color _colorForLabel(String label, bool isConfirmed) {
    if (!isConfirmed) return Colors.grey;
    if (kClassCritical.contains(label))    return Colors.red;
    if (kClassConditional.contains(label)) return Colors.orange;
    if (kClassContext.contains(label))     return Colors.blue;
    return Colors.grey;
  }

  @override
  bool shouldRepaint(DetectionPainter old) =>
      old.detections != detections || old.confirmed != confirmed;
}