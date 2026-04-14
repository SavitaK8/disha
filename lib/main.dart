// lib/main.dart
// ─────────────────────────────────────────────────────────────────────────────
// DISHA — App entry point
// ─────────────────────────────────────────────────────────────────────────────

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'controllers/disha_controller.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait — camera works best this way for DISHA
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Keep screen on while navigating
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  final cameras = await availableCameras();

  runApp(DishaApp(cameras: cameras));
}

class DishaApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const DishaApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DishaController()..init(cameras),
      child: MaterialApp(
        title: 'DISHA दिशा',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}