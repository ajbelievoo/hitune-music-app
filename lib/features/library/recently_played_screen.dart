import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import 'user_library_service.dart';
import '../../core/theme/theme_service.dart';
import '../player/models/track.dart';
import '../player/player_service.dart';
import '../player/mini_player.dart';
import '../player/widgets/music_wave_animation.dart';
import '../auth/auth_gate.dart';
import '../artist/artist_screen.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/cover_image_extractor.dart';

class RecentlyPlayedScreen extends StatefulWidget {
  const RecentlyPlayedScreen({super.key});

  @override
  State<RecentlyPlayedScreen> createState() => _RecentlyPlayedScreenState();
}

class _RecentlyPlayedScreenState extends State<RecentlyPlayedScreen> {
  final _svc = UserLibraryService();
  final _player = PlayerService.instance;

  bool _loading = false;
  String? _error;
  List<Track> _tracks = const [];

  // Currently playing track stream subscription
  StreamSubscription<Track?>? _currentTrackSub;
  Track? _currentTrack;

  @override
  void initState() {
    super.initState();
    _currentTrack = PlayerService.instance.currentTrack;
    _currentTrackSub = PlayerService.instance.currentTrackStream.listen((track) {
      if (mounted) {
        setState(() {
          _currentTrack = track;
        });
      }
    });
    _load();
  }

  @override
  void dispose() {
    _currentTrackSub?.cancel();
    super.dispose();
  }

  Track? _trackFrom(dynamic item) {
    if (item is! Map) return null;
    final m = Map<String, dynamic>.from(item);

    // Debug: Log available keys in track item
    if (kDebugMode) {
      AppLogger.d('[RecentlyPlayed] Track item keys: ${m.keys.toList()}');
      AppLogger.d('[RecentlyPlayed] Full track item: ${m.toString().substring(0, m.toString().length > 500 ? 500 : m.toString().length)}');
    }

    // Helper function to clean HTML tags
    String cleanHtml(String text) {
      if (text.isEmpty) return text;
      // Remove HTML tags and clean up whitespace
      return text
          .replaceAll(RegExp(r'<[^>]*>'), ' ') // Remove HTML tags
          .replaceAll(RegExp(r'\s+'), ' ') // Replace multiple spaces with single space
          .trim(); // Trim leading/trailing spaces
    }
    
    // Helper to normalize cover URLs - convert relative to absolute
    String normalizeCoverUrl(String url) {
      if (url.isEmpty) return url;
      final trimmed = url.trim();
      
      // If already absolute URL, return as-is
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return trimmed;
      }
      // If starts with //, add https:
      if (trimmed.startsWith('//')) {
        return 'https:$trimmed';
      }
      // If starts with /, add domain
      if (trimmed.startsWith('/')) {
        return 'https://music.hitune.in$trimmed';
      }
      // Otherwise, assume relative path
      return 'https://music.hitune.in/$trimmed';
    }

    // Handle table data structure (tds) format from user_library API
    String title = '';
    String subtitle = '';
    String artistName = '';
    String artistSlug = '';
    String cover = '';
    String objectHash = '';
    String objectType = '';
    String url = '';
    
    final tds = m['tds'];
    if (tds is List) {
      for (final cell in tds) {
        if (cell is! Map) continue;
        final cls = (cell['class'] ?? '').toString();
        final val = cell['val'];
        
        if (cls.contains('title') && val != null) {
          title = cleanHtml(val.toString());
        } else if (cls.contains('sub_title') && val != null) {
          subtitle = cleanHtml(val.toString());
        } else if (cls.contains('artist') && val != null) {
          artistName = cleanHtml(val.toString());
        } else if (cls.contains('artist_slug') && val != null) {
          artistSlug = cleanHtml(val.toString());
        } else if (cls.contains('cover') && val != null) {
          cover = normalizeCoverUrl(val.toString());
        } else if (cls.contains('object_hash') && val != null) {
          objectHash = val.toString();
        } else if (cls.contains('object_type') && val != null) {
          objectType = val.toString();
        } else if (cls.contains('url') && val != null) {
          url = val.toString();
        }
      }
    }
    
    // Fallback to direct fields
    if (title.isEmpty) {
      title = cleanHtml((m['title'] ?? m['name'] ?? '').toString());
    }
    if (subtitle.isEmpty) {
      subtitle = cleanHtml((m['artist'] ?? m['sub_title'] ?? m['subtitle'] ?? '').toString());
    }
    if (artistName.isEmpty) {
      artistName = cleanHtml((m['artist'] ?? m['artist_name'] ?? '').toString());
    }
    if (artistSlug.isEmpty) {
      artistSlug = (m['artist_slug'] ?? m['slug'] ?? '').toString();
    }
    if (cover.isEmpty) {
      // Try multiple cover field names
      final rawCover = (m['cover'] ?? m['image'] ?? m['image_thumb'] ?? m['cover_url'] ?? m['img'] ?? '').toString();
      cover = rawCover.isNotEmpty ? normalizeCoverUrl(rawCover) : '';
      
      // If cover is still empty, try to extract from nested structures
      if (cover.isEmpty) {
        // Try to get from 'raw' field if it exists
        final raw = m['raw'];
        if (raw is Map) {
          final rawCover2 = (raw['cover'] ?? raw['image'] ?? raw['image_thumb'] ?? raw['cover_url'] ?? '').toString();
          if (rawCover2.isNotEmpty) {
            cover = normalizeCoverUrl(rawCover2);
          }
        }
        // Try bof_file_cover structure
        final bofFileCover = m['bof_file_cover'];
        if (bofFileCover is Map) {
          final bofCover = (bofFileCover['image_thumb'] ?? bofFileCover['cover'] ?? bofFileCover['image'] ?? '').toString();
          if (bofCover.isNotEmpty) {
            cover = normalizeCoverUrl(bofCover);
          }
        }
      }
    }
    // Always run through the centralized extractor so maps/HTML/encoded strings resolve.
    cover = CoverImageExtractor.extract(m) ?? '';
    if (objectHash.isEmpty) {
      objectHash = (m['hash'] ?? m['object_hash'] ?? m['object'] ?? '').toString();
    }
    if (objectType.isEmpty) {
      objectType = (m['o_type'] ?? m['object_type'] ?? m['ot'] ?? m['on'] ?? 'm_track').toString();
    }
    if (url.isEmpty) {
      url = (m['url'] ?? m['address'] ?? '').toString();
    }

    if (kDebugMode) {
      AppLogger.d('[RecentlyPlayed] Extracted -> title: $title, subtitle: $subtitle, cover: $cover, artistSlug: $artistSlug, objectHash: $objectHash');
    }

    final id = (m['ID'] ?? m['id'] ?? objectHash).toString();

    if (id.isEmpty) return null;

    return Track(
      id: id,
      title: title.isEmpty ? 'Track' : title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      url: url.isEmpty ? '' : url,
      coverUrl: cover.isEmpty ? null : cover,
      objectType: objectType.isEmpty ? 'm_track' : objectType,
      objectHash: objectHash.isEmpty ? null : objectHash,
      artistSlug: artistSlug.isEmpty ? null : artistSlug,
    );
  }

  List<Track> _extractTracks(Map<String, dynamic> payload) {
    final widgets = payload['widgets'];
    dynamic node;
    if (widgets is Map) {
      final wm = Map<String, dynamic>.from(widgets);
      node = wm['history'] ?? wm['recent'] ?? wm['recently_played'] ?? wm.values.firstOrNull;
    } else if (widgets is List && widgets.isNotEmpty) {
      node = widgets.first;
    }

    dynamic items;
    if (node is Map) {
      final lm = Map<String, dynamic>.from(node);
      items = lm['items'] ?? (lm['data'] is Map ? (lm['data'] as Map)['items'] : null);
    }

    if (items is! List) return const [];

    final out = <Track>[];
    for (final it in items) {
      final t = _trackFrom(it);
      if (t != null) out.add(t);
    }
    return out;
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final loggedIn = await AuthGate.isLoggedIn();
    if (!mounted) return;
    if (!loggedIn) {
      setState(() {
        _loading = false;
        _tracks = const [];
      });
      return;
    }

    final res = await _svc.fetchUserLibrary(tab: 'history', page: 1);
    if (!mounted) return;

    if (!res.isSuccess || res.data == null) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Failed to load history';
        _tracks = const [];
      });
      return;
    }

    setState(() {
      _loading = false;
      _tracks = _extractTracks(res.data!);
    });
  }

  Future<void> _playAll(int startIndex) async {
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to play history.');
    if (!ok) return;
    await _player.playQueue(_tracks, startIndex: startIndex);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthGate.isLoggedIn(),
      builder: (context, snap) {
        final loggedIn = snap.data == true;
        return Consumer<ThemeService>(
          builder: (context, themeService, child) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            
            return Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              appBar: AppBar(
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.orangeAccent, Colors.deepOrange.shade400],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.history_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Recently Played',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                backgroundColor: theme.scaffoldBackgroundColor,
                elevation: 0,
                actions: [
                  IconButton(
                    onPressed: _loading ? null : _load,
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  )
                ],
              ),
              body: !loggedIn
                  ? _buildGuestView(theme, isDark)
                  : _loading
                      ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                      : _error != null
                          ? _buildErrorView(theme, isDark)
                          : _tracks.isEmpty
                              ? _buildEmptyView(theme, isDark)
                              : Column(
                                  children: [
                                    _buildHeaderSection(theme, isDark),
                                    Expanded(child: _buildTracksList(theme, isDark)),
                                  ],
                                ),
              bottomNavigationBar: (!loggedIn || _tracks.isEmpty || _loading)
                  ? null
                  : MiniPlayer(player: PlayerService.instance),
            );
          },
        );
      },
    );
  }

  Widget _buildHeaderSection(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.orangeAccent.withValues(alpha: 0.1),
            Colors.deepOrange.shade400.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark 
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.orangeAccent, Colors.deepOrange],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.history_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_tracks.length} Recently Played',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your listening history',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () => _playAll(0),
              icon: Icon(
                Icons.play_arrow_rounded,
                color: theme.colorScheme.primary,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestView(ThemeData theme, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orangeAccent.withValues(alpha: 0.15), Colors.deepOrange.shade400.withValues(alpha: 0.15)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(Icons.history_rounded, size: 40, color: Colors.orangeAccent.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 20),
            Text('Login to sync your history', style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.9), fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Your listening history will appear here', style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.55))),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to view Recently Played.');
                if (!ok) return;
                await _load();
              },
              child: const Text('Login'),
            ),
            const SizedBox(height: 16),
            Text(
              'Local history works while browsing as guest.\nAfter login, history will sync here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.45), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.redAccent.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black.withValues(alpha: 0.8), fontSize: 16)),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(ThemeData theme, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 64, color: Colors.orangeAccent.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No history yet', style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.65) : Colors.black.withValues(alpha: 0.65), fontSize: 16)),
          const SizedBox(height: 8),
          Text('Start playing tracks to build your history', style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.45), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildTracksList(ThemeData theme, bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _tracks.length,
        itemBuilder: (context, i) => _buildTrackCard(i, theme, isDark),
      ),
    );
  }

  Widget _buildTrackCard(int i, ThemeData theme, bool isDark) {
    final t = _tracks[i];
    final isPlaying = _currentTrack?.id == t.id && _currentTrack != null;
    final playingColor = const Color(0xFF1DB954); // Spotify green
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isPlaying 
          ? playingColor.withValues(alpha: 0.15)
          : isDark 
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlaying
            ? playingColor.withValues(alpha: 0.5)
            : isDark 
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark 
              ? Colors.black.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _playAll(i),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Album Artwork
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        isPlaying ? playingColor.withValues(alpha: 0.3) : Colors.orangeAccent.withValues(alpha: 0.2),
                        isPlaying ? playingColor.withValues(alpha: 0.1) : Colors.deepOrange.shade400.withValues(alpha: 0.2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: t.coverUrl != null && t.coverUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: t.coverUrl!,
                            fit: BoxFit.cover,
                            width: 56,
                            height: 56,
                            placeholder: (_, __) => Container(
                              color: Colors.transparent,
                              child: Icon(
                                Icons.music_note,
                                color: isDark ? Colors.white38 : Colors.black38,
                                size: 24,
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: isPlaying 
                                ? playingColor.withValues(alpha: 0.15)
                                : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                              child: Center(
                                child: Text(
                                  t.title.isNotEmpty ? t.title[0].toUpperCase() : '♪',
                                  style: TextStyle(
                                    color: isPlaying ? playingColor : (isDark ? Colors.white70 : Colors.black54),
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Container(
                            color: isPlaying 
                              ? playingColor.withValues(alpha: 0.15)
                              : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                            child: Center(
                              child: Text(
                                t.title.isNotEmpty ? t.title[0].toUpperCase() : '♪',
                                style: TextStyle(
                                  color: isPlaying ? playingColor : (isDark ? Colors.white70 : Colors.black54),
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Song Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        style: TextStyle(
                          color: isPlaying ? playingColor : (isDark ? Colors.white : Colors.black),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (t.subtitle != null && t.subtitle!.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            // Navigate to artist page if artist slug is available
                            if (t.artistSlug != null && t.artistSlug!.isNotEmpty) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ArtistScreen(artistSlug: t.artistSlug!),
                                ),
                              );
                            } else if (t.subtitle != null && t.subtitle!.isNotEmpty) {
                              // Show a message if artist slug is not available
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Artist page not available for ${t.subtitle}'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: Text(
                            t.subtitle!,
                            style: TextStyle(
                              color: isPlaying ? playingColor.withValues(alpha: 0.8) : Colors.orangeAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPlaying)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: MusicWaveAnimation(
                          color: Color(0xFF1DB954),
                          height: 20,
                          barCount: 4,
                        ),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        color: isPlaying 
                          ? playingColor.withValues(alpha: 0.2)
                          : theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        onPressed: () => _playAll(i),
                        icon: Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: isPlaying ? playingColor : theme.colorScheme.primary,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        onPressed: () async {
                          final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required.');
                          if (!ok) return;
                          await _player.toggleLike(t);
                        },
                        icon: Icon(
                          Icons.favorite_border_rounded,
                          color: Colors.orangeAccent,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull on Iterable {
  Object? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
