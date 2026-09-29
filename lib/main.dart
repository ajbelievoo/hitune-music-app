import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:app_links/app_links.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:ui';
import 'dart:convert';

import 'features/shell/app_shell.dart';
import 'features/auth/auth_service.dart';
import 'features/auth/auth_state_service.dart';
import 'features/config/client_config_service.dart';
import 'features/charts/charts_screen.dart';
import 'features/clips/clips_screen.dart';
import 'features/contests/contests_screen.dart';
import 'features/library/upload_redirect_screen.dart';
import 'features/parties/parties_screen.dart';
import 'features/radio/radio_screen.dart';
import 'features/tipping/tip_history_screen.dart';
import 'features/subscription/subscription_service.dart';
import 'core/l10n/locale_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/theme/theme_service.dart';
import 'core/ads/ad_service.dart';
import 'core/utils/app_logger.dart';
import 'splash_screen.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // One-time purge of the image disk cache: older builds stored covers
    // downscaled to ~100px (maxWidthDiskCache) and those files keep serving
    // blurry until evicted. Runs once, guarded by a flag.
    unawaited(Future(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('img_cache_v2') != true) {
          await DefaultCacheManager().emptyCache();
          await prefs.setBool('img_cache_v2', true);
        }
      } catch (e) {
        AppLogger.d('[APP] image cache purge failed: $e');
      }
    }));

    // Initialize AdMob in the background — don't block the first frame on it.
    unawaited(Future(() async {
      try {
        await AdService.instance.initialize(testMode: false); // Production mode
        AppLogger.d('[APP] AdMob initialized successfully (Production)');
      } catch (e) {
        AppLogger.d('[APP] AdMob initialization failed: $e');
      }
    }));

    final appLinks = AppLinks();

    Future<void> handleAuthLink(Uri uri) async {
      AppLogger.d('Deep link received: $uri');

      // Handle Social Login
      if (uri.scheme == 'hitune' && uri.host.toLowerCase() == 'sociallogin') {
        // Backend failure path: hitune://sociallogin?success=false&error=...
        final success = (uri.queryParameters['success'] ?? '').toLowerCase();
        final errorParam = uri.queryParameters['error'];
        if (success == 'false' || success == '0' || (errorParam != null && errorParam.isNotEmpty)) {
          AuthStateService().notifyLoginFailed(
            (errorParam != null && errorParam.isNotEmpty) ? errorParam : 'Social login failed',
          );
          return;
        }

        // Backend sends token as JSON string in query parameter
        final tokenJson = uri.queryParameters['token'];
        if (tokenJson != null && tokenJson.isNotEmpty) {
          try {
            final tokenData = jsonDecode(tokenJson) as Map<String, dynamic>;
            final sessId = tokenData['sess_id']?.toString();
            final sessKey = tokenData['sess_key']?.toString();

            if (sessId != null && sessKey != null && sessId.isNotEmpty && sessKey.isNotEmpty) {
              AppLogger.d('[DEEP LINK] Setting session from deep link');
              await AuthService().setSession(sessId: sessId, sessKey: sessKey);
              await ClientConfigService().fetchClientConfig();
              AuthStateService().notifyLoggedIn();
              AppLogger.d('[DEEP LINK] Session set successfully');
            } else {
              AppLogger.d('[DEEP LINK] ERROR: sess_id or sess_key missing in token');
              AuthStateService().notifyLoginFailed('Login data incomplete');
            }
          } catch (e) {
            AppLogger.d('[DEEP LINK] ERROR parsing token JSON: $e');
            AuthStateService().notifyLoginFailed('Could not read login data');
          }
        } else {
          // Fallback: try direct query parameters (old format)
          final sessId = uri.queryParameters['sess_id'];
          final sessKey = uri.queryParameters['sess_key'];
          if (sessId != null && sessKey != null) {
            await AuthService().setSession(sessId: sessId, sessKey: sessKey);
            await ClientConfigService().fetchClientConfig();
            AuthStateService().notifyLoggedIn();
          } else {
            AuthStateService().notifyLoginFailed('Login data missing');
          }
        }
        return;
      }

      // Handle Share Links (HTTPS)
      if (uri.scheme == 'https') {
        _handleShareLink(uri);
      }
    }

    // In app_links 6.x the stream already includes the initial (cold-start) link.
    try {
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) await handleAuthLink(initialUri);
    } catch (e) {
      AppLogger.d('[DEEP LINK] Error reading initial link: $e');
    }

    appLinks.uriLinkStream.listen(handleAuthLink);

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.dumpErrorToConsole(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      Zone.current.handleUncaughtError(error, stack);
      return true;
    };

    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'in.hitune.music.channel.audio',
        androidNotificationChannelName: 'Playback',
        androidNotificationOngoing: true,
      );
    } catch (e, st) {
      // Don't block UI if background audio init fails.
      AppLogger.d('JustAudioBackground.init failed: $e');
      AppLogger.d(st.toString());
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ClientConfigService()),
          ChangeNotifierProvider(create: (_) => ThemeService()),
          ChangeNotifierProvider(create: (_) => AuthStateService()),
          ChangeNotifierProvider.value(value: LocaleService.instance),
          ChangeNotifierProvider.value(value: SubscriptionService.instance),
        ],
        child: const MyApp(),
      ),
    );
  }, (error, stack) {
    AppLogger.d('Uncaught zone error: $error');
    AppLogger.d(stack.toString());
  });
}

/// Handle share link deep links
void _handleShareLink(Uri uri) {
  AppLogger.d('[DEEP LINK] Handling share link: $uri');
  
  final path = uri.path;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  
  if (segments.isEmpty) return;
  
  // Handle /music/{type}/{slug}/ pattern
  if (segments.length >= 2 && segments[0] == 'music') {
    final objectType = segments[1];
    final slug = segments.length > 2 ? segments[2] : '';
    
    if (slug.isEmpty) return;
    
    AppLogger.d('[DEEP LINK] Type: $objectType, Slug: $slug');
    
    // Store the pending navigation for after app loads
    DeepLinkService().setPendingLink(objectType, slug);
  }
  // Handle /{type}/{slug}/ pattern (without /music/ prefix)
  else if (segments.isNotEmpty) {
    final objectType = segments[0];
    final slug = segments.length > 1 ? segments[1] : '';
    
    if (slug.isEmpty) return;
    
    AppLogger.d('[DEEP LINK] Type: $objectType, Slug: $slug');
    
    // Store the pending navigation for after app loads
    DeepLinkService().setPendingLink(objectType, slug);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    
    // Load theme + language preference
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final themeService = Provider.of<ThemeService>(context, listen: false);
      await themeService.loadTheme();
      await LocaleService.instance.load();
    });
    
    // Pre-fetch client config before showing splash
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      AppLogger.d('[APP] Pre-fetching client config...');
      await ClientConfigService().fetchClientConfig();
      SubscriptionService.instance.refresh();
      AppLogger.d('[APP] Client config pre-fetched');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'HiTune Music',
          theme: ThemeService.lightTheme,
          darkTheme: ThemeService.darkTheme,
          themeMode: themeService.themeMode,
          initialRoute: '/splash',
          routes: {
            '/splash': (context) => const SplashScreen(),
            '/main': (context) => const AppShell(),
            '/upload': (context) => const UploadRedirectScreen(),
            '/clips': (context) => const ClipsScreen(),
            '/charts': (context) => const ChartsScreen(),
            '/radio': (context) => const RadioScreen(),
            '/parties': (context) => const PartiesScreen(),
            '/contests': (context) => const ContestsScreen(),
            '/tips': (context) => const TipHistoryScreen(),
          },
        );
      },
    );
  }
}
