// lib/core/models.dart
// ─────────────────────────────────────────────────────────────────────────────
// DISHA — Data models used across the pipeline
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

// ── Raw YOLO output ────────────────────────────────────────────────────────────

@immutable
class BoundingBox {
  /// All values in pixels relative to the model input frame (320×320)
  final double x, y, width, height;

  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  double get centerX => x + width / 2;
  double get centerY => y + height / 2;
  double get right  => x + width;
  double get bottom => y + height;
}

@immutable
class Detection {
  final String label;
  final double confidence;
  final BoundingBox bbox;

  const Detection({
    required this.label,
    required this.confidence,
    required this.bbox,
  });
}

// ── Enriched detection (after depth fusion) ────────────────────────────────────

enum ObstacleZone { critical, warning, ambient, ignore }

enum ObjectDirection { left, center, right }

@immutable
class RichDetection extends Detection {
  /// Estimated distance in metres. -1 if unknown (no ARCore yet).
  final double distanceM;

  const RichDetection({
    required super.label,
    required super.confidence,
    required super.bbox,
    required this.distanceM,
  });
}

// ── Final confirmed obstacle ───────────────────────────────────────────────────

@immutable
class ConfirmedObstacle {
  final String label;
  final double distanceM;
  final ObstacleZone zone;
  final ObjectDirection direction;

  const ConfirmedObstacle({
    required this.label,
    required this.distanceM,
    required this.zone,
    required this.direction,
  });

  /// Short TTS string — always under 5 words
  String get ttsMessage {
    if (zone == ObstacleZone.critical) return ''; // beep only
    final dir = direction == ObjectDirection.left
        ? 'left'
        : direction == ObjectDirection.right
            ? 'right'
            : 'ahead';
    if (distanceM > 0) {
      return '$label, $dir, ${distanceM.toStringAsFixed(1)}m';
    }
    return '$label, $dir';
  }
}