import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'screens/recording_screen.dart';
import 'services/native_camera_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final settingsService = SettingsService();
  await settingsService.init();

  final cameraService = NativeCameraService();
  await cameraService.init();

  runApp(
    BcgCamApp(
      settingsService: settingsService,
      cameraService: cameraService,
    ),
  );
}

class BcgCamApp extends StatelessWidget {
  final SettingsService settingsService;
  final NativeCameraService cameraService;

  const BcgCamApp({
    super.key,
    required this.settingsService,
    required this.cameraService,
  });

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D47A1);

    final lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
      ),
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
      ),
    );

    return MaterialApp(
      title: 'BcgCam',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: _AppHome(
        settingsService: settingsService,
        cameraService: cameraService,
      ),
    );
  }
}

class _AppHome extends StatefulWidget {
  final SettingsService settingsService;
  final NativeCameraService cameraService;

  const _AppHome({
    required this.settingsService,
    required this.cameraService,
  });

  @override
  State<_AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<_AppHome> {
  @override
  void initState() {
    super.initState();
    // If the service was already recording when the app launched, open recording screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.cameraService.isRecording) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecordingScreen(
              cameraService: widget.cameraService,
              onFinished: () => Navigator.pop(context),
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      settingsService: widget.settingsService,
      cameraService: widget.cameraService,
    );
  }
}
