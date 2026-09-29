import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/network/api_service.dart';
import '../auth/auth_gate.dart';
import '../downloads/download_service.dart';
import '../share/share_dialog.dart';
import '../subscription/feature_gate.dart';
import '../subscription/subscription_service.dart';
import 'collection_service.dart';
import '../library/user_library_service.dart';
import '../artist/artist_screen.dart';
import '../player/mini_player.dart';
import '../player/models/track.dart';
import '../player/player_service.dart';
import '../player/widgets/music_wave_animation.dart';
import '../../core/ui/cover_image.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/artist_utils.dart';
import '../../core/utils/cover_image_extractor.dart';

class CollectionScreen extends StatefulWidget {
  final Map<String, dynamic> item;

  const CollectionScreen({super.key, required this.item});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _FloatingPlayButton extends StatelessWidget {
  final VoidCallback onPressed;
  final List<Map<String, dynamic>> tracks;

  const _FloatingPlayButton({
    required this.onPressed,
    required this.tracks,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: StreamBuilder<Track?>(
        stream: PlayerService.instance.currentTrackStream,
        builder: (context, trackSnapshot) {
          return StreamBuilder<PlayerState>(
            stream: PlayerService.instance.audioPlayer.playerStateStream,
            builder: (context, playerStateSnapshot) {
              final currentTrack = trackSnapshot.data;
              final isPlayingAudio = playerStateSnapshot.data?.playing ?? false;
              
              // Check if current track is from this collection
              final trackIds = tracks.map((t) => 
                (t['hash'] ?? t['id'] ?? '').toString()
              ).where((id) => id.isNotEmpty).toList();
              
              final isPlayingThisCollection = currentTrack != null && 
                                           trackIds.contains(currentTrack.id);
              final showPause = isPlayingThisCollection && isPlayingAudio;
              
              return ElevatedButton(
                onPressed: () async {
                  if (isPlayingThisCollection) {
                    // Toggle play/pause
                    if (isPlayingAudio) {
                      await PlayerService.instance.audioPlayer.pause();
                    } else {
                      await PlayerService.instance.audioPlayer.play();
                    }
                  } else {
                    // Start playing this collection
                    onPressed();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  elevation: 6,
                ),
                child: Icon(
                  showPause ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 32,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CollectionScreenState extends State<CollectionScreen> {
  late Future<List<Map<String, dynamic>>> _tracks;
  late Future<List<Map<String, dynamic>>> _relatedTracks;
  bool _likedBusy = false;
  bool _liked = false;
  bool _downloading = false;

  String? _artistSlugFromTrack(Track t) => ArtistUtils.slugFromTrack(t);

  @override
  void initState() {
    super.initState();
    _tracks = _loadTracks();
    _relatedTracks = _loadRelatedTracks();
    if (kDebugMode) AppLogger.d('[CollectionScreen] initState - _relatedTracks initialized');
    _initLiked();
  }

  Future<void> _initLiked() async {
    try {
      final loggedIn = await AuthGate.isLoggedIn();
      if (!loggedIn) return;
      final target = _pickLikeTarget();
      if (target == null) return;
      final object = target['object'] ?? '';
      if (object.isEmpty) return;

      final res = await UserLibraryService().fetchUserLibrary(tab: 'likes', page: 1);
      if (!res.isSuccess || res.data == null) return;
      final payload = res.data!;

      final widgets = payload['widgets'];
      dynamic likesNode;
      if (widgets is Map) {
        final wm = Map<String, dynamic>.from(widgets);
        likesNode = wm['likes'] ?? wm['like'] ?? wm['favorites'];
      } else if (widgets is List && widgets.isNotEmpty) {
        likesNode = widgets.first;
      }

      dynamic items;
      if (likesNode is Map) {
        final lm = Map<String, dynamic>.from(likesNode);
        items = lm['items'] ?? (lm['data'] is Map ? (lm['data'] as Map)['items'] : null);
      }
      if (items is! List) return;

      bool liked = false;
      for (final it in items) {
        if (it is! Map) continue;
        final m = Map<String, dynamic>.from(it);
        final h = (m['hash'] ?? m['object_hash'] ?? m['object'] ?? '').toString();
        if (h.isNotEmpty && h == object) {
          liked = true;
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _liked = liked;
      });
    } catch (_) {
      // ignore
    }
  }

  Map<String, dynamic> get item => widget.item;

  String _pickTitle() {
    final display = item['display'] is Map<String, dynamic> ? (item['display'] as Map<String, dynamic>) : null;
    final t = (display?['title'] ?? item['title'] ?? item['name'] ?? '').toString();
    return t.isEmpty ? 'Collection' : t;
  }

  String? _pickListWidgetHash() {
    final display = item['display'] is Map<String, dynamic> ? (item['display'] as Map<String, dynamic>) : null;
    final link = (display?['link'] ?? '').toString();
    if (link.isEmpty) {
      final pagination = display?['pagination'];
      final id = (item['ID'] ?? '').toString();
      if ((pagination == true || pagination is String) && id.isNotEmpty) return id;
      return null;
    }
    // Expected format: list/<hash>
    if (!link.startsWith('list/')) return null;
    final parts = link.split('/');
    if (parts.length < 2) return null;
    final hash = parts[1];
    return hash.isEmpty ? null : hash;
  }

  Map<String, String>? _pickLikeTarget() {
    final display = item['display'] is Map<String, dynamic> ? (item['display'] as Map<String, dynamic>) : null;
    final ot = (display?['o_type'] ?? item['ot'] ?? item['object_type'] ?? item['o_type'] ?? '').toString();
    final directHash = (item['hash'] ?? item['object_hash'] ?? item['object'] ?? '').toString();

    final objectHash = directHash.isNotEmpty ? directHash : (_pickListWidgetHash() ?? '');
    if (objectHash.isEmpty) return null;

    final link = (display?['link'] ?? '').toString();
    final isList = link.startsWith('list/') || _pickListWidgetHash() != null;

    // For list widgets, backend expects m_list.
    final objectType = isList ? 'm_list' : (ot.isEmpty ? 'm_list' : ot);
    return {
      'object_type': objectType,
      'object': objectHash,
    };
  }

  Future<void> _toggleLikeCollection() async {
    if (_likedBusy) return;
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to like.');
    if (!ok) return;

    final target = _pickLikeTarget();
    if (target == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Like not available for this item.')));
      return;
    }

    setState(() {
      _likedBusy = true;
      _liked = !_liked;
    });

    try {
      final endpoint = _liked ? 'like' : 'unlike';
      final res = await ApiService.instance.postRaw(endpoint: endpoint, data: target);
      if (!res.isSuccess) {
        throw Exception(res.error?.message ?? 'Failed');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_liked ? 'Added to Your Library' : 'Removed from Your Library'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = !_liked;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _likedBusy = false;
      });
    }
  }

  Future<void> _addAllToQueue() async {
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to add to queue.');
    if (!ok) return;
    try {
      final items = await _tracks;
      final tracks = _toTracks(items);
      if (tracks.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No playable tracks found.')));
        return;
      }
      final player = PlayerService.instance;
      final nextQueue = [...player.queue, ...tracks];
      await player.playQueue(nextQueue, startIndex: player.queue.isEmpty ? 0 : player.index);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${tracks.length} songs to queue')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  /// Spotify-style "download the whole collection" — resolves each track and
  /// saves it via DownloadService. Premium-gated (offline_downloads feature).
  Future<void> _downloadAll() async {
    if (_downloading) return;
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to download.');
    if (!ok || !mounted) return;
    final allowed = await FeatureGate.require(
      context,
      AppFeatures.offlineDownloads,
      customTitle: 'Offline Downloads',
    );
    if (!allowed || !mounted) return;

    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final items = await _tracks;
      final tracks = _toTracks(items);
      if (tracks.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('No tracks to download.')));
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('Downloading ${tracks.length} songs...')));
      var done = 0;
      var failed = 0;
      for (final t in tracks) {
        try {
          final already = await DownloadService.instance.isDownloaded(t);
          if (already) {
            done++;
            continue;
          }
          final url = await PlayerService.instance.resolveUrlFor(t);
          if (url.isEmpty || url.contains('.m3u8') || url.contains('.ts')) {
            failed++;
            continue;
          }
          await DownloadService.instance.download(t, url);
          done++;
        } catch (_) {
          failed++;
        }
      }
      messenger.showSnackBar(SnackBar(
        content: Text(failed == 0
            ? 'Downloaded $done songs for offline playback'
            : 'Downloaded $done songs ($failed unavailable)'),
      ));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _openMoreSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(99)),
              ),
              ListTile(
                leading: Icon(_liked ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: _liked ? const Color(0xFF1DB954) : Colors.white),
                title: Text(_liked ? 'Remove from Your Library' : 'Add to Your Library', style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _toggleLikeCollection();
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded, color: Colors.white),
                title: const Text('Add to queue', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _addAllToQueue();
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_for_offline_outlined, color: Colors.white),
                title: const Text('Download', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _downloadAll();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  List<Track> _toTracks(List<Map<String, dynamic>> items) {
    final out = <Track>[];
    
    // Get album cover with blacklist bypass for fallback
    String? albumCoverUrl;
    for (final item in items) {
      albumCoverUrl = _extractTrackCoverUrlWithBlacklistBypass(item);
      if (albumCoverUrl != null) break;
    }
    if (kDebugMode) AppLogger.d('[Collection] Album cover for fallback: $albumCoverUrl');
    
    for (final t in items) {
      // Try multiple possible hash field names
      var hash = (t['hash'] ?? '').toString();
      if (hash.isEmpty) hash = (t['object_hash'] ?? '').toString();
      if (hash.isEmpty) hash = (t['objectHash'] ?? '').toString();
      if (hash.isEmpty) hash = (t['ID'] ?? '').toString();
      if (hash.isEmpty) hash = (t['id'] ?? '').toString();
      if (hash.isEmpty) hash = (t['object'] ?? '').toString();
      
      final ot = (t['ot'] ?? t['object_type'] ?? '').toString();
      final title = _extractTrackTitle(t) ?? 'Track';
      final subtitle = _extractTrackSubtitle(t);
      
      // Try to get track cover, fallback to album cover
      var coverUrl = _extractTrackCoverUrl(t);
      if (coverUrl == null || coverUrl.isEmpty) {
        coverUrl = albumCoverUrl;
        if (kDebugMode && coverUrl != null) {
          AppLogger.d('[Collection] Using album cover for track: $title');
        }
      }
      
      final url = (t['url'] ?? '').toString();
      
      // Debug: Check raw data for URL
      final raw = t['raw'];
      if (raw is Map && (url.isEmpty || url == '')) {
        final rawUrl = raw['url']?.toString();
        final rawHash = raw['hash']?.toString();
        if (kDebugMode) {
          AppLogger.d('[Collection] Track $title has empty URL, raw.url=$rawUrl, raw.hash=$rawHash');
        }
      }
      
      if (kDebugMode) {
        AppLogger.d('[Collection] Track: $title, hash=$hash, url=${url.isEmpty ? "EMPTY" : url.substring(0, url.length > 30 ? 30 : url.length)}, ot=$ot');
      }
      
      if (hash.isEmpty) {
        if (kDebugMode) {
          AppLogger.d('[Collection] Skipping track - empty hash. Available keys: ${t.keys.toList()}');
        }
        continue;
      }

      String? _parseArtistSlugFromLink(String? link) {
        final l = (link ?? '').toString().trim();
        if (l.isEmpty) return null;
        final cleaned = l.startsWith('/') ? l.substring(1) : l;
        final m = RegExp(r'^music/artist/([^/?#]+)', caseSensitive: false).firstMatch(cleaned);
        final slug = m?.group(1);
        return (slug == null || slug.isEmpty) ? null : slug;
      }

      final directSlug = (t['artist_slug'] ?? t['artistSlug'] ?? t['slug'] ?? t['artist_hash'] ?? '').toString();
      final linkSlug = _parseArtistSlugFromLink((t['sub_link'] ?? t['artist_link'] ?? t['artistLink'] ?? '').toString());
      final artistSlug = directSlug.isNotEmpty ? directSlug : linkSlug;
      final artistLink = (t['sub_link'] ?? t['artist_link'] ?? '').toString();

      out.add(
        Track(
          id: hash,
          title: title,
          subtitle: subtitle,
          url: url,
          coverUrl: coverUrl,
          artistSlug: artistSlug,
          artistLink: artistLink.isEmpty ? null : artistLink,
          objectType: ot.isEmpty ? 'm_track' : ot,
          objectHash: hash,
          aiPct: Track.aiPctFromJson(t),
        ),
      );
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _loadTracks() async {
    // Debug: Log item keys to understand structure
    if (kDebugMode) {
      AppLogger.d('[CollectionScreen] _loadTracks() - item keys: ${item.keys.toList()}');
      AppLogger.d('[CollectionScreen] _loadTracks() - item[items] type: ${item['items']?.runtimeType}');
    }
    
    // Check if this is a single track (has id/url but no items list)
    final trackId = (item['id'] ?? item['hash'] ?? '').toString();
    final trackUrl = (item['url'] ?? '').toString();
    final hasItemsList = item['items'] is List && (item['items'] as List).isNotEmpty;
    final ot = (item['ot'] ?? item['object_type'] ?? '').toString();

    if (kDebugMode) {
      AppLogger.d('[CollectionScreen] _loadTracks() - trackId: $trackId, trackUrl: $trackUrl, hasItemsList: $hasItemsList, ot: $ot');
    }

    // Albums/lists must fall through to the fetch-by-slug path — they carry
    // an `id`/`hash` too, but are not playable single tracks.
    final isTrackLike = ot.isEmpty || ot == 'm_track' || ot == 'track';
    if (isTrackLike && trackId.isNotEmpty && !hasItemsList) {
      if (kDebugMode) AppLogger.d('[CollectionScreen] _loadTracks() - Treating as single track');
      return [Map<String, dynamic>.from(item)];
    }
    
    final rawItems = item['items'];
    if (rawItems is List) {
      final tracks = rawItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (kDebugMode) AppLogger.d('[CollectionScreen] _loadTracks() - Found ${tracks.length} tracks in item[items]');
      return tracks;
    }
    if (rawItems is Map) {
      final out = <Map<String, dynamic>>[];
      for (final v in rawItems.values) {
        if (v is List) {
          out.addAll(v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        }
      }
      if (out.isNotEmpty) {
        if (kDebugMode) AppLogger.d('[CollectionScreen] _loadTracks() - Found ${out.length} tracks in item[items] (Map)');
        return out;
      }
    }

    final widgetHash = _pickListWidgetHash();
    if (kDebugMode) AppLogger.d('[CollectionScreen] _loadTracks() - widgetHash: $widgetHash');
    if (widgetHash != null) {
      final res = await CollectionService().fetchListWidget(widgetHash: widgetHash);
      if (res.isSuccess) {
        final payload = res.data!;
        final tracks = _extractTracksFromPayload(payload);
        if (kDebugMode) AppLogger.d('[CollectionScreen] _loadTracks() - Found ${tracks.length} tracks from widget API');
        if (tracks.isNotEmpty) return tracks;
      }
    }

    // Fallback: fetch the album page by slug (m_album?slug=...).
    final albumSlug = _pickAlbumSlug();
    if (kDebugMode) AppLogger.d('[CollectionScreen] _loadTracks() - albumSlug: $albumSlug');
    if (albumSlug != null) {
      final res = await CollectionService().fetchCollectionDetail(hash: '', slug: albumSlug);
      if (res.isSuccess) {
        final payload = res.data!;
        final tracks = _extractTracksFromPayload(payload);
        if (kDebugMode) AppLogger.d('[CollectionScreen] _loadTracks() - Found ${tracks.length} tracks from album API');
        if (tracks.isNotEmpty) return tracks;
      } else {
        if (kDebugMode) AppLogger.d('[CollectionScreen] _loadTracks() - Album API failed: ${res.error?.message}');
      }
    }

    if (kDebugMode) AppLogger.d('[CollectionScreen] _loadTracks() - No tracks found, returning empty list');
    return const [];
  }

  Future<List<Map<String, dynamic>>> _loadRelatedTracks() async {
    // Get track ID from various possible fields
    final trackId = (item['id'] ?? item['hash'] ?? item['object_hash'] ?? item['object'] ?? '').toString();
    final hasItemsList = item['items'] is List && (item['items'] as List).isNotEmpty;
    
    if (kDebugMode) {
      AppLogger.d('[CollectionScreen] _loadRelatedTracks() - trackId: $trackId, hasItemsList: $hasItemsList');
      AppLogger.d('[CollectionScreen] _loadRelatedTracks() - item keys: ${item.keys.toList()}');
    }
    
    // If this is a collection with items list, don't show related tracks
    if (hasItemsList) {
      if (kDebugMode) AppLogger.d('[CollectionScreen] _loadRelatedTracks() - Has items list, skipping related tracks');
      return const [];
    }
    
    // If no track ID, can't fetch related tracks
    if (trackId.isEmpty) {
      if (kDebugMode) AppLogger.d('[CollectionScreen] _loadRelatedTracks() - No track ID found');
      return const [];
    }
    
    // For single tracks, always try to fetch related tracks
    try {
      if (kDebugMode) AppLogger.d('[CollectionScreen] _loadRelatedTracks() - Fetching related tracks for: $trackId');
      final res = await CollectionService().fetchRelatedTracks(trackHash: trackId, limit: 10);
      if (!res.isSuccess || res.data == null) {
        if (kDebugMode) AppLogger.d('[CollectionScreen] _loadRelatedTracks() - Failed to fetch: ${res.error?.message}');
        return const [];
      }
      
      final tracks = _extractTracksFromPayload(res.data!);
      if (kDebugMode) AppLogger.d('[CollectionScreen] _loadRelatedTracks() - Found ${tracks.length} related tracks');
      return tracks;
    } catch (e, stack) {
      if (kDebugMode) {
        AppLogger.d('[CollectionScreen] _loadRelatedTracks() - Error: $e');
        AppLogger.d('[CollectionScreen] _loadRelatedTracks() - Stack: $stack');
      }
      return const [];
    }
  }

  String? _pickAlbumSlug() {
    // Album items carry `url: "music/album/<slug>"` — the m_album endpoint
    // only accepts slugs (`?hash=` 404s).
    for (final key in const ['url', 'link']) {
      final raw = (item[key] ?? '').toString();
      final m = RegExp(r'album/([^/?#]+)', caseSensitive: false).firstMatch(raw);
      final slug = m?.group(1);
      if (slug != null && slug.isNotEmpty) return slug;
    }
    final display = item['display'] is Map<String, dynamic> ? (item['display'] as Map<String, dynamic>) : null;
    final link = (display?['link'] ?? '').toString();
    if (link.isNotEmpty) {
      final m = RegExp(r'album/([^/?#]+)', caseSensitive: false).firstMatch(link);
      final slug = m?.group(1);
      if (slug != null && slug.isNotEmpty) return slug;
      final parts = link.split('/');
      if (parts.length >= 2 && parts.last.isNotEmpty) return parts.last;
    }
    return null;
  }

  List<Map<String, dynamic>> _extractTracksFromPayload(Map<String, dynamic> payload) {
    if (kDebugMode) AppLogger.d('[CollectionScreen] _extractTracksFromPayload - keys: ${payload.keys.toList()}');
    
    // Try multiple formats (same strategy as Home table widget)
    final widgets = payload['widgets'];
    if (kDebugMode) AppLogger.d('[CollectionScreen] _extractTracksFromPayload - widgets type: ${widgets.runtimeType}');
    
    if (widgets is List && widgets.isNotEmpty) {
      if (kDebugMode) AppLogger.d('[CollectionScreen] _extractTracksFromPayload - widgets count: ${widgets.length}');
      
      for (int i = 0; i < widgets.length; i++) {
        final widget = widgets[i];
        if (widget is Map) {
          // Try display.widgets first (home page format)
          final display = widget['display'];
          if (display is Map) {
            final displayWidgets = display['widgets'];
            if (displayWidgets is List && displayWidgets.isNotEmpty) {
              if (kDebugMode) AppLogger.d('[CollectionScreen] _extractTracksFromPayload - Found ${displayWidgets.length} tracks in display.widgets');
              return displayWidgets.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            }
          }
          
          // Try direct items
          final items = widget['items'];
          if (kDebugMode) AppLogger.d('[CollectionScreen] _extractTracksFromPayload - widget[$i] items type: ${items.runtimeType}');
          
          if (items is List && items.isNotEmpty) {
            if (kDebugMode) AppLogger.d('[CollectionScreen] _extractTracksFromPayload - Found ${items.length} tracks in widget[$i]');
            return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          }
          
          // Try items as Map (keyed by string)
          if (items is Map) {
            final out = <Map<String, dynamic>>[];
            for (final v in items.values) {
              if (v is List) {
                out.addAll(v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
              }
            }
            if (out.isNotEmpty) {
              if (kDebugMode) AppLogger.d('[CollectionScreen] _extractTracksFromPayload - Found ${out.length} tracks in widget[$i] items map');
              return out;
            }
          }
        }
      }
    }

    final directItems = payload['items'];
    if (directItems is List && directItems.isNotEmpty) {
      if (kDebugMode) AppLogger.d('[CollectionScreen] _extractTracksFromPayload - Found ${directItems.length} direct items');
      return directItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }

    final data = payload['data'];
    if (data is Map) {
      final dataItems = data['items'];
      if (dataItems is List && dataItems.isNotEmpty) {
        if (kDebugMode) AppLogger.d('[CollectionScreen] _extractTracksFromPayload - Found ${dataItems.length} items in data');
        return dataItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }

    if (kDebugMode) AppLogger.d('[CollectionScreen] _extractTracksFromPayload - No tracks found in payload');
    return const [];
  }

  String? _extractTrackTitle(Map<String, dynamic> t) {
    final raw = t['raw'];
    if (raw is Map && raw['title'] != null) return raw['title'].toString();

    // Table items often store the title HTML inside tds.
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

    final title = t['title'];
    if (title == null) return null;
    final cleaned = title.toString().replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  String? _extractTrackSubtitle(Map<String, dynamic> t) {
    final raw = t['raw'];
    if (raw is Map && raw['sub_data'] != null) return raw['sub_data'].toString();
    final sub = t['sub_data'] ?? t['subtitle'] ?? t['subTitle'];
    final s = sub?.toString() ?? '';
    return s.isEmpty ? null : s;
  }

  String? _extractTrackCoverUrl(Map<String, dynamic> t) {
    // cover_url is a plain CDN URL on many backend items (album track rows,
    // home widgets) — the central extractor knows all these shapes.
    final direct = CoverImageExtractor.extract(t);
    if (direct != null && direct.isNotEmpty) return direct;

    if (kDebugMode) {
      AppLogger.d('[CollectionScreen] === Extracting cover ===');
      AppLogger.d('[CollectionScreen] Track keys: ${t.keys.toList()}');
    }

    // PRIORITY 1: Check tds first (backend converts cover to tds)
    final tds = t['tds'];
    if (tds is List) {
      if (kDebugMode) AppLogger.d('[CollectionScreen] Checking ${tds.length} tds cells');
      for (final cell in tds) {
        if (cell is! Map) continue;
        final cls = (cell['class'] ?? '').toString();
        final val = (cell['val'] ?? '').toString();
        
        // Check for cover class specifically
        if (cls.split(' ').contains('cover')) {
          if (kDebugMode) AppLogger.d('[CollectionScreen] Found cover cell, val length: ${val.length}');
          if (kDebugMode) AppLogger.d('[CollectionScreen] Cover HTML: ${val.substring(0, val.length > 200 ? 200 : val.length)}...');
          final url = _extractUrlFromHtml(val);
          if (url != null && !_isBlacklistedUrl(url)) {
            if (kDebugMode) AppLogger.d('[CollectionScreen] ✅ Extracted cover URL from tds: $url');
            return url;
          }
        }
      }
    }
    
    // PRIORITY 2: Check raw.cover (before parsing)
    final raw = t['raw'];
    if (raw is Map) {
      final rawCover = raw['cover'];
      if (rawCover is Map) {
        final imageThumb = rawCover['image_thumb']?.toString();
        if (imageThumb != null && imageThumb.isNotEmpty && imageThumb.startsWith('http')) {
          if (!_isBlacklistedUrl(imageThumb)) {
            if (kDebugMode) AppLogger.d('[CollectionScreen] ✅ Found cover in raw.cover.image_thumb: $imageThumb');
            return imageThumb;
          }
        }
        // Try image_strings
        final imageStrings = rawCover['image_strings'];
        if (imageStrings is Map) {
          final s1 = imageStrings['1'] ?? imageStrings[1];
          if (s1 is Map) {
            final html = s1['html']?.toString() ?? '';
            final url = _extractUrlFromHtml(html);
            if (url != null && !_isBlacklistedUrl(url)) {
              if (kDebugMode) AppLogger.d('[CollectionScreen] ✅ Found cover in raw.cover.image_strings: $url');
              return url;
            }
          }
        }
      }
      if (rawCover is String && rawCover.isNotEmpty) {
        final url = _extractUrlFromHtml(rawCover);
        if (url != null && !_isBlacklistedUrl(url)) {
          if (kDebugMode) AppLogger.d('[CollectionScreen] ✅ Found cover in raw string: $url');
          return url;
        }
      }
    }

    // PRIORITY 3: Check direct cover field (might still have object)
    final coverObj = t['cover'];
    if (coverObj is Map) {
      final imageThumb = coverObj['image_thumb']?.toString();
      if (imageThumb != null && imageThumb.isNotEmpty && imageThumb.startsWith('http')) {
        if (!_isBlacklistedUrl(imageThumb)) {
          if (kDebugMode) AppLogger.d('[CollectionScreen] ✅ Found cover in cover object: $imageThumb');
          return imageThumb;
        }
      }
    }
    if (coverObj is String && coverObj.isNotEmpty) {
      final url = _extractUrlFromHtml(coverObj);
      if (url != null && !_isBlacklistedUrl(url)) {
        if (kDebugMode) AppLogger.d('[CollectionScreen] ✅ Found cover in cover string: $url');
        return url;
      }
    }

    // PRIORITY 4: Check display object
    final display = t['display'];
    if (display is Map) {
      final displayCover = display['cover'] ?? display['image'] ?? display['bg_img'];
      if (displayCover is Map) {
        final displayThumb = displayCover['image_thumb']?.toString();
        if (displayThumb != null && displayThumb.isNotEmpty && displayThumb.startsWith('http')) {
          if (!_isBlacklistedUrl(displayThumb)) {
            if (kDebugMode) AppLogger.d('[CollectionScreen] ✅ Found cover in display object: $displayThumb');
            return displayThumb;
          }
        }
      }
    }

    if (kDebugMode) AppLogger.d('[CollectionScreen] ❌ No cover found for track');
    return null;
  }

  String? _extractUrlFromHtml(String html) {
    final url = _extractUrlFromHtmlRaw(html);
    return CoverImageExtractor.isUsableUrl(url) ? url : null;
  }

  String? _extractUrlFromHtmlRaw(String html) {
    if (html.isEmpty) return null;
    
    // URL decode if the string contains encoded HTML entities
    String decoded = html;
    if (html.contains('%3C') || html.contains('%3E') || html.contains('%22')) {
      try {
        decoded = Uri.decodeComponent(html);
      } catch (_) {
        // If decoding fails, use original
      }
    }
    
    // Try srcset first for higher quality
    final srcsetMatch = RegExp(r'srcset="([^"]+)"', caseSensitive: false).firstMatch(decoded);
    if (srcsetMatch != null) {
      final srcset = srcsetMatch.group(1);
      if (srcset != null && srcset.isNotEmpty) {
        final urls = srcset.split(',');
        if (urls.isNotEmpty) {
          final first = urls.first.trim();
          final spaceIndex = first.indexOf(' ');
          final url = spaceIndex > 0 ? first.substring(0, spaceIndex) : first;
          if (url.startsWith('http')) return url;
        }
      }
    }
    
    // Try img src with double quotes
    final imgMatch = RegExp(r'<img[^>]+src="([^"]+)"', caseSensitive: false).firstMatch(decoded);
    if (imgMatch != null) {
      final url = imgMatch.group(1);
      if (url != null && url.isNotEmpty && url.startsWith('http')) return url;
    }
    
    // Try img src with single quotes
    final imgMatchSingle = RegExp(r"<img[^>]+src='([^'>]+)", caseSensitive: false).firstMatch(decoded);
    if (imgMatchSingle != null) {
      final url = imgMatchSingle.group(1);
      if (url != null && url.isNotEmpty && url.startsWith('http')) return url;
    }
    
    // Try direct URL if it's not HTML
    if (!decoded.contains('<')) {
      final trimmed = decoded.trim();
      if (trimmed.startsWith('http')) {
        return trimmed;
      }
    }
    
    // Extract any http URL from the string
    final urlMatch = RegExp(r'https?://[a-zA-Z0-9._/~:/?#\\[\\]@!$&\\(\\)*+,;=%-]+', caseSensitive: false).firstMatch(decoded);
    if (urlMatch != null) {
      final url = urlMatch.group(0);
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
    
    return null;
  }

  String? _extractTrackCoverUrlWithBlacklistBypass(Map<String, dynamic> t) {
    // The central extractor already covers every shape handled here before
    // (tds cells, raw.cover maps, plain-string covers, HTML) and rejects
    // backend dummy placeholders.
    return CoverImageExtractor.extract(t);
  }

  bool _isBlacklistedUrl(String url) => false;

  String? _pickSubtitle() {
    final display = item['display'] is Map<String, dynamic> ? (item['display'] as Map<String, dynamic>) : null;
    final st = (display?['sub_title'] ?? display?['subtitle'] ?? item['subtitle'] ?? item['sub_title'] ?? '').toString();
    return st.isEmpty ? null : st;
  }

  String? _pickImageUrl() {
    final display = item['display'] is Map<String, dynamic> ? (item['display'] as Map<String, dynamic>) : null;
    
    if (kDebugMode) {
      AppLogger.d('[CollectionScreen] _pickImageUrl - item keys: ${item.keys.toList()}');
      AppLogger.d('[CollectionScreen] _pickImageUrl - display keys: ${display?.keys.toList()}');
      AppLogger.d('[CollectionScreen] _pickImageUrl - item[cover] type: ${item['cover']?.runtimeType}');
      AppLogger.d('[CollectionScreen] _pickImageUrl - display[cover] type: ${display?['cover']?.runtimeType}');
      AppLogger.d('[CollectionScreen] _pickImageUrl - display[bg_img] type: ${display?['bg_img']?.runtimeType}');
      AppLogger.d('[CollectionScreen] _pickImageUrl - display[bg_img] value: ${display?['bg_img']}');
      AppLogger.d('[CollectionScreen] _pickImageUrl - item[bg_img] type: ${item['bg_img']?.runtimeType}');
      AppLogger.d('[CollectionScreen] _pickImageUrl - item[bg_img] value: ${item['bg_img']}');
    }

    String normalizeUrl(String url) {
      var u = url.trim().replaceAll('\\/', '/');
      if (u.startsWith('//')) u = 'https:$u';
      return u;
    }

    // URL decode if needed and extract image from HTML
    String? extractFromHtml(String? value) {
      if (value == null) return null;
      // URL decode if the string contains encoded HTML entities
      String decoded = value;
      if (value.contains('%3C') || value.contains('%3E') || value.contains('%22')) {
        try {
          decoded = Uri.decodeComponent(value);
        } catch (_) {
          // If decoding fails, use original
        }
      }
      // Now extract URL from decoded HTML
      return _extractUrlFromHtml(decoded);
    }

    String? pickUrl(Object? node) {
      if (node == null) return null;
      if (node is String) {
        // First try to extract from HTML (handles both encoded and decoded)
        final fromHtml = extractFromHtml(node);
        if (fromHtml != null) {
          if (kDebugMode) AppLogger.d('[CollectionScreen] pickUrl extracted from HTML: $fromHtml');
          return fromHtml;
        }
        
        // If not HTML, treat as direct URL
        final normalized = normalizeUrl(node);
        // Simple regex to extract HTTP URL
        final urlPattern = RegExp(r'https?://[^\s<>]+', caseSensitive: false);
        final match = urlPattern.firstMatch(normalized);
        if (match == null) return null;
        final extractedUrl = match.group(0);
        if (extractedUrl == null) return null;
        final finalUrl = normalizeUrl(extractedUrl);
        if (CoverImageExtractor.isUsableUrl(finalUrl)) return finalUrl;
        return null;
      }
      if (node is Map) {
        // Full-size fields first — image_thumb is a tiny variant and makes
        // the wallpaper look blurry.
        final direct = node['cover_url'] ?? node['image'] ?? node['cover'] ??
            node['bg_img'] ?? node['img'] ?? node['url'];
        final got = pickUrl(direct);
        if (got != null) return got;

        // Check for image_strings (common backend format)
        final imageStrings = node['image_strings'];
        if (imageStrings is Map) {
          final s1 = imageStrings['1'] ?? imageStrings[1];
          if (s1 is Map) {
            final html = s1['html']?.toString() ?? '';
            if (html.isNotEmpty) {
              final url = _extractUrlFromHtml(html);
              if (url != null) {
                if (kDebugMode) AppLogger.d('[CollectionScreen] pickUrl extracted from image_strings: $url');
                return url;
              }
            }
          }
        }

        // Thumbnails are the last resort.
        final imageThumb = node['image_thumb']?.toString();
        if (imageThumb != null && imageThumb.isNotEmpty && imageThumb.startsWith('http') &&
            CoverImageExtractor.isUsableUrl(imageThumb)) {
          if (kDebugMode) AppLogger.d('[CollectionScreen] pickUrl found image_thumb: $imageThumb');
          return imageThumb;
        }

        // Recurse into values
        for (final v in node.values) {
          final got2 = pickUrl(v);
          if (got2 != null) return got2;
        }
      }
      if (node is List) {
        for (final v in node) {
          final got = pickUrl(v);
          if (got != null) return got;
        }
      }
      return null;
    }

    // Try multiple cover sources in priority order
    final sources = [
      display?['bg_img'],
      display?['img'],
      display?['cover_url'],
      display?['image'],
      display?['cover'],
      item['bg_img'],
      item['img'],
      item['cover_url'],
      item['image'],
      item['cover'],
      // Also check raw if available
      item['raw'] is Map ? (item['raw'] as Map)['cover'] : null,
    ];
    
    for (final source in sources) {
      final url = pickUrl(source);
      if (url != null && CoverImageExtractor.isUsableUrl(url)) {
        if (kDebugMode) AppLogger.d('[CollectionScreen] _pickImageUrl found URL from source: $url');
        return url;
      }
    }
    
    if (kDebugMode) AppLogger.d('[CollectionScreen] _pickImageUrl - no URL found');
    return null;
  }

  String? _pickStatsText(List<Map<String, dynamic>> tracks) {
    final display = item['display'] is Map<String, dynamic> ? (item['display'] as Map<String, dynamic>) : null;
    final saves = (display?['saves'] ?? display?['save_count'] ?? '').toString().trim();
    final duration = (display?['duration'] ?? display?['time'] ?? '').toString().trim();

    final parts = <String>[];
    if (tracks.isNotEmpty) parts.add('${tracks.length} songs');
    if (saves.isNotEmpty) parts.add('$saves saves');
    if (duration.isNotEmpty) parts.add(duration);

    if (parts.isEmpty) return null;
    return parts.join('  •  ');
  }

  Widget _actionIcon({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
    double size = 24,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: size, color: color ?? (isDark ? Colors.white : Colors.black).withValues(alpha: 0.85)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final title = _pickTitle();
    final subtitle = _pickSubtitle();
    final imageUrl = _pickImageUrl();

    // iTunes artwork lookup only makes sense for real album/track pages —
    // generic list titles ("Latest Songs") would match random art, and
    // lists already fall back to the first track's cover below.
    final displayMap = item['display'] is Map<String, dynamic> ? item['display'] as Map<String, dynamic> : null;
    final objectType = (item['ot'] ?? item['object_type'] ?? displayMap?['o_type'] ?? '').toString();
    final canLookupArtwork = objectType == 'm_album' || objectType == 'm_track';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.45),
                    isDark ? Colors.black : Colors.white,
                  ],
                ),
              ),
            ),
          ),
          // Album artwork as the page wallpaper (Spotify-style), when the
          // item carries a cover.
          if (imageUrl != null && imageUrl.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.55)),
            ),
          ),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _tracks = _loadTracks();
                });
              },
              child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white : Colors.black),
                  ),
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _tracks,
                          builder: (context, snap) {
                            String? cover = imageUrl;
                            if (cover == null || cover.isEmpty) {
                              final items = snap.data ?? const [];
                              if (items.isNotEmpty) {
                                // Try to get cover from first track, bypassing blacklist for album art
                                cover = _extractTrackCoverUrlWithBlacklistBypass(items.first);
                              }
                            }
                            return Align(
                              alignment: Alignment.center,
                              child: _CoverArt(
                                imageUrl: cover,
                                isDark: isDark,
                                lookupTitle: canLookupArtwork ? title : null,
                                lookupSubtitle: subtitle,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.72)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 10),
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _tracks,
                          builder: (context, snapshot) {
                            final tracks = snapshot.data ?? const [];
                            final stats = _pickStatsText(tracks);
                            if (stats == null || stats.isEmpty) return const SizedBox.shrink();
                            return Text(
                              stats,
                              style: theme.textTheme.bodySmall?.copyWith(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.65)),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 52,
                          child: Row(
                            children: [
                              // Mini cover thumb (Spotify-style leading artwork)
                              if (imageUrl != null && imageUrl.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      width: 38,
                                      height: 38,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              // Add to / Remove from Your Library (+ / green check)
                              _actionIcon(
                                icon: _liked ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                color: _liked ? const Color(0xFF1DB954) : null,
                                onPressed: _toggleLikeCollection,
                              ),
                              // Download whole collection (premium)
                              _actionIcon(
                                icon: _downloading
                                    ? Icons.downloading_rounded
                                    : Icons.download_for_offline_outlined,
                                onPressed: _downloadAll,
                              ),
                              _actionIcon(
                                icon: Icons.more_horiz,
                                onPressed: _openMoreSheet,
                              ),
                              const Spacer(),
                              // Shuffle toggle — green when on (persisted on the
                              // player; playQueue picks it up and shuffles)
                              StreamBuilder<bool>(
                                stream: PlayerService.instance.audioPlayer.shuffleModeEnabledStream,
                                initialData: PlayerService.instance.audioPlayer.shuffleModeEnabled,
                                builder: (context, snap) {
                                  final on = snap.data ?? false;
                                  return IconButton(
                                    onPressed: () => PlayerService.instance
                                        .audioPlayer
                                        .setShuffleModeEnabled(!on),
                                    icon: Icon(
                                      Icons.shuffle_rounded,
                                      color: on
                                          ? const Color(0xFF1DB954)
                                          : (isDark ? Colors.white : Colors.black)
                                              .withValues(alpha: 0.85),
                                    ),
                                  );
                                },
                              ),
                              FutureBuilder<List<Map<String, dynamic>>>(
                                future: _tracks,
                                builder: (context, snapshot) {
                                  // Don't show anything while loading
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const SizedBox.shrink();
                                  }
                                  
                                  final allItems = snapshot.data ?? <Map<String, dynamic>>[];
                                  final tracks = _toTracks(allItems);
                                  AppLogger.d('[Collection] Building track list, items count: ${tracks.length}');
                                  
                                  // Only show snackbar if truly empty after loading
                                  if (tracks.isEmpty && snapshot.connectionState == ConnectionState.done) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('No playable tracks found.')),
                                        );
                                      }
                                    });
                                    return const SizedBox.shrink();
                                  }
                                  
                                  // If still loading or has tracks, show play button
                                  if (tracks.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return _FloatingPlayButton(
                                    tracks: allItems,
                                    onPressed: () async {
                                      try {
                                        final items = await _tracks;
                                        AppLogger.d('[Collection] Building track list, items count: ${items.length}');
                                        final tracks = _toTracks(items);
                                        if (tracks.isEmpty) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('No playable tracks found.')),
                                          );
                                          return;
                                        }
                                        await PlayerService.instance.playQueue(tracks, startIndex: 0);
                                        
                                        // Debug: Print queue info
                                        AppLogger.d('[Collection] Playing queue with ${tracks.length} tracks, starting at index 0');
                                        for (int i = 0; i < tracks.length; i++) {
                                          AppLogger.d('[Collection] Track $i: ${tracks[i].title}');
                                        }
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Play failed: $e')),
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _tracks,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Failed to load tracks: ${snapshot.error}',
                            style: theme.textTheme.bodyMedium?.copyWith(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.85)),
                          ),
                        );
                      }

                      final tracks = snapshot.data ?? const [];
                      if (tracks.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No tracks found.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.75)),
                          ),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: tracks.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)),
                        itemBuilder: (context, index) {
                          final t = tracks[index];
                          final tTitle = _extractTrackTitle(t) ?? 'Track';
                          final tSubtitle = _extractTrackSubtitle(t) ?? '';
                          // Try hash first, then code (both should be 32-char hex), then id as last resort
                          var tHash = (t['hash'] ?? t['code'] ?? t['id'] ?? '').toString();
                          // Validate that it's a proper 32-char hex hash for sharing
                          if (tHash.isNotEmpty && !RegExp(r'^[a-f0-9]{32}$', caseSensitive: false).hasMatch(tHash)) {
                            // If not a valid hash, try to find hash in other fields or skip sharing
                            AppLogger.d('[Collection] Warning: Invalid hash format for track "$tTitle": $tHash');
                            // Don't use invalid hashes for sharing
                            tHash = '';
                          }
                          
                          // Convert to Track object to get the cover (with album fallback)
                          final playableTracks = _toTracks([t]);
                          final metaTrack = playableTracks.isNotEmpty ? playableTracks.first : null;
                          
                          // Use cover from processed Track object (has album fallback)
                          final cover = metaTrack?.coverUrl;
                          
                          AppLogger.d('[Collection] Building track row $index: $tTitle, cover: ${cover != null ? "found" : "null"}');
                          
                          final artistSlug = metaTrack == null ? null : _artistSlugFromTrack(metaTrack);
                          return _SpotifyTrackRow(
                            index: index,
                            title: tTitle,
                            subtitle: tSubtitle,
                            coverUrl: cover,
                            trackHash: tHash.isNotEmpty ? tHash : null,
                            isDark: isDark,
                            onArtistTap: () {
                              if (artistSlug == null || artistSlug.isEmpty) {
                                // ignore: avoid_print
                                debugPrint('[ArtistNav] missing slug. subtitle=$tSubtitle sub_link=${t['sub_link']}');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Artist profile not available for this track.')),
                                );
                                return;
                              }
                              // ignore: avoid_print
                              debugPrint('[ArtistNav] open artist slug=$artistSlug');
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ArtistScreen(artistSlug: artistSlug),
                                ),
                              );
                            },
                            onTap: playableTracks.isEmpty
                                ? null
                                : () async {
                                    AppLogger.d('[Collection] TAP DETECTED on track: $tTitle');
                                    
                                    // Use the already loaded tracks from the FutureBuilder
                                    if (tracks.isEmpty) {
                                      AppLogger.d('[Collection] No tracks found in collection!');
                                      return;
                                    }
                                    
                                    // Find the index of the tapped track in the full queue
                                    int startIndex = 0;
                                    for (int i = 0; i < tracks.length; i++) {
                                      final trackTitle = _extractTrackTitle(tracks[i]) ?? 'Track';
                                      if (trackTitle == tTitle) {
                                        startIndex = i;
                                        break;
                                      }
                                    }
                                    
                                    AppLogger.d('[Collection] Playing full queue: ${tracks.length} tracks, starting at index $startIndex');
                                    final trackList = _toTracks(tracks);
                                    await PlayerService.instance.playQueue(trackList, startIndex: startIndex);
                                  },
                          );
                        },
                      );
                    },
                  ),
                ),
                // Related Tracks Section
                SliverToBoxAdapter(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _relatedTracks,
                    builder: (context, snapshot) {
                      if (kDebugMode) {
                        AppLogger.d('[CollectionScreen] RelatedTracks FutureBuilder - state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, dataLength: ${snapshot.data?.length ?? 0}');
                      }
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const SizedBox.shrink();
                      }
                      
                      final relatedTracks = snapshot.data ?? [];
                      if (kDebugMode) AppLogger.d('[CollectionScreen] RelatedTracks - found ${relatedTracks.length} tracks');
                      
                      if (relatedTracks.isEmpty) {
                        if (kDebugMode) AppLogger.d('[CollectionScreen] RelatedTracks - empty, returning SizedBox.shrink');
                        return const SizedBox.shrink();
                      }
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Related Songs',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: relatedTracks.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                            ),
                            itemBuilder: (context, index) {
                              final t = relatedTracks[index];
                              final tTitle = _extractTrackTitle(t) ?? 'Track';
                              final tSubtitle = _extractTrackSubtitle(t) ?? '';
                              
                              // Try hash first, then code (both should be 32-char hex), then id as last resort
                              var tHash = (t['hash'] ?? t['code'] ?? t['id'] ?? '').toString();
                              // Validate that it's a proper 32-char hex hash for sharing
                              if (tHash.isNotEmpty && !RegExp(r'^[a-f0-9]{32}$', caseSensitive: false).hasMatch(tHash)) {
                                AppLogger.d('[Collection] Warning: Invalid hash format for related track "$tTitle": $tHash');
                                tHash = '';
                              }
                              
                              // Convert to Track object to get the cover (with album fallback)
                              final playableTracks = _toTracks([t]);
                              final metaTrack = playableTracks.isNotEmpty ? playableTracks.first : null;
                              
                              // Use cover from processed Track object (has album fallback)
                              final cover = metaTrack?.coverUrl;
                              
                              final artistSlug = metaTrack == null ? null : _artistSlugFromTrack(metaTrack);
                              return _SpotifyTrackRow(
                                index: index,
                                title: tTitle,
                                subtitle: tSubtitle,
                                coverUrl: cover,
                                trackHash: tHash.isNotEmpty ? tHash : null,
                                isDark: isDark,
                                onArtistTap: () {
                                  if (kDebugMode) AppLogger.d('[Collection] Artist tap - metaTrack: $metaTrack, artistSlug: $artistSlug');
                                  if (artistSlug == null || artistSlug.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Artist profile not available for this track.')),
                                    );
                                    return;
                                  }
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ArtistScreen(artistSlug: artistSlug),
                                    ),
                                  );
                                },
                                onTap: playableTracks.isEmpty
                                    ? null
                                    : () async {
                                        await PlayerService.instance.playQueue(playableTracks, startIndex: 0);
                                      },
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 90)),
              ],
            ),
          ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: MiniPlayer(player: PlayerService.instance),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverArt extends StatelessWidget {
  final String? imageUrl;
  final String? lookupTitle;
  final String? lookupSubtitle;
  final bool isDark;

  const _CoverArt({
    required this.imageUrl,
    required this.isDark,
    this.lookupTitle,
    this.lookupSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    final child = CoverImage(
      imageUrl: imageUrl,
      lookupTitle: lookupTitle,
      lookupSubtitle: lookupSubtitle,
      placeholder: Container(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        child: Icon(Icons.library_music, color: isDark ? Colors.white70 : Colors.black54, size: 46),
      ),
    );

    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            blurRadius: 30,
            spreadRadius: 1,
            color: Colors.black.withValues(alpha: 0.55),
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            blurRadius: 40,
            spreadRadius: 1,
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(18), child: child),
    );
  }
}

class _SpotifyTrackRow extends StatelessWidget {
  final int index;
  final String title;
  final String subtitle;
  final String? coverUrl;
  final String? trackHash;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback? onArtistTap;

  const _SpotifyTrackRow({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    this.trackHash,
    required this.isDark,
    required this.onTap,
    this.onArtistTap,
  });

  void _showTrackOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              ListTile(
                leading: Icon(Icons.share, color: isDark ? Colors.white : Colors.black),
                title: Text('Share', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () {
                  Navigator.of(context).pop();
                  final hash = trackHash ?? '';
                  if (hash.isNotEmpty) {
                    final track = Track(
                      id: hash,
                      title: title,
                      subtitle: subtitle,
                      url: '',
                      coverUrl: coverUrl,
                      objectType: 'm_track',
                      objectHash: hash,
                    );
                    showShareEmbedDialog(
                      context,
                      track: track,
                      objectType: 'm_track',
                      objectHash: hash,
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.queue_music, color: isDark ? Colors.white : Colors.black),
                title: Text('Add to Queue', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added to queue')),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return StreamBuilder<Track?>(
      stream: PlayerService.instance.currentTrackStream,
      builder: (context, snapshot) {
        final currentTrack = snapshot.data;
        final isPlaying = trackHash != null && trackHash!.isNotEmpty && 
                         currentTrack?.id == trackHash;
        
        if (kDebugMode && isPlaying) {
          AppLogger.d('[CollectionScreen] Track is playing: $title (hash: $trackHash)');
        }
        
        return Container(
          decoration: BoxDecoration(
            color: isPlaying ? const Color(0xFF1DB954).withValues(alpha: 0.1) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: isPlaying
                        ? const MusicWaveAnimation(
                            color: Color(0xFF1DB954),
                            height: 16,
                            barCount: 3,
                          )
                        : Text(
                            '${index + 1}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.55),
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                  ),
                  const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 46,
                height: 46,
                child: (coverUrl == null || coverUrl!.isEmpty)
                    ? Container(
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                        child: Icon(Icons.music_note, color: isDark ? Colors.white70 : Colors.black54, size: 20),
                      )
                    : CachedNetworkImage(
                        imageUrl: coverUrl!,
                        fit: BoxFit.cover,
                        maxHeightDiskCache: 640,
                        maxWidthDiskCache: 640,
                        memCacheHeight: 100,
                        memCacheWidth: 100,
                        placeholder: (_, __) => Container(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)),
                        errorWidget: (_, __, ___) => Container(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                          child: Icon(Icons.music_note, color: isDark ? Colors.white70 : Colors.black54, size: 20),
                        ),
                      ),
              ),
            ),  const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: isPlaying ? const Color(0xFF1DB954) : (isDark ? Colors.white : Colors.black),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      onArtistTap != null
                          ? GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onArtistTap,
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isPlaying ? const Color(0xFF1DB954).withValues(alpha: 0.8) : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.75),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isPlaying ? const Color(0xFF1DB954).withValues(alpha: 0.8) : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.65),
                              ),
                            ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _showTrackOptions(context),
                icon: Icon(
                  Icons.more_vert,
                  color: isPlaying ? const Color(0xFF1DB954) : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
      );
      },
    );
  }
}
