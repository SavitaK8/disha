// lib/core/constants.dart
// ─────────────────────────────────────────────────────────────────────────────
// DISHA — Global constants. Change values here, everything else follows.
// ─────────────────────────────────────────────────────────────────────────────

/// YOLO model input size (must match the .tflite you exported)
const int kModelInputSize = 320;

/// Confidence threshold — lower = more detections, more false positives
const double kConfidenceThreshold = 0.45;

/// IoU threshold for NMS
const double kIouThreshold = 0.45;

/// Camera horizontal field of view in degrees (phone rear camera, approx)
const double kCamFovH = 66.0;

/// Assumed camera height in metres (phone held at ~chest / pocket level)
const double kCamHeightM = 1.20;

/// Target inference FPS — 10 is enough for walking speed
const int kTargetFps = 10;

/// ── Distance zones (metres) ─────────────────────────────────────────────────
const double kZoneCriticalMax = 0.8;
const double kZoneWarningMax  = 2.0;
const double kZoneAmbientMax  = 3.5;
// Beyond kZoneAmbientMax → silently dropped

/// ── Size filter ─────────────────────────────────────────────────────────────
/// Objects whose real-world width OR height is below this are ignored
const double kMinRealSizeM = 0.20; // 20 cm

/// ── Flat surface filter ─────────────────────────────────────────────────────
/// Depth variance below this = flat / open door → not a real obstacle
/// (ARCore Phase 3; stub returns false until then)
const double kFlatVarianceThreshold = 0.04;

/// ── Path filter ─────────────────────────────────────────────────────────────
/// Only the centre N% of frame width is considered "in path"
const double kPathCenterFraction = 0.40; // middle 40%

/// ── Temporal persistence ────────────────────────────────────────────────────
/// Detection must appear in this many consecutive frames before alerting user
const int kMinConfirmedFrames = 4;

/// ── Ground plane filter ─────────────────────────────────────────────────────
/// Bottom N% of frame is auto-classified as floor when camera is at eye level
const double kGroundPlaneBottomFraction = 0.25;

/// ── Audio cooldown ──────────────────────────────────────────────────────────
/// Minimum milliseconds between two TTS/beep alerts for the same object class
const int kAudioCooldownMs = 3000;

/// ── Class buckets ────────────────────────────────────────────────────────────
const Set<String> kClassCritical = {
  'person', 'bicycle', 'dog', 'cat', 'suitcase',
};

const Set<String> kClassConditional = {
  'chair', 'couch', 'sofa', 'dining table', 'potted plant',
  'refrigerator', 'bed', 'toilet', 'tv', 'monitor',
};

const Set<String> kClassContext = {
  'door', 'stairs', 'elevator',
};

/// Everything not in the above sets that COCO knows about → ignored immediately
/// (ties, remotes, phones, books, bottles, cups, forks, spoons …)