import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' show Intl;
import 'package:revvo_app/l10n/app_localizations.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/navigation/app_router.dart';
import 'core/providers/app_settings_provider.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'core/config/app_config.dart';
import 'core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force Western (English) numerals for all intl formatting (NumberFormat, DateFormat)
  // even when the UI locale is Arabic. The Flutter UI locale is set separately in MaterialApp.
  Intl.defaultLocale = 'en';

  // Set environment before anything else
  AppConfig.setEnvironment(
    kReleaseMode ? Environment.production : Environment.development,
  );
  
  // Initialize Firebase with the generated options
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Enable Firestore offline persistence
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Pass all uncaught "fatal" errors from the framework to Crashlytics
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    // Register FCM background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    if (kDebugMode) debugPrint('Firebase & Crashlytics initialization failed: $e');
  }

  // Lock orientation to portrait for now
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ProviderScope(child: RevvoApp()));
}

class RevvoApp extends ConsumerWidget {
  const RevvoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'Revvo',
      debugShowCheckedModeBanner: false,

      // ─── Theme ───
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,

      // ─── Router ───
      routerConfig: router,

      // ─── Localization ───
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
      ],
    );
  }
}
