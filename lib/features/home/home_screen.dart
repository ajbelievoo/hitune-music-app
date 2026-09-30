import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui/hi_tune_card.dart';
import '../../core/ui/section_header.dart';
import '../charts/charts_screen.dart';
import '../clips/clips_screen.dart';
import '../contests/contests_screen.dart';
import '../parties/parties_screen.dart';
import '../radio/radio_screen.dart';
import '../tipping/tip_history_screen.dart';
import '../collection/collection_screen.dart';
import '../collection/collection_service.dart';
import '../config/client_config_service.dart';
import '../../core/theme/theme_service.dart';
import '../../core/ads/ad_service.dart';
import '../ai_studio/ai_studio_screen.dart';
import '../info/info_screen.dart';
import '../info/iyol_app_screen.dart';
import '../player/models/track.dart';
import '../player/player_service.dart';
import '../auth/auth_gate.dart';
import '../auth/auth_state_service.dart';
import '../auth/login_screen.dart';
import '../library/liked_songs_screen.dart';
import '../library/playlists_screen.dart';
import '../library/recently_played_screen.dart';
import '../../core/storage/secure_storage.dart';
import 'home_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../browse/browse_tracks_screen.dart';
import '../browse/browse_albums_screen.dart';
import '../browse/browse_artists_screen.dart';
import '../browse/browse_radios_screen.dart';
import '../browse/genre_rock_screen.dart';
import '../browse/genre_hiphop_screen.dart';
import '../downloads/downloads_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import 'iyol_stories_rail.dart';
import 'made_for_you_section.dart';
import 'home_rails.dart';
import 'recommendations_service.dart';
import '../browse/browse_feed_service.dart';

// Helper function for background JSON parsing (must be top-level)
Map<String, dynamic> _parseHomePayload(Map<String, dynamic> raw) {
  final msg = raw['messages'];
  if (msg is List && msg.isNotEmpty && msg.first is Map) {
    final data = Map<String, dynamic>.from(msg.first as Map);
    // Pre-extract widgets to avoid main thread work
    final widgets = data['widgets'];
    final widgetList = <Object?>[];
    if (widgets is List) {
      widgetList.addAll(widgets);
    } else if (widgets is Map) {
      widgetList.addAll(widgets.values);
    }
    // Store pre-extracted list for later use
    data['_widgetList'] = widgetList;
    return data;
  }
  final widgets = raw['widgets'];
  final widgetList = <Object?>[];
  if (widgets is List) {
    widgetList.addAll(widgets);
  } else if (widgets is Map) {
    widgetList.addAll(widgets.values);
  }
  raw['_widgetList'] = widgetList;
  return raw;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _TableWidget extends StatefulWidget {
  final ThemeData theme;
  final Map<String, dynamic>? widgetMap;

  const _TableWidget({required this.theme, required this.widgetMap});

  @override
  State<_TableWidget> createState() => _TableWidgetState();
}

class _TableWidgetState extends State<_TableWidget> {
  late Future<List<Map<String, dynamic>>> _items;

  @override
  void initState() {
    super.initState();
    _items = _loadItems();
  }

  Map<String, dynamic>? get w => widget.widgetMap;

  Map<String, dynamic>? get display => (w?['display'] is Map<String, dynamic>) ? (w!['display'] as Map<String, dynamic>) : null;

  String _label() {
    final t = (display?['title'] ?? '').toString();
    return t.isEmpty ? 'Tracks' : t;
  }

  String? _widgetHash() {
    // Try link first (list/xxx format)
    final link = (display?['link'] ?? '').toString();
    if (link.startsWith('list/')) {
      final parts = link.split('/');
      if (parts.length >= 2 && parts[1].isNotEmpty) return parts[1];
    }
    // Try ID field
    final id = (w?['ID'] ?? '').toString();
    if (id.isNotEmpty) return id;
    // Fallback: try name or slug
    final name = (w?['name'] ?? w?['slug'] ?? '').toString();
    if (name.isNotEmpty) return name;
    return null;
  }

  bool _isTrackTable() {
    final ot = (display?['o_type'] ?? '').toString();
    return ot == 'm_track';
  }

  Future<List<Map<String, dynamic>>> _loadItems() async {
    final raw = w?['items'];
    if (raw is List) {
      final list = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (list.isNotEmpty) return list;
      final hash = _widgetHash();
      if (hash == null) return const [];
      return _fetchFromList(hash);
    }

    if (raw is Map) {
      final inner = raw['items'];
      if (inner is List) {
        final list = inner.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        if (list.isNotEmpty) return list;
        final hash = _widgetHash();
        if (hash == null) return const [];
        return _fetchFromList(hash);
      }

      if (raw.isEmpty) {
        final hash = _widgetHash();
        if (hash == null) return const [];
        return _fetchFromList(hash);
      }
    }

    if (raw == null) {
      final hash = _widgetHash();
      if (hash == null) return const [];
      return _fetchFromList(hash);
    }

    if (raw is String) {
      final s = raw.trim().toLowerCase();
      if (s == 'false' || s == '0' || s.isEmpty) {
        final hash = _widgetHash();
        if (hash == null) return const [];
        return _fetchFromList(hash);
      }
      return const [];
    }

    if (raw != false) {
      final hash = _widgetHash();
      if (hash == null) return const [];
      return _fetchFromList(hash);
    }

    final hash = _widgetHash();
    if (hash == null) return const [];
    return _fetchFromList(hash);
  }

  Future<List<Map<String, dynamic>>> _fetchFromList(String hash) async {
    final res = await CollectionService().fetchListWidget(widgetHash: hash);
    if (!res.isSuccess) {
      throw Exception('List API failed: ${res.error?.message}');
    }

    final payload = res.data!;
    final widgets = payload['widgets'];
    if (widgets is List && widgets.isNotEmpty && widgets.first is Map) {
      final w0 = Map<String, dynamic>.from(widgets.first as Map);
      final items = w0['items'];
      if (items is List && items.isNotEmpty) {
        return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    
    // Format 2: Direct items in payload
    final directItems = payload['items'];
    if (directItems is List && directItems.isNotEmpty) {
      return directItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    
    // Format 3: payload['data']['items']
    final data = payload['data'];
    if (data is Map) {
      final dataItems = data['items'];
      if (dataItems is List && dataItems.isNotEmpty) {
        return dataItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    
    // Format 4: payload['results']
    final results = payload['results'];
    if (results is List && results.isNotEmpty) {
      return results.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  String? _extractTitle(Map<String, dynamic> t) {
    final title = t['title'];
    if (title != null && title.toString().isNotEmpty) {
      final cleaned = title.toString().replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleaned.isNotEmpty) return cleaned;
    }

    final tds = t['tds'];
    if (tds is List) {
      for (final cell in tds) {
        if (cell is! Map) continue;
        final cls = (cell['class'] ?? '').toString();
        if (!cls.split(' ').contains('title')) continue;
        final val = (cell['val'] ?? '').toString();
        final cleaned = val.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (cleaned.isNotEmpty) return cleaned;
      }
    }

    return null;
  }

  String? _extractCoverUrl(Map<String, dynamic> t) {
    return CoverImageExtractor.extract(t);
  }

  Track? _toTrack(Map<String, dynamic> t) {
    final rawNode = t['raw'];
    final rawMap = rawNode is Map ? Map<String, dynamic>.from(rawNode) : null;
    final hash = (t['hash'] ?? rawMap?['hash'] ?? '').toString();
    if (hash.isEmpty) return null;
    final ot = (t['ot'] ?? t['object_type'] ?? rawMap?['ot'] ?? 'm_track').toString();
    final title = _extractTitle(t) ?? 'Track';
    final coverUrl = _extractCoverUrl(t);
    final url = (t['url'] ?? '').toString();
    final subtitle = (t['sub_title'] ?? t['sub_data'] ?? rawMap?['sub_data'] ?? rawMap?['sub_title'] ?? '').toString();
    final artistLink = (t['sub_link'] ?? rawMap?['sub_link'] ?? '').toString();
    var artistSlug = (t['artist_slug'] ?? rawMap?['artist_slug'] ?? '').toString();
    if (artistSlug.isEmpty && artistLink.contains('artist/')) {
      final parts = artistLink.split('?').first.split('/').where((e) => e.isNotEmpty).toList();
      if (parts.isNotEmpty) artistSlug = parts.last;
    }
    return Track(
      id: hash,
      title: title,
      subtitle: subtitle.isNotEmpty ? subtitle : null,
      url: url,
      coverUrl: coverUrl,
      artistSlug: artistSlug.isEmpty ? null : artistSlug,
      artistLink: artistLink.isEmpty ? null : artistLink,
      objectType: ot.isEmpty ? 'm_track' : ot,
      objectHash: hash,
      aiPct: Track.aiPctFromJson(t),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isDark = theme.brightness == Brightness.dark;
    final label = _label();
    final canOpen = _widgetHash() != null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
        border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w800),
                ),
              ),
              if (canOpen)
                TextButton(
                  onPressed: () {
                    if (w == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CollectionScreen(item: w!),
                      ),
                    );
                  },
                  child: Text(
                    'See all',
                    style: TextStyle(color: theme.colorScheme.primary.withValues(alpha: 0.9)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _items,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)),
                );
              }

              if (snapshot.hasError) {
                return Text(
                  'Failed: ${snapshot.error}',
                  style: theme.textTheme.bodySmall?.copyWith(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.75)),
                );
              }

              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return Text(
                  'No items',
                  style: theme.textTheme.bodySmall?.copyWith(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7)),
                );
              }

              final show = items.length > 6 ? items.sublist(0, 6) : items;
              return Column(
                children: [
                  for (final t in show) _HomeTableRow(
                    theme: theme,
                    title: _extractTitle(t) ?? 'Item',
                    coverUrl: _extractCoverUrl(t),
                    onTap: () async {
                      AppLogger.d('[HOME] Track tapped, checking if track table...');
                      AppLogger.d('[HOME] _isTrackTable() = ${_isTrackTable()}');
                      
                      if (_isTrackTable()) {
                        final ok = await AuthGate.ensureLoggedIn(
                          context,
                          reason: 'Login required to play tracks.',
                        );
                        if (!ok) {
                          AppLogger.d('[HOME] User not logged in, aborting');
                          return;
                        }
                        
                        // Get all tracks from the table to create a proper queue
                        final itemsFuture = _items;
                        final allItems = await itemsFuture;
                        AppLogger.d('[HOME] Got ${allItems.length} items from _items');
                        
                        final tracks = <Track>[];
                        int startIndex = 0;
                        
                        for (int i = 0; i < allItems.length; i++) {
                          final item = allItems[i];
                          final track = _toTrack(item);
                          AppLogger.d('[HOME] Item $i: track=${track?.title ?? "null"}');
                          if (track != null) {
                            tracks.add(track);
                            // Find the index of the tapped track
                            if (item == t) {
                              startIndex = tracks.length - 1;
                              AppLogger.d('[HOME] Found tapped track at index $startIndex');
                            }
                          }
                        }
                        
                        if (tracks.isEmpty) {
                          AppLogger.d('[HOME] ERROR: No tracks found!');
                          return;
                        }
                        
                        AppLogger.d('[HOME] Playing queue with ${tracks.length} tracks, starting at index $startIndex');
                        await PlayerService.instance.playQueue(tracks, startIndex: startIndex);
                        return;
                      }
                      AppLogger.d('[HOME] Not a track table, navigating to CollectionScreen');
                      if (w == null) return;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CollectionScreen(item: w!),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeTableRow extends StatelessWidget {
  final ThemeData theme;
  final String title;
  final String? coverUrl;
  final VoidCallback onTap;

  const _HomeTableRow({required this.theme, required this.title, required this.coverUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    bool isValidImageUrl(String url) {
      final u = url.trim();
      if (u.isEmpty) return false;
      if (u.contains(' ')) return false;
      if (u.startsWith('data:')) return false;
      return true;
    }

    final safeCover = (coverUrl != null && coverUrl!.trim().isNotEmpty && isValidImageUrl(coverUrl!)) ? coverUrl : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
            border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: (safeCover == null || safeCover.isEmpty)
                      ? Container(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                          child: Icon(Icons.music_note, color: isDark ? Colors.white70 : Colors.black54, size: 24),
                        )
                      : Builder(builder: (context) {
                          if (_HomeScreenState.failedImageUrls.contains(safeCover)) {
                            return Container(
                              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                              child: Icon(Icons.music_note, color: isDark ? Colors.white70 : Colors.black54, size: 24),
                            );
                          }
                          return CachedNetworkImage(
                            imageUrl: safeCover,
                            fit: BoxFit.cover,
                            maxHeightDiskCache: 640,
                            maxWidthDiskCache: 640,
                            memCacheHeight: 100,
                            memCacheWidth: 100,
                            placeholder: (_, __) => Container(
                              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                            ),
                            errorWidget: (_, __, ___) {
                              if (safeCover.isNotEmpty) {
                                _HomeScreenState.failedImageUrls.add(safeCover);
                              }
                              return Container(
                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                                child: Icon(Icons.music_note, color: isDark ? Colors.white70 : Colors.black54, size: 24),
                              );
                            },
                          );
                        }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Map<String, dynamic>> _home;

  @override
  void initState() {
    super.initState();
    _home = _fetch();
  }

  // Global blacklist for failed images to prevent repeated loading attempts
  static final Set<String> failedImageUrls = <String>{};

  @override
  void dispose() {
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetch() async {
    final res = await HomeService().fetchHomePage();
    if (!res.isSuccess) {
      throw Exception(res.error?.message ?? 'Home fetch failed');
    }

    final raw = res.data!;
    if (kDebugMode) {
      AppLogger.d('[HOME] Home API raw response type: ${raw.runtimeType}');
      AppLogger.d('[HOME] Home API response keys: ${raw.keys}');
    }
    
    // Move heavy JSON parsing to background isolate
    return await compute(_parseHomePayload, raw);
  }

  Widget _buildLogoWidget() {
    return Consumer<ClientConfigService>(
      builder: (context, service, child) {
        final config = service.config;
        
        // If config is loaded, try to show logo from admin panel
        if (config != null) {
          final brand = config['brand'] as Map<String, dynamic>?;
          final rawLogoUrl = brand?['logo'] as String?;
          final logoUrl = _normalizeLogoUrl(rawLogoUrl);
          final brandName = brand?['name'] as String? ?? 'HiTune';
          
          if (kDebugMode) {
            AppLogger.d('[HOME] Logo URL: $logoUrl');
          }
          
          if (logoUrl != null && logoUrl.isNotEmpty && logoUrl.startsWith('http')) {
            return Image.network(
              logoUrl,
              height: 40,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }
                // Show fallback while loading
                return _buildFallbackLogo(context, brandName);
              },
              errorBuilder: (context, error, stackTrace) {
                return _buildFallbackLogo(context, brandName);
              },
            );
          }
          
          return _buildFallbackLogo(context, brandName);
        }

        // Config not loaded yet - show default fallback immediately
        return _buildFallbackLogo(context, 'HiTune');
      },
    );
  }

  String? _normalizeLogoUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    
    // Remove escaping and normalize
    var normalized = url.trim().replaceAll('\\/', '/');
    
    // Add https if starts with //
    if (normalized.startsWith('//')) {
      normalized = 'https:$normalized';
    }
    
    // Add base URL if relative path
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      if (normalized.startsWith('/')) {
        normalized = 'https://music.hitune.in$normalized';
      } else {
        normalized = 'https://music.hitune.in/$normalized';
      }
    }
    
    return normalized;
  }

  Widget _buildFallbackLogo(BuildContext context, String brandName) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Image.asset(
        'assets/logo.png',
        height: 28,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            brandName,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.white,
              fontSize: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSideMenuDrawer(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final theme = Theme.of(context);

        return Drawer(
          backgroundColor: theme.scaffoldBackgroundColor,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with logo
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildLogoWidget(),
                ),
                Divider(color: theme.dividerColor),
                // Menu items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      // Browse categories (not in bottom nav)
                      _buildMenuItem(context, Icons.play_circle_outline, 'Short Clips', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ClipsScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.auto_awesome, 'AI Studio', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AiStudioScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.leaderboard_rounded, 'Charts', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ChartsScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.radio_rounded, 'Radio', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RadioScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.surround_sound_rounded, 'Listening Parties', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PartiesScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.emoji_events_rounded, 'Contests', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ContestsScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.volunteer_activism_rounded, 'Tips & Wallet', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const TipHistoryScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.rocket, "Rock'n'Roll", () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const GenreRockScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.headphones, 'Hip Hop', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const GenreHipHopScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.audiotrack, 'Browse Tracks', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BrowseTracksScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.album, 'Browse Albums', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BrowseAlbumsScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.person, 'Browse Artists', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BrowseArtistsScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.radio, 'Browse Radios', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BrowseRadiosScreen()),
                        );
                      }),
                      Divider(color: theme.dividerColor),
                      // Library shortcuts
                      _buildMenuItem(context, Icons.playlist_play, 'Playlists', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.favorite, 'Liked Songs', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.history, 'History', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RecentlyPlayedScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.download_rounded, 'Downloads', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                        );
                      }),
                      _buildMenuItem(context, Icons.notifications_outlined, 'Notifications', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                        );
                      }),
                      Divider(color: theme.dividerColor),
                      _buildMenuItem(
                        context,
                        themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                        themeService.isDarkMode ? 'Light Mode' : 'Dark Mode',
                        () => themeService.toggleTheme(),
                      ),
                      _buildMenuItem(context, Icons.logout, 'Logout', () async {
                        await SecureStore.clearUserSession();
                        await SecureStore.clearUserToken();
                        await SecureStore.clearUserId();
                        await SecureStore.clearUserName();
                        await SecureStore.clearUserAvatar();
                        AuthStateService().notifyLoggedOut();
                        if (context.mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (route) => false,
                          );
                        }
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuItem(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    final theme = Theme.of(context);
    final muted = theme.iconTheme.color?.withValues(alpha: 0.5);
    return ListTile(
      leading: Icon(icon, color: muted, size: 24),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
      dense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        scrolledUnderElevation: 0,
        title: const Text('Listen Now'),
        actions: [
          const NotificationBell(),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
            ),
            icon: const Icon(Icons.person_rounded),
          ),
          Builder(
            builder: (context) => IconButton(
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      endDrawer: _buildSideMenuDrawer(context),
      body: SafeArea(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _home,
              builder: (context, snapshot) {
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _home = _fetch();
                    });
                  },
                  child: CustomScrollView(
                    slivers: [
                      // IyolMe stories rail — recent public stories deep-link
                      // into the IyolMe app. Renders nothing when empty.
                      const SliverToBoxAdapter(child: IyolStoriesRail()),
                      // Personalized rail - renders only when backend provides
                      // recommendations (see RecommendationsService).
                      const SliverToBoxAdapter(child: MadeForYouSection()),
                      if (snapshot.connectionState != ConnectionState.done)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        )
                      else if (snapshot.hasError)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Could not load home content',
                                    style: theme.textTheme.titleMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Pull down to retry',
                                    style: theme.textTheme.bodySmall,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        ..._buildFromPayload(theme, snapshot.data!),
                    ],
                  ),
                );
              },
            ),
          ),
    );
  }

  List<Widget> _buildFromPayload(ThemeData theme, Map<String, dynamic> payload) {
    if (kDebugMode) {
      AppLogger.d('[HOME] Building from payload keys: ${payload.keys}');
    }
    // Use pre-extracted widget list from compute()
    final widgetList = payload['_widgetList'] as List<Object?>? ?? [];
    
    if (kDebugMode) {
      AppLogger.d('[HOME] Total widgets to render: ${widgetList.length}');
    }

    return [
      // Use SliverList for lazy loading - only renders visible widgets
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            // Insert Banner Ad after the first widget (usually the hero grid)
            if (index == 1) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: (theme.brightness == Brightness.dark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AdService.instance.getBannerAdWidget(),
                  ),
                ),
              );
            }
            // Adjust index for actual content (skip index 1 which is the ad)
            final contentIndex = index > 1 ? index - 1 : index;
            if (contentIndex >= widgetList.length) return null;
            final content = _buildWidgetContent(theme, widgetList[contentIndex]);
            if (content == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: content,
            );
          },
          childCount: widgetList.length + 1, // +1 for the banner ad
        ),
      ),
      if (widgetList.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No content available',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      // Extra content rails — the home page itself only ships 2 widgets, so
      // we top up with live recommendation/daily-mix/because rails and a
      // featured-radio strip. Each renders nothing when its feed is empty.
      SliverToBoxAdapter(
        child: HomeTrackRail(
          title: 'Daily Mix',
          fetcher: RecommendationsService.instance.fetchDailyMixes,
        ),
      ),
      SliverToBoxAdapter(
        child: HomeTrackRail(
          title: 'Because You Listened',
          fetcher: RecommendationsService.instance.fetchBecauseYouListened,
        ),
      ),
      const SliverToBoxAdapter(child: _HomeRadioRail()),
      const SliverToBoxAdapter(child: SizedBox(height: 90)),
    ];
  }

  // Helper to build just the widget content (without SliverToBoxAdapter wrapper)
  Widget? _buildWidgetContent(ThemeData theme, Object? rawWidget) {
    final w = rawWidget is Map<String, dynamic> ? rawWidget : null;
    
    final display = (w?['display'] is Map<String, dynamic>) ? (w!['display'] as Map<String, dynamic>) : null;
    final type = (display?['type'] ?? '').toString();
    final title = display?['title']?.toString();

    if (kDebugMode) {
      AppLogger.d('Widget type: $type, title: $title');
    }

    List _normalizeItems(Object? raw) {
      if (raw is List) return raw;
      if (raw is Map) {
        final out = <Object?>[];
        for (final v in raw.values) {
          if (v is List) out.addAll(v);
        }
        return out;
      }
      return const [];
    }

    if (type == 'grid') {
      final items = _normalizeItems(display?['widgets'] ?? w?['items']);
      return _SliderWidget(theme: theme, title: title, items: items, parentWidgetMap: w);
    } else if (type == 'slider') {
      final items = _normalizeItems(display?['widgets'] ?? w?['items']);
      return _SliderWidget(theme: theme, title: title, items: items, parentWidgetMap: w);
    } else if (type == 'table' || type == 'list') {
      return _TableWidget(theme: theme, widgetMap: w);
    } else if (type == 'html') {
      final html = (display?['html'] ?? '').toString();
      final bgImg = (display?['bg_img'] ?? '').toString();
      final subTitle = (display?['sub_title'] ?? '').toString();
      final link = (display?['link'] ?? '').toString();
      return _HtmlWidget(
        theme: theme,
        title: title,
        subtitle: subTitle.isNotEmpty ? subTitle : null,
        html: html,
        bgImage: bgImg.isNotEmpty ? bgImg : null,
        link: link.isNotEmpty ? link : null,
      );
    } else {
      return _UnknownWidget(theme: theme, type: type, widgetMap: w);
    }
  }
}

class _SliderWidget extends StatelessWidget {
  final ThemeData theme;
  final String? title;
  final List items;
  final Map<String, dynamic>? parentWidgetMap;

  const _SliderWidget({required this.theme, required this.title, required this.items, required this.parentWidgetMap});

  // Helper to extract cover from various formats (HTML, object, string)
  String? _extractCoverFromItem(Map<String, dynamic>? map, Map<String, dynamic>? itemDisplay) {
    if (map == null) return null;
    // Combine display metadata with the raw item so nested covers are found.
    final combined = Map<String, dynamic>.from(map);
    if (itemDisplay != null) {
      for (final entry in itemDisplay.entries) {
        if (!combined.containsKey(entry.key)) {
          combined[entry.key] = entry.value;
        }
      }
    }
    return CoverImageExtractor.extract(combined);
  }

  @override
  Widget build(BuildContext context) {
    final label = (title == null || title!.isEmpty) ? '' : title!;
    final itemList = items.whereType<Map<String, dynamic>>().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) SectionHeader(title: label),
        if (label.isNotEmpty) const SizedBox(height: 4),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: itemList.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final map = itemList[index];
              final itemDisplay = (map['display'] is Map<String, dynamic>) ? (map['display'] as Map<String, dynamic>) : null;
              final itemTitle =
                  itemDisplay?['title']?.toString() ?? map['title']?.toString() ?? map['name']?.toString() ?? 'Item';
              final itemSubtitle = itemDisplay?['sub_title']?.toString() ?? map['subtitle']?.toString() ?? '';
              final cover = _extractCoverFromItem(map, itemDisplay);

              return HiTuneCard(
                imageUrl: cover,
                title: itemTitle,
                subtitle: itemSubtitle.isNotEmpty ? itemSubtitle : null,
                width: 156,
                height: 156,
                onTap: () {
                  final display = (map['display'] is Map<String, dynamic>) ? (map['display'] as Map<String, dynamic>) : null;
                  final type = (display?['type'] ?? '').toString();

                  if (type == 'html') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => InfoScreen(
                          title: (display?['title'] ?? '').toString(),
                          subtitle: (display?['sub_title'] ?? display?['subtitle'] ?? '').toString(),
                          html: (display?['html'] ?? '').toString(),
                          bg: (display?['bg_img'] ?? '').toString(),
                        ),
                      ),
                    );
                    return;
                  }

                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CollectionScreen(item: map),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HtmlWidget extends StatelessWidget {
  final ThemeData theme;
  final String? title;
  final String html;
  final String? bgImage;
  final String? link;
  final String? subtitle;

  const _HtmlWidget({
    required this.theme,
    required this.title,
    required this.html,
    this.bgImage,
    this.link,
    this.subtitle,
  });

  String _stripHtml(String input) {
    return input.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final label = (title == null || title!.isEmpty) ? 'Info' : title!;
    final sub = subtitle ?? '';
    final text = _stripHtml(html);
    final hasBgImage = bgImage != null && bgImage!.isNotEmpty;
    
    return InkWell(
      onTap: () {
        // Check if this is the iYol app info widget
        final htmlLower = html.toLowerCase();
        final isIyolApp = title?.toLowerCase().contains('iyol') == true ||
                          label.toLowerCase().contains('iyol') == true ||
                          htmlLower.contains('iyol') == true ||
                          link?.toLowerCase().contains('iyol') == true;
        
        if (kDebugMode) {
          AppLogger.d('[HOME] _HtmlWidget clicked');
          AppLogger.d('[HOME] title: $title');
          AppLogger.d('[HOME] label: $label');
          AppLogger.d('[HOME] link: $link');
          AppLogger.d('[HOME] html contains iyol: ${htmlLower.contains('iyol')}');
          AppLogger.d('[HOME] isIyolApp: $isIyolApp');
        }
        
        if (isIyolApp) {
          // Navigate to dedicated iYol app screen
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const IyolAppScreen(),
            ),
          );
        } else {
          // Navigate to generic info screen with full content
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => InfoScreen(
                title: label,
                subtitle: sub,
                html: html,
                bg: bgImage ?? '',
              ),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hasBgImage
                ? [
                    Colors.purple.withValues(alpha: 0.8),
                    Colors.blue.withValues(alpha: 0.8),
                    Colors.teal.withValues(alpha: 0.8),
                  ]
                : [
                    isDark ? const Color(0xFF2D1B69) : const Color(0xFF6B4EE6),
                    isDark ? const Color(0xFF1A1A2E) : const Color(0xFF9B7BFF),
                  ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Background image if available
              if (hasBgImage)
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: bgImage!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const SizedBox.shrink(),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              // Gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Click Now',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnknownWidget extends StatelessWidget {
  final ThemeData theme;
  final String type;
  final Map<String, dynamic>? widgetMap;

  const _UnknownWidget({required this.theme, required this.type, required this.widgetMap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final label = type.isEmpty ? 'Widget' : 'Widget ($type)';
    return Container(
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: t.textTheme.titleMedium?.copyWith(
              color: t.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This section is not supported yet.',
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Featured live-radio strip for the home page. Renders nothing when the
/// backend returns no stations.
class _HomeRadioRail extends StatelessWidget {
  const _HomeRadioRail();

  static const _colors = [
    Color(0xFFE91E63), Color(0xFF9C27B0), Color(0xFF3F51B5),
    Color(0xFF2196F3), Color(0xFF009688), Color(0xFF4CAF50),
    Color(0xFFFF9800), Color(0xFFFF5722), Color(0xFF607D8B),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: BrowseFeedService.instance.radios(),
      builder: (context, snap) {
        final radios = snap.data ?? const [];
        if (radios.isEmpty) return const SizedBox.shrink();

        final tracks = <Track>[];
        for (final r in radios) {
          final url = (r['url'] ?? r['stream_url'])?.toString();
          if (url == null || url.isEmpty) continue;
          tracks.add(Track(
            id: 'radio:$url',
            title: (r['name'] ?? r['title'] ?? 'Radio').toString(),
            subtitle: (r['sub_title'] ?? r['genre'] ?? 'Live Radio').toString(),
            url: url,
            coverUrl: (r['image'] ?? r['logo'] ?? r['cover'])?.toString(),
            sourceType: 'audio',
            objectType: 'radio',
          ));
        }
        if (tracks.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Live Radio',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tracks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  final color = _colors[t.title.hashCode.abs() % _colors.length];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => PlayerService.instance.playQueue(tracks, startIndex: i),
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: color,
                            child: Text(
                              t.title.isEmpty ? 'R' : t.title[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                if (t.subtitle != null)
                                  Text(t.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
