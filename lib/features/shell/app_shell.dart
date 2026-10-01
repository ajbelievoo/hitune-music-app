import 'package:flutter/material.dart';

import '../../core/l10n/locale_service.dart';
import '../../core/ui/offline_banner.dart';
import '../../core/utils/app_logger.dart';
import '../auth/auth_gate.dart';
import '../config/client_config_service.dart';
import '../home/home_screen.dart';
import '../browse/browse_screen.dart';
import '../radio/radio_screen.dart';
import '../player/mini_player.dart';
import '../player/player_service.dart';
import '../search/search_screen.dart';
import '../library/library_screen.dart';
import '../collection/collection_screen.dart';
import '../collection/collection_service.dart';
import '../artist/artist_screen.dart';
import '../subscription/subscription_service.dart';
import '../../core/services/deep_link_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _syncClientConfig();
    _checkPendingDeepLink();
    
    // Listen for deep links while app is running
    DeepLinkService().onDeepLink.listen((data) {
      _handleDeepLink(data);
    });
  }

  void _checkPendingDeepLink() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingLink = DeepLinkService().consumePendingLink();
      if (pendingLink != null) {
        _handleDeepLink(pendingLink);
      }
    });
  }

  void _handleDeepLink(DeepLinkData data) {
    AppLogger.d('[AppShell] Handling deep link: ${data.type}/${data.slug}');
    
    switch (data.type) {
      case 'track':
        _navigateToTrack(data.slug);
        break;
      case 'artist':
        _navigateToArtist(data.slug);
        break;
      case 'album':
        _navigateToAlbum(data.slug);
        break;
      case 'playlist':
        _navigateToPlaylist(data.slug);
        break;
      default:
        AppLogger.d('[AppShell] Unknown deep link type: ${data.type}');
    }
  }

  void _navigateToTrack(String slug) async {
    // Fetch track data first, then navigate
    final item = await _fetchObjectData('m_track', slug);
    if (item != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CollectionScreen(item: item),
        ),
      );
    }
  }

  void _navigateToArtist(String slug) {
    // Navigate to artist screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ArtistScreen(artistSlug: slug),
      ),
    );
  }

  void _navigateToAlbum(String slug) async {
    // Fetch album data first, then navigate
    final item = await _fetchObjectData('m_album', slug);
    if (item != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CollectionScreen(item: item),
        ),
      );
    }
  }

  void _navigateToPlaylist(String slug) async {
    // Fetch playlist data first, then navigate
    final item = await _fetchObjectData('m_playlist', slug);
    if (item != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CollectionScreen(item: item),
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> _fetchObjectData(String objectType, String slug) async {
    try {
      AppLogger.d('[AppShell] Fetching $objectType data for: $slug');
      final res = await CollectionService().fetchCollectionDetail(hash: slug);
      if (res.isSuccess && res.data != null) {
        // Extract item from response
        final payload = res.data!;
        if (payload['item'] is Map) {
          return Map<String, dynamic>.from(payload['item']);
        }
        // If no direct item, construct from payload
        return {
          'hash': slug,
          'object_type': objectType,
          'object_hash': slug,
          ...payload,
        };
      }
      AppLogger.d('[AppShell] Failed to fetch object data: ${res.error?.message}');
    } catch (e) {
      AppLogger.d('[AppShell] Error fetching object data: $e');
    }
    return null;
  }

  Future<void> _syncClientConfig() async {
    AppLogger.d('[APP SHELL] Starting _syncClientConfig...');
    await ClientConfigService().fetchClientConfig();
    SubscriptionService.instance.refresh();
    AppLogger.d('[APP SHELL] fetchClientConfig done, now fetching social logins...');
    // Also fetch social login providers from admin panel
    await ClientConfigService().fetchSocialLogins();
    AppLogger.d('[APP SHELL] fetchSocialLogins done');
  }

  final _pages = const [
    HomeScreen(),
    BrowseScreen(),
    RadioScreen(),
    LibraryScreen(),
    SearchScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final player = PlayerService.instance;
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: _pages,
        ),
      ),
      // Bottom bars live in the scaffold slot (not an overlay Stack) so page
      // content is never painted underneath them — lists can scroll fully.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const OfflineBanner(),
          MiniPlayer(player: player),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.95),
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              backgroundColor: Colors.transparent,
              elevation: 0,
              onDestinationSelected: (i) async {
                if (i == 3) {
                  final ok = await AuthGate.ensureLoggedIn(
                    context,
                    reason: 'Login required to open Your Library.',
                  );
                  if (!ok) return;
                }
                if (!mounted) return;
                setState(() => _index = i);
              },
              destinations: [
                NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: L10n.t('nav_listen_now')),
                NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view_rounded), label: L10n.t('nav_browse')),
                NavigationDestination(icon: const Icon(Icons.radio_outlined), selectedIcon: const Icon(Icons.radio_rounded), label: L10n.t('nav_radio')),
                NavigationDestination(icon: const Icon(Icons.library_music_outlined), selectedIcon: const Icon(Icons.library_music_rounded), label: L10n.t('nav_library')),
                NavigationDestination(icon: const Icon(Icons.search_outlined), selectedIcon: const Icon(Icons.search_rounded), label: L10n.t('nav_search')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


