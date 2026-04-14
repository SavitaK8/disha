// lib/services/audio_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// DISHA — Audio Output Layer
//
//  Critical zone  → triple beep earcon  (no speech — faster)
//  Warning zone   → short TTS            "chair, left, 1.4m"
//  Ambient zone   → single soft blip    (no speech)
//  Context class  → TTS announcement    "door ahead, open"
//
//  Cooldown: same label not announced more than once per kAudioCooldownMs
// ─────────────────────────────────────────────────────────────────────────────

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/constants.dart';
import '../core/models.dart';

class AudioService {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _beepPlayer = AudioPlayer();
  final AudioPlayer _blipPlayer = AudioPlayer();

  // cooldown tracking: label → last announced timestamp
  final Map<String, DateTime> _lastAnnounced = {};

  bool _ready = false;

  Future<void> init() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.55); // slightly faster than default
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _ready = true;
  }

  // ── Main entry point ──────────────────────────────────────────────────────

  Future<void> announce(ConfirmedObstacle obstacle) async {
    if (!_ready) return;

    // Cooldown check
    final now = DateTime.now();
    final key  = obstacle.label;
    final last = _lastAnnounced[key];
    if (last != null &&
        now.difference(last).inMilliseconds < kAudioCooldownMs) {
      return; // still in cooldown — skip
    }
    _lastAnnounced[key] = now;

    switch (obstacle.zone) {
      case ObstacleZone.critical:
        await _playBeep();
        break;
      case ObstacleZone.warning:
        final msg = obstacle.ttsMessage;
        if (msg.isNotEmpty) await _speak(msg);
        break;
      case ObstacleZone.ambient:
        await _playBlip();
        break;
      case ObstacleZone.ignore:
        break; // should never reach here
    }
  }

  /// Announce navigation context objects (doors, stairs, etc.)
  Future<void> announceContext(String label) async {
    if (!_ready) return;
    final key = 'ctx_$label';
    final now = DateTime.now();
    final last = _lastAnnounced[key];
    if (last != null && now.difference(last).inMilliseconds < 8000) return;
    _lastAnnounced[key] = now;
    await _speak('$label ahead');
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _playBeep() async {
    // Triple short beep — critical zone earcon
    for (int i = 0; i < 3; i++) {
      await _beepPlayer.play(
        AssetSource('audio/beep_critical.mp3'),
        volume: 1.0,
      );
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  Future<void> _playBlip() async {
    await _blipPlayer.play(
      AssetSource('audio/blip_ambient.mp3'),
      volume: 0.55,
    );
  }

  Future<void> stop() async {
    await _tts.stop();
    await _beepPlayer.stop();
    await _blipPlayer.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _beepPlayer.dispose();
    await _blipPlayer.dispose();
  }
}