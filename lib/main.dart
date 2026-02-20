import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait for now
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ProviderScope(child: MasariApp()));
}

class MasariApp extends StatelessWidget {
  const MasariApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Masari',
      debugShowCheckedModeBanner: false,

      // ─── Theme ───
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light, // Start with light mode
      // ─── Entry point ───
      home: const SplashScreen(),
    );
  }
}
