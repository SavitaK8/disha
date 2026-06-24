// lib/services/reasoning_engine.dart
// ─────────────────────────────────────────────────────────────────────────────
// DISHA — 5-Stage Obstacle Filter Pipeline
//
//  Stage 1  Class relevance    → drop IGNORE bucket immediately
//  Stage 2  Zone / distance    → beyond 3.5 m = dropped
//  Stage 3  Size + geometry    → <20 cm real size = dropped
//  Stage 4  Path intersection  → outside centre 40% = dropped (or ambient)
//  Stage 5  Temporal persist.  → must appear 4+ consecutive frames
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import '../core/constants.dart';
import '../core/models.dart';

class ReasoningEngine {
  // ── Temporal tracker state ─────────────────────────────────────────────────
  // Key: label string → consecutive frame count
  final Map<String, int> _frameCount = {};
  // Labels seen last frame (to reset counters for disappeared objects)
  Set<String> _prevLabels = {};

  // ── Public entry point ─────────────────────────────────────────────────────

  /// Pass raw YOLO detections each frame. Returns only confirmed obstacles.
  List<ConfirmedObstacle> process(List<Detection> detections) {
    // Enrich with distance heuristic
    final rich = detections.map((d) => _estimateDistance(d)).toList();

    final results = <ConfirmedObstacle>[];
    final currentLabels = <String>{};

    for (final d in rich) {
      // ── Stage 1: Class relevance ──────────────────────────────────────────
      if (_isIgnored(d.label)) continue;

      // ── Stage 2: Zone / distance ──────────────────────────────────────────
      final zone = _classifyZone(d.distanceM);
      if (zone == ObstacleZone.ignore) continue;

      // ── Stage 3a: Real-world size ─────────────────────────────────────────
      if (_isTooSmall(d.bbox, d.distanceM)) continue;

      // ── Stage 3b: Ground plane — bottom 25% of frame is floor ────────────
      if (_isGroundPlane(d.bbox)) continue;

      // ── Stage 4: Path intersection ────────────────────────────────────────
      final dir = _direction(d.bbox);
      // Objects strictly off-path are downgraded to ambient or dropped
      if (!_isInPath(d.bbox) && zone == ObstacleZone.critical) {
        // Still announce as ambient if critical class but off-path
        // (edge case: a person walking past from the side)
      } else if (!_isInPath(d.bbox) && zone != ObstacleZone.ambient) {
        continue;
      }

      // ── Stage 5: Temporal persistence ────────────────────────────────────
      final key = '${d.label}_${dir.name}';
      currentLabels.add(key);
      _frameCount[key] = (_frameCount[key] ?? 0) + 1;

      if (_frameCount[key]! < kMinConfirmedFrames) continue;

      results.add(ConfirmedObstacle(
        label: d.label,
        distanceM: d.distanceM,
        zone: zone,
        direction: dir,
      ));
    }

    // Reset counters for objects that disappeared
    for (final old in _prevLabels) {
      if (!currentLabels.contains(old)) {
        _frameCount.remove(old);
      }
    }
    _prevLabels = currentLabels;

    return results;
  }

  // ── Stage 1 helper ────────────────────────────────────────────────────────

  bool _isIgnored(String label) {
    // Keep critical + conditional + context, drop everything else
    return !kClassCritical.contains(label) &&
        !kClassConditional.contains(label) &&
        !kClassContext.contains(label);
  }

  // ── Stage 2 helper ────────────────────────────────────────────────────────

  ObstacleZone _classifyZone(double dist) {
    if (dist <= 0) return ObstacleZone.warning; // unknown dist → conservative
    if (dist <= kZoneCriticalMax) return ObstacleZone.critical;
    if (dist <= kZoneWarningMax)  return ObstacleZone.warning;
    if (dist <= kZoneAmbientMax)  return ObstacleZone.ambient;
    return ObstacleZone.ignore;
  }

  // ── Stage 3 helpers ───────────────────────────────────────────────────────

  bool _isTooSmall(BoundingBox box, double distM) {
    if (distM <= 0) return false; // no depth = can't filter by size yet
    final realW = 2 *
        distM *
        math.tan(
          (box.width / kModelInputSize) *
              (kCamFovH / 2) *
              math.pi /
              180,
        );
    final realH = 2 *
        distM *
        math.tan(
          (box.height / kModelInputSize) *
              (kCamFovH / 2) *
              math.pi /
              180,
        );
    return realW < kMinRealSizeM || realH < kMinRealSizeM;
  }

  bool _isGroundPlane(BoundingBox box) {
    // If the bounding box bottom is in the bottom 25% of frame
    // AND the box top is also in the bottom 25% → floor object
    final frameH = kModelInputSize.toDouble();
    return box.y > frameH * (1 - kGroundPlaneBottomFraction);
  }

  // Stage 3b — flat surface (open door) check.
  // Requires depth samples from ARCore (Phase 3).
  // Returns false (= not flat) until real depth is available.
  bool _isFlatSurface(List<double> depthSamples) {
    if (depthSamples.isEmpty) return false;
    final mean =
        depthSamples.reduce((a, b) => a + b) / depthSamples.length;
    final variance = depthSamples
            .map((d) => math.pow(d - mean, 2))
            .reduce((a, b) => a + b) /
        depthSamples.length;
    return variance < kFlatVarianceThreshold;
  }

  // ── Stage 4 helpers ───────────────────────────────────────────────────────

  bool _isInPath(BoundingBox box) {
    final center = box.centerX;
    final frameW = kModelInputSize.toDouble();
    final margin = frameW * (1 - kPathCenterFraction) / 2;
    return center >= margin && center <= frameW - margin;
  }

  ObjectDirection _direction(BoundingBox box) {
    final center = box.centerX;
    final frameW = kModelInputSize.toDouble();
    if (center < frameW * 0.35) return ObjectDirection.left;
    if (center > frameW * 0.65) return ObjectDirection.right;
    return ObjectDirection.center;
  }

  // ── Distance estimation ──────────────────────────────────────────────
  // Use Geometry focal heuristic since LiDAR/ARCore is unavailable

  RichDetection _estimateDistance(Detection d) {
    double distM = -1.0;

    // Flat heuristic based on real world known heights
    const typicalHeights = <String, double>{
      'person': 1.70, 'chair': 0.90, 'couch': 0.85, 'sofa': 0.85,
      'dining table': 0.75, 'refrigerator': 1.80, 'bed': 0.60,
      'toilet': 0.45, 'tv': 0.60, 'monitor': 0.40, 'potted plant': 0.50,
      'bicycle': 1.10, 'dog': 0.55, 'cat': 0.30, 'suitcase': 0.70,
      'car': 1.50, 'truck': 2.50, 'door': 2.10, 'stairs': 0.30,
    };
    
    final typicalH = typicalHeights[d.label] ?? 0.80;
    final pixelH = d.bbox.height.clamp(1.0, kModelInputSize.toDouble());
    
    // focal length in pixels = (width / 2) / tan(FOV / 2)
    final focalPx = kModelInputSize / (2 * math.tan(kCamFovH / 2 * math.pi / 180));
    
    distM = (typicalH * focalPx) / pixelH;

    return RichDetection(
      label: d.label,
      confidence: d.confidence,
      bbox: d.bbox,
      distanceM: distM.clamp(0.1, 10.0),
    );
  }

  void reset() {
    _frameCount.clear();
    _prevLabels = {};
  }
}