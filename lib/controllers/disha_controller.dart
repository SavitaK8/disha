// lib/controllers/disha_controller.dart
// ─────────────────────────────────────────────────────────────────────────────
// DISHA — Main pipeline orchestrator
// Camera → YOLO → Reasoning Engine → Audio
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants.dart';
import '../core/models.dart';
import 'package:camera/camera.dart';
import '../services/camera_service.dart';
import '../services/audio_service.dart';
import '../services/reasoning_engine.dart';
import '../services/yolo_service.dart';

class DishaController extends ChangeNotifier {
  final CameraService  _cameraService  = CameraService();
  final YoloService    _yoloService    = YoloService();
  final AudioService   _audioService   = AudioService();
  final ReasoningEngine _engine        = ReasoningEngine();
  StreamSubscription<CameraImage>? _frameSub;
  bool _isProcessing = false;

  // ── State exposed to UI ────────────────────────────────────────────────────
  bool _running = false;
  bool _initialising = true;
  String _statusMessage = 'Initialising…';
  List<Detection> _rawDetections = [];
  List<ConfirmedObstacle> _obstacles = [];
  int _fps = 0;

  bool   get running         => _running;
  bool   get initialising    => _initialising;
  String get statusMessage   => _statusMessage;
  List<Detection> get rawDetections => _rawDetections;
  List<ConfirmedObstacle> get obstacles => _obstacles;
  int    get fps             => _fps;
  CameraController? get cameraController => _cameraService.controller;

  // ── FPS counter ────────────────────────────────────────────────────────────
  int _frameCount = 0;
  Timer? _fpsTimer;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _setStatus('Requesting permissions…');
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      _setStatus('Camera permission required');
      return;
    }

    _setStatus('Loading model…');
    await _yoloService.init();

    _setStatus('Starting Camera…');
    await _cameraService.init();

    _setStatus('Loading audio…');
    await _audioService.init();

    _initialising = false;
    _running = true;
    _setStatus('Running');

    _startFpsCounter();
    _frameSub = _cameraService.frames.listen(_onFrame);

    notifyListeners();
  }

  // ── Frame pipeline ────────────────────────────────────────────────────────

  Future<void> _onFrame(CameraImage frame) async {
    if (!_running) return;
    if (_isProcessing) return;

    _isProcessing = true;

    try {
      // YOLO inference
      // Run asynchronously via Isolate to prevent UI lockup!
      List<Detection> detections = await _yoloService.runOnCameraImage(frame);

      // 5-stage reasoning
      final confirmed = _engine.process(detections);

      // Update UI state
      _rawDetections = detections;
      _obstacles     = confirmed;
      _frameCount++;
      notifyListeners();

      // Audio output — announce highest priority obstacle
      if (confirmed.isNotEmpty) {
        // Sort: critical first, then by distance
        final sorted = [...confirmed]..sort((a, b) {
            final zoneOrder = {
              ObstacleZone.critical : 0,
              ObstacleZone.warning  : 1,
              ObstacleZone.ambient  : 2,
              ObstacleZone.ignore   : 3,
            };
            final cmp = zoneOrder[a.zone]!.compareTo(zoneOrder[b.zone]!);
            if (cmp != 0) return cmp;
            return a.distanceM.compareTo(b.distanceM);
          });

        await _audioService.announce(sorted.first);

        // Announce any context objects (doors, stairs)
        for (final o in sorted) {
          if (kClassContext.contains(o.label)) {
            await _audioService.announceContext(o.label);
          }
        }
      }
    } finally {
      // allow next frame through
      _isProcessing = false;
    }
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  void togglePause() {
    _running = !_running;
    if (!_running) {
      _engine.reset();
      _setStatus('Paused');
    } else {
      _setStatus('Running');
    }
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setStatus(String msg) {
    _statusMessage = msg;
    notifyListeners();
  }

  void _startFpsCounter() {
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _fps = _frameCount;
      _frameCount = 0;
      notifyListeners();
    });
  }

  @override
  Future<void> dispose() async {
    _running = false;
    await _frameSub?.cancel();
    _fpsTimer?.cancel();
    await _cameraService.dispose();
    await _audioService.dispose();
    _yoloService.dispose();
    super.dispose();
  }
}