// lib/ui/home_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// DISHA — Main camera screen with detection overlay
// ─────────────────────────────────────────────────────────────────────────────

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/disha_controller.dart';
import '../core/models.dart';
import 'detection_painter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DishaController>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: ctrl.initialising
          ? _buildSplash(ctrl.statusMessage)
          : _buildMain(context, ctrl),
    );
  }

  // ── Splash / loading ──────────────────────────────────────────────────────

  Widget _buildSplash(String status) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'DISHA दिशा',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(color: Colors.blue),
          const SizedBox(height: 16),
          Text(
            status,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Main layout ───────────────────────────────────────────────────────────

  Widget _buildMain(BuildContext context, DishaController ctrl) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        _CameraView(ctrl: ctrl),

        // Detection overlay
        if (ctrl.cameraController != null)
          _DetectionOverlay(ctrl: ctrl),

        // HUD — top bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _TopHud(ctrl: ctrl),
        ),

        // Bottom panel — confirmed obstacles
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _BottomPanel(ctrl: ctrl),
        ),

        // Pause / resume FAB
        Positioned(
          bottom: ctrl.obstacles.isEmpty ? 24 : 140,
          right: 16,
          child: _PauseFab(ctrl: ctrl),
        ),
      ],
    );
  }
}

// ── Camera Preview Widget ─────────────────────────────────────────────────────

class _CameraView extends StatelessWidget {
  final DishaController ctrl;
  const _CameraView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final camCtrl = ctrl.cameraController;
    if (camCtrl == null || !camCtrl.value.isInitialized) {
      return const SizedBox();
    }
    return CameraPreview(camCtrl);
  }
}

// ── Bounding Box Overlay ──────────────────────────────────────────────────────

class _DetectionOverlay extends StatelessWidget {
  final DishaController ctrl;
  const _DetectionOverlay({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: DetectionPainter(
          detections  : ctrl.rawDetections,
          confirmed   : ctrl.obstacles,
          previewSize : Size(
            ctrl.cameraController!.value.previewSize!.height,
            ctrl.cameraController!.value.previewSize!.width,
          ),
        ),
      ),
    );
  }
}

// ── Top HUD ───────────────────────────────────────────────────────────────────

class _TopHud extends StatelessWidget {
  final DishaController ctrl;
  const _TopHud({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          const Text(
            'DISHA',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          _StatusChip(
            label: ctrl.running ? 'LIVE' : 'PAUSED',
            color: ctrl.running ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          _StatusChip(
            label: '${ctrl.fps} fps',
            color: Colors.white24,
          ),
          const SizedBox(width: 8),
          _StatusChip(
            label: '${ctrl.rawDetections.length} det',
            color: Colors.white24,
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(180),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── Bottom Panel — confirmed obstacles ────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  final DishaController ctrl;
  const _BottomPanel({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final obstacles = ctrl.obstacles;
    if (obstacles.isEmpty) return const SizedBox();

    return Container(
      constraints: const BoxConstraints(maxHeight: 130),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        reverse: true,
        itemCount: obstacles.length,
        itemBuilder: (_, i) => _ObstacleRow(obstacle: obstacles[i]),
      ),
    );
  }
}

class _ObstacleRow extends StatelessWidget {
  final ConfirmedObstacle obstacle;
  const _ObstacleRow({required this.obstacle});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (obstacle.zone) {
      ObstacleZone.critical => ('🔴', Colors.red),
      ObstacleZone.warning  => ('🟡', Colors.orange),
      ObstacleZone.ambient  => ('🔵', Colors.blue),
      ObstacleZone.ignore   => ('⚫', Colors.grey),
    };

    final dirLabel = switch (obstacle.direction) {
      ObjectDirection.left   => '← Left',
      ObjectDirection.center => '↑ Ahead',
      ObjectDirection.right  => '→ Right',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              obstacle.label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            dirLabel,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 8),
          if (obstacle.distanceM > 0)
            Text(
              '${obstacle.distanceM.toStringAsFixed(1)} m',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

// ── Pause FAB ─────────────────────────────────────────────────────────────────

class _PauseFab extends StatelessWidget {
  final DishaController ctrl;
  const _PauseFab({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'pause',
      backgroundColor: Colors.black54,
      onPressed: ctrl.togglePause,
      child: Icon(
        ctrl.running ? Icons.pause : Icons.play_arrow,
        color: Colors.white,
      ),
    );
  }
}