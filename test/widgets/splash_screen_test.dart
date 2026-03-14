import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:masari_app/features/splash/splash_screen.dart';

void main() {
  testWidgets('SplashScreen renders logo and title', (WidgetTester tester) async {
    // Create a simple router for the test
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/auth/signin',
          builder: (context, state) => const Scaffold(body: Text('Sign In')),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const Scaffold(body: Text('Dashboard')),
        ),
      ],
    );

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    // Verify that the logo icon is present
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);

    // Verify the text is rendered
    expect(find.byType(RichText), findsWidgets);
    expect(find.textContaining('Masari'), findsWidgets);

    // Advance time to allow the simulated 3-second initialization timer to complete
    await tester.pump(const Duration(seconds: 4));
  });
}
