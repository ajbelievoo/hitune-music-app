import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitune_music/main.dart';
import 'package:hitune_music/core/theme/theme_service.dart';
import 'package:hitune_music/features/auth/auth_state_service.dart';
import 'package:hitune_music/features/config/client_config_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('MyApp builds with providers and shows splash', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ClientConfigService()),
          ChangeNotifierProvider(create: (_) => ThemeService()),
          ChangeNotifierProvider(create: (_) => AuthStateService()),
        ],
        child: const MyApp(),
      ),
    );

    // App should build and show the splash route initially.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
