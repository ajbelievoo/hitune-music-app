import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'artist_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../collection/collection_screen.dart';
import '../player/models/track.dart';
import '../player/player_screen.dart';
import '../player/player_service.dart';
import '../player/mini_player.dart';
import '../player/widgets/music_wave_animation.dart';

class ArtistScreen extends StatefulWidget {
  final String artistSlug;

  /// Display title of the artist, when known. The backend sometimes ships
  /// related-artist `slug` values with underscores stripped (404), so the
  /// title is used to derive a fallback slug like `pranjal_dahiya`.
  final String? artistTitle;

  const ArtistScreen({super.key, required this.artistSlug, this.artistTitle});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> with SingleTickerProviderStateMixin {
  // Runtime blacklist for failed images to prevent repeated loading attempts
  static final Set<String> _failedImageUrls = <String>{};
  
  late Future<Map<String, dynamic>> _future;
  late TabController _tab;
  bool _following = false;
  String? _artistHash;
  bool _isLoadingFollow = false;
  
  // Search filter state with debouncing
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // Currently playing track stream subscription
  StreamSubscription<Track?>? _currentTrackSub;
  Track? _currentTrack;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _future = _load();
    _currentTrack = PlayerService.instance.currentTrack;
    _currentTrackSub = PlayerService.instance.currentTrackStream.listen((track) {
      if (mounted) {
        setState(() {
          _currentTrack = track;
        });
      }
    });
  }

  @override
  void dispose() {
    _currentTrackSub?.cancel();
    _tab.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// Derives a slug from a display title the way the backend does —
  /// "Pranjal Dahiya" -> `pranjal_dahiya`. Backend `related_artists[].slug`
  /// values arrive with underscores stripped and 404; the title-derived slug
  /// resolves correctly.
  String? _slugFromTitle(String? title) {
    if (title == null) return null;
    final s = title
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? null : s;
  }

  Future<Map<String, dynamic>> _load() async {
    final candidates = <String>[widget.artistSlug];
    final derived = _slugFromTitle(widget.artistTitle);
    if (derived != null && derived != widget.artistSlug) {
      candidates.add(derived);
    }

    Object? lastError;
    for (final slug in candidates) {
      final res = await ArtistService().fetchArtist(slug: slug);
      if (res.isSuccess && res.data != null) {
        // Debug: Print full response to understand structure
        if (kDebugMode) {
          debugPrint('[ArtistScreen] FULL API RESPONSE: ${res.data.toString().substring(0, res.data.toString().length > 2000 ? 2000 : res.data.toString().length)}...');
        }
        return res.data!;
      }
      lastError = res.error?.message ?? 'Failed to load artist';
    }
    throw Exception(lastError);
  }

  // Temporary method to prevent crashes from old timer during hot reload
  void _slideToNextPage() {
    // Auto-sliding functionality removed - this method is kept temporarily
    // to prevent crashes from timers that might still be running from previous hot reloads
  }

  void _syncButtonStates(Map<String, dynamic> data) {
    var resolved = false;
    bool asBool(Object? v) =>
        (v == true) || (v is num && v == 1) || (v is String && v.trim() == '1');
    final buttons = data['buttons'];
    if (buttons is Map) {
      // Backend nests actionable buttons under buttons.items; the follow
      // action is exposed as "subscribe" (and sometimes "follow").
      final items = buttons['items'];
      final container = items is Map ? items : buttons;
      for (final key in ['subscribe', 'follow']) {
        final node = container[key];
        if (node is Map) {
          final active = node['is_active'] ?? node['active'] ?? node['subscribed'];
          if (active != null) {
            _following = asBool(active);
            resolved = true;
            break;
          }
        }
      }
    }
    if (!resolved && data['subscribed'] != null) {
      _following = asBool(data['subscribed']);
    }
    // Extract artist hash for follow API
    _artistHash = data['hash']?.toString() ?? data['ID']?.toString();
  }

  Future<void> _toggleFollow() async {
    if (_artistHash == null || _artistHash!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot follow: artist ID not found')),
      );
      return;
    }
    
    setState(() => _isLoadingFollow = true);
    
    try {
      final newFollowState = !_following;
      final res = await ArtistService().toggleFollow(
        artistHash: _artistHash!,
        follow: newFollowState,
      );
      
      if (res.isSuccess) {
        setState(() => _following = newFollowState);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to ${_following ? 'unfollow' : 'follow'}: ${res.error?.message}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoadingFollow = false);
    }
  }

  String _plainText(dynamic v) {
    var s = (v ?? '').toString();
    if (s.isEmpty) return s;
    s = s.replaceAll('\\/', '/');
    s = s.replaceAll(RegExp(r'<[^>]*>'), '');
    s = s.replaceAll('&nbsp;', ' ');
    s = s.replaceAll('&amp;', '&');
    s = s.replaceAll('&quot;', '"');
    s = s.replaceAll('&#039;', "'");
    s = s.replaceAll('&lt;', '<');
    s = s.replaceAll('&gt;', '>');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  String? _extractBio(Map<String, dynamic> data) {
    // Try multiple possible bio fields
    final bio = data['bio'] ?? data['biography'] ?? data['description'] ?? data['about'] ?? data['summary'];
    if (bio == null) return null;
    final cleaned = _plainText(bio);
    return cleaned.isEmpty ? null : cleaned;
  }

  bool _isVerified(Map<String, dynamic> data) {
    // Check multiple possible field names for verified status
    final v = data['verified'] ?? data['is_verified'] ?? data['verify'] ?? data['verified_badge'] ?? data['has_badge'] ?? data['is_verified_badge'] ?? data['verification'];
    if (v == true) return true;
    if (v is num) return v == 1;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes' || s == 'verified';
    }
    // Check in stats object if available
    final stats = data['stats'];
    if (stats is Map) {
      final sv = stats['verified'] ?? stats['is_verified'] ?? stats['has_badge'];
      if (sv == true) return true;
      if (sv is num) return sv == 1;
      if (sv is String) {
        final s = sv.trim().toLowerCase();
        return s == '1' || s == 'true' || s == 'yes' || s == 'verified';
      }
    }
    // Check buttons for verified badge
    final buttons = data['buttons'];
    if (buttons is Map) {
      final items = buttons['items'];
      if (items is Map) {
        final verified = items['verified'] ?? items['verify'] ?? items['badge'];
        if (verified == true) return true;
        if (verified is String && verified.toLowerCase() == 'true') return true;
      }
    }

    // Some responses embed verified badge in HTML title e.g.
    // "Name<span class=\"mdi mdi-check-decagram verified\"></span>"
    final titleRaw = (data['title'] ?? data['name'] ?? '').toString();
    final title = titleRaw.toLowerCase();
    if (title.contains('verified') || title.contains('check-decagram')) return true;
    final titleText = _plainText(titleRaw).toLowerCase();
    if (titleText.contains('verified')) return true;
    return false;
  }

  String? _artistSlugFromItem(Map<String, dynamic> item) {
    final direct = (item['slug'] ?? item['artist_slug'])?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    final link = (item['sub_link'] ?? item['link'] ?? item['url'])?.toString().trim() ?? '';
    if (link.isNotEmpty) {
      final cleaned = link.startsWith('/') ? link.substring(1) : link;
      final m = RegExp(r'^music/artist/([^/?#]+)', caseSensitive: false).firstMatch(cleaned);
      final slug = m?.group(1);
      if (slug != null && slug.isNotEmpty) return slug;
    }
    return null;
  }

  String? _extractTextFromHtml(String? html) {
    if (html == null) return null;
    final s = _plainText(html);
    return s.isEmpty ? null : s;
  }

  String? _extractTrackTitle(Map<String, dynamic> t) {
    final title = _extractTextFromHtml(t['title']?.toString());
    if (title != null) return title;
    final raw = t['raw'];
    if (raw is Map && raw['title'] != null) {
      return _extractTextFromHtml(raw['title']?.toString());
    }
    
    // Handle table data structure (tds) format from API
    final tds = t['tds'];
    if (tds is List) {
      for (final cell in tds) {
        if (cell is! Map) continue;
        final cls = (cell['class'] ?? '').toString();
        final val = cell['val'];
        if (cls.contains('title') && val != null) {
          return _extractTextFromHtml(val.toString());
        }
      }
    }
    
    // Fallback to direct fields
    final directTitle = t['name'] ?? t['track_name'] ?? t['song_name'];
    if (directTitle != null) {
      return _extractTextFromHtml(directTitle.toString());
    }
    
    return null;
  }

  String? _extractTrackSubtitle(Map<String, dynamic> t) {
    final sub = _extractTextFromHtml(t['sub_title']?.toString());
    if (sub != null) return sub;
    final raw = t['raw'];
    if (raw is Map && raw['sub_title'] != null) {
      return _extractTextFromHtml(raw['sub_title']?.toString());
    }
    
    // Handle table data structure (tds) format from API
    final tds = t['tds'];
    if (tds is List) {
      for (final cell in tds) {
        if (cell is! Map) continue;
        final cls = (cell['class'] ?? '').toString();
        final val = cell['val'];
        if (cls.contains('sub_title') && val != null) {
          return _extractTextFromHtml(val.toString());
        }
      }
    }
    
    // Fallback to direct fields
    final directSub = t['artist'] ?? t['artist_name'] ?? t['subtitle'] ?? t['sub_data'];
    if (directSub != null) {
      return _extractTextFromHtml(directSub.toString());
    }
    
    return null;
  }

  String? _extractCoverUrl(Map<String, dynamic> t) {
    return CoverImageExtractor.extract(t);
  }

  List<Map<String, dynamic>> _widgetItems(Map<String, dynamic> w) {
    List<Map<String, dynamic>> normalize(Object? items) {
      if (items is List) {
        return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      // Backend often sends items as a page map: {"1": [...], "2": [...]}
      if (items is Map) {
        final out = <Map<String, dynamic>>[];
        for (final v in items.values) {
          if (v is List) {
            out.addAll(v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
          } else if (v is Map) {
            out.add(Map<String, dynamic>.from(v));
          }
        }
        return out;
      }
      return const [];
    }

    // Try direct 'items' first (most common)
    final directItems = normalize(w['items']);
    if (directItems.isNotEmpty) return directItems;

    // Try payload nesting
    final payload = w['payload'];
    if (payload is Map) {
      final p = Map<String, dynamic>.from(payload);
      final fromPayload = normalize(p['items']);
      if (fromPayload.isNotEmpty) return fromPayload;
      final fromList = normalize(p['list']);
      if (fromList.isNotEmpty) return fromList;
      final data = p['data'];
      if (data is Map) {
        final d = Map<String, dynamic>.from(data);
        final fromData = normalize(d['items']);
        if (fromData.isNotEmpty) return fromData;
        final fromDataList = normalize(d['list']);
        if (fromDataList.isNotEmpty) return fromDataList;
      }
    }
    
    // Try display nesting (common in bof responses)
    final display = w['display'];
    if (display is Map) {
      final d = Map<String, dynamic>.from(display);
      final fromDisplay = normalize(d['items']);
      if (fromDisplay.isNotEmpty) return fromDisplay;
    }

    return const [];
  }

  Map<String, dynamic>? _findWidget(Map<String, dynamic> data, List<String> types, List<String> names) {
    // First, try direct field matching for common patterns
    for (final key in data.keys) {
      final keyLower = key.toLowerCase();
      final matchesType = types.any((t) => keyLower.contains(t.toLowerCase()));
      final matchesName = names.any((n) => keyLower.contains(n.toLowerCase()));
      
      if (matchesType || matchesName) {
        final value = data[key];
        if (value is List && value.isNotEmpty) {
          return <String, dynamic>{'items': value, '_source': key};
        } else if (value is Map) {
          return Map<String, dynamic>.from(value);
        }
      }
    }
    
    // Try common direct field names for artist data
    final directFieldMap = {
      ['m_track_list', 'track_list', 'tracks', 'popular']: ['tracks', 'track_list', 'popular_tracks', 'top_tracks', 'm_tracks'],
      ['m_album_grid', 'album_grid', 'm_album', 'albums']: ['albums', 'album_list', 'discography', 'm_albums'],
      ['m_artist_grid', 'artist_grid', 'm_artist', 'related', 'similar']: ['related_artists', 'similar_artists', 'related', 'artists', 'm_artists'],
    };
    
    for (final entry in directFieldMap.entries) {
      final typeMatches = entry.key.any((t) => types.any((type) => t.toLowerCase().contains(type.toLowerCase()) || type.toLowerCase().contains(t.toLowerCase())));
      if (typeMatches) {
        for (final fieldName in entry.value) {
          if (data.containsKey(fieldName)) {
            final value = data[fieldName];
            if (value is List && value.isNotEmpty) {
              return <String, dynamic>{'items': value, '_source': fieldName};
            } else if (value is Map) {
              return Map<String, dynamic>.from(value);
            }
          }
        }
      }
    }
    
    // Fall back to widget-based lookup
    Object? widgetsNode = data['widgets'];
    
    if (widgetsNode is! List) {
      final payload = data['payload'];
      if (payload is Map) {
        final p = Map<String, dynamic>.from(payload);
        widgetsNode = p['widgets'] ?? (p['data'] is Map ? (p['data'] as Map)['widgets'] : null);
      }
    }
    
    if (widgetsNode is! List) {
      final innerData = data['data'];
      if (innerData is Map) {
        widgetsNode = innerData['widgets'];
      }
    }
    
    if (widgetsNode is! List) return null;

    final typeNeedles = types.map((e) => e.toLowerCase()).toList();
    final nameNeedles = names.map((e) => e.toLowerCase()).toList();

    for (final w in widgetsNode) {
      if (w is! Map) continue;
      final m = Map<String, dynamic>.from(w);
      final t = (m['widget_type'] ?? m['type'] ?? m['display']?['type'] ?? '').toString().toLowerCase();
      final n = _plainText(m['widget_name'] ?? m['name'] ?? m['title'] ?? m['display']?['title']).toLowerCase();
      
      if (typeNeedles.contains(t)) return m;
      if (nameNeedles.contains(n)) return m;
      if (typeNeedles.any((e) => t.contains(e))) return m;
      if (nameNeedles.any((e) => n.contains(e))) return m;
    }
    return null;
  }

  Future<void> _playArtistTracks(List<Map<String, dynamic>> rawItems, {int startIndex = 0, Map<String, dynamic>? artistData}) async {
    // Always play full queue for proper auto-advance
    // Backend sends artist tracks with cover:null/sub_title:null — fall back
    // to the artist's own image and name.
    final fallbackCover = artistData == null ? null : _pickImage(artistData);
    final fallbackSubtitle = artistData == null ? null : _plainText(artistData['name'] ?? artistData['title']);
    final tracks = <Track>[];
    for (final it in rawItems) {
      final objectType = (it['object_type'] ?? it['type'] ?? it['objectType'])?.toString();
      final objectHash = (it['hash'] ?? it['object_hash'] ?? it['objectHash'])?.toString();
      final title = _extractTrackTitle(it) ?? 'Track';
      final subtitle = _extractTrackSubtitle(it) ?? fallbackSubtitle ?? '';
      final cover = _extractCoverUrl(it) ?? fallbackCover;
      final url = (it['url'] ?? it['play'] ?? it['web_address'] ?? '').toString();

      if (objectHash == null || objectHash.isEmpty) continue;
      tracks.add(
        Track(
          id: objectHash,
          title: title,
          subtitle: subtitle,
          url: url,
          coverUrl: cover,
          objectType: objectType ?? 'm_track',
          objectHash: objectHash,
          aiPct: Track.aiPctFromJson(it),
        ),
      );
    }
    if (tracks.isEmpty) return;
    // Play full queue with proper auto-advance
    await PlayerService.instance.playQueue(tracks, startIndex: startIndex);
  }

  Widget _sectionTitle(String t) {
    return Text(
      t,
      style: TextStyle(color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.95), fontSize: 18, fontWeight: FontWeight.w900),
    );
  }

  Widget _buildPopular(Map<String, dynamic> data) {
    final w = _findWidget(data, ['m_track_list', 'track_list'], ['popular', 'popular tracks', 'tracks']);
    final items = w == null ? const <Map<String, dynamic>>[] : _widgetItems(w);
    if (items.isEmpty) {
      return Text('No tracks', style: TextStyle(color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.65)));
    }
    // Track items carry cover:null — use the artist image as fallback.
    final fallbackCover = _pickImage(data);
    final fallbackSubtitle = _plainText(data['name'] ?? data['title']);
    // Use ListView.builder for lazy loading to prevent BLASTBufferQueue errors
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, i) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: () {
                final cover = _extractCoverUrl(items[i]) ?? fallbackCover;
                if (cover == null || cover.isEmpty) {
                  return Container(
                    color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                    child: Icon(Icons.music_note, color: _isDark ? Colors.white70 : Colors.black54),
                  );
                }
                // Check if URL is in blacklist before attempting to load
                if (_failedImageUrls.contains(cover)) {
                  return Container(
                    color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                    child: Icon(Icons.music_note, color: _isDark ? Colors.white70 : Colors.black54),
                  );
                }
                return CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  maxHeightDiskCache: 640,
                  maxWidthDiskCache: 640,
                  memCacheHeight: 100,
                  memCacheWidth: 100,
                  placeholder: (_, __) => Container(color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
                  errorWidget: (_, __, ___) {
                    // Add URL to blacklist when it fails to load
                    if (cover != null && cover.isNotEmpty) {
                      _failedImageUrls.add(cover);
                    }
                    return Container(
                      color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                      child: Icon(Icons.music_note, color: _isDark ? Colors.white70 : Colors.black54),
                    );
                  },
                );
              }(),
            ),
          ),
          title: Text(
            _extractTrackTitle(items[i]) ?? 'Track',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            _extractTrackSubtitle(items[i]) ?? fallbackSubtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.65)),
          ),
          trailing: Text(
            _plainText(items[i]['duration'] ?? '').trim(),
            style: TextStyle(color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.55), fontWeight: FontWeight.w700, fontSize: 12),
          ),
          onTap: () => _playArtistTracks(items, startIndex: i, artistData: data),
        );
      },
    );
  }

  Widget _buildAlbums(Map<String, dynamic> data) {
    final w = _findWidget(data, ['m_album_grid', 'album_grid', 'm_album'], ['albums']);
    final items = w == null ? const <Map<String, dynamic>>[] : _widgetItems(w);
    if (items.isEmpty) {
      return Text('No albums', style: TextStyle(color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.65)));
    }
    // Limit max items to prevent BLASTBufferQueue overload
    final displayItems = items.take(10).toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: displayItems.length,
      itemBuilder: (context, i) {
        final it = displayItems[i];
        final title = _plainText(it['title'] ?? it['name']);
        final sub = _plainText(it['sub_title'] ?? it['subtitle']);
        final cover = _extractCoverUrl(it);
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CollectionScreen(item: it),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: cover == null || cover.isEmpty
                        ? Container(
                            color: Colors.white.withValues(alpha: 0.08),
                            child: const Icon(Icons.album, color: Colors.white70),
                          )
                        : Builder(builder: (context) {
                            if (_failedImageUrls.contains(cover)) {
                              return Container(
                                color: Colors.white.withValues(alpha: 0.08),
                                child: const Icon(Icons.album, color: Colors.white70),
                              );
                            }
                            return CachedNetworkImage(
                              imageUrl: cover!,
                              fit: BoxFit.cover,
                              maxHeightDiskCache: 640,
                              maxWidthDiskCache: 640,
                              memCacheHeight: 200,
                              memCacheWidth: 200,
                              placeholder: (_, __) => Container(color: Colors.white.withValues(alpha: 0.08)),
                              errorWidget: (_, __, ___) {
                                if (cover != null && cover.isNotEmpty) {
                                  _failedImageUrls.add(cover);
                                }
                                return Container(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  child: const Icon(Icons.album, color: Colors.white70),
                                );
                              },
                            );
                          }),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title.isEmpty ? 'Album' : title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w600, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRelatedArtists(Map<String, dynamic> data) {
    final w = _findWidget(data, ['m_artist_grid', 'artist_grid', 'm_artist'], ['related', 'related artists']);
    final items = w == null ? const <Map<String, dynamic>>[] : _widgetItems(w);
    if (items.isEmpty) {
      return Text('No related artists', style: TextStyle(color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.65)));
    }
    // Limit max items to prevent BLASTBufferQueue overload
    final displayItems = items.take(10).toList();
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: displayItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final it = displayItems[i];
          final title = _plainText(it['title'] ?? it['name']);
          final cover = _extractCoverUrl(it);
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              final slug = _artistSlugFromItem(it);
              if (slug == null || slug.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Artist link not available')),
                );
                return;
              }
              // Validate slug format to prevent 404 errors
              if (slug.contains(' ') || slug.contains('&') || slug.contains(':')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid artist link')),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ArtistScreen(artistSlug: slug, artistTitle: title),
                ),
              );
            },
            child: SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 140,
                      height: 140,
                      child: cover == null || cover.isEmpty
                        ? Container(
                            color: Colors.white.withValues(alpha: 0.08),
                            child: const Icon(Icons.person, color: Colors.white70),
                          )
                        : Builder(builder: (context) {
                            if (_failedImageUrls.contains(cover)) {
                              return Container(
                                color: Colors.white.withValues(alpha: 0.08),
                                child: const Icon(Icons.person, color: Colors.white70),
                              );
                            }
                            return CachedNetworkImage(
                              imageUrl: cover!,
                              fit: BoxFit.cover,
                              maxHeightDiskCache: 640,
                              maxWidthDiskCache: 640,
                              memCacheHeight: 140,
                              memCacheWidth: 140,
                              placeholder: (_, __) => Container(color: Colors.white.withValues(alpha: 0.08)),
                              errorWidget: (_, __, ___) {
                                if (cover != null && cover.isNotEmpty) {
                                  _failedImageUrls.add(cover);
                                }
                                return Container(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  child: const Icon(Icons.person, color: Colors.white70),
                                );
                              },
                            );
                          }),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title.isEmpty ? 'Artist' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPopularSliver(Map<String, dynamic> data) {
    final w = _findWidget(data, ['m_track_list', 'track_list'], ['popular', 'popular tracks', 'tracks']);
    var items = w == null ? const <Map<String, dynamic>>[] : _widgetItems(w);
    
    // Apply search filter if query exists
    if (_searchQuery.isNotEmpty) {
      items = items.where((item) {
        final title = _extractTrackTitle(item)?.toLowerCase() ?? '';
        final subtitle = _extractTrackSubtitle(item)?.toLowerCase() ?? '';
        return title.contains(_searchQuery) || subtitle.contains(_searchQuery);
      }).toList();
    }
    
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Center(
            child: Text(
              _searchQuery.isEmpty ? 'No tracks found' : 'No songs match your search',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
            ),
          ),
        ),
      );
    }
    // Track items carry cover:null — use the artist image as fallback.
    final fallbackCover = _pickImage(data);
    final fallbackSubtitle = _plainText(data['name'] ?? data['title']);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            if (i >= items.length) return null;
            final item = items[i];
            final objectHash = (item['hash'] ?? item['object_hash'] ?? item['objectHash'])?.toString();
            final trackTitle = _extractTrackTitle(item);
            
            return StreamBuilder<Track?>(
              stream: PlayerService.instance.currentTrackStream,
              builder: (context, trackSnapshot) {
                final currentTrack = trackSnapshot.data;
                
                // Better matching: check both ID and title
                final isPlaying = currentTrack != null && objectHash != null && (
                  currentTrack.id == objectHash || 
                  (currentTrack.title == trackTitle && trackTitle != null)
                );
                
                return Container(
                  decoration: BoxDecoration(
                    color: isPlaying ? const Color(0xFF1DB954).withValues(alpha: 0.15) : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: () {
                      final cover = _extractCoverUrl(item) ?? fallbackCover;
                      if (kDebugMode && i == 0 && (cover == null || cover.isEmpty)) {
                        // ignore: avoid_print
                        AppLogger.d('[ArtistScreen] cover missing for first track. keys=${item.keys.toList()} display=${item['display'] is Map} tds=${item['tds'] is List}');
                      }
                      if (cover == null || cover.isEmpty) {
                        return Container(
                          color: Colors.white.withValues(alpha: 0.08),
                          child: const Icon(Icons.music_note, color: Colors.white70),
                        );
                      }
                      return Builder(builder: (context) {
                        if (_failedImageUrls.contains(cover)) {
                          return Container(
                            color: Colors.white.withValues(alpha: 0.08),
                            child: const Icon(Icons.music_note, color: Colors.white70),
                          );
                        }
                        return CachedNetworkImage(
                          imageUrl: cover!,
                          fit: BoxFit.cover,
                          maxHeightDiskCache: 640,
                          maxWidthDiskCache: 640,
                          memCacheHeight: 100,
                          memCacheWidth: 100,
                          placeholder: (_, __) => Container(color: Colors.white.withValues(alpha: 0.08)),
                          errorWidget: (_, __, ___) {
                            if (cover != null && cover.isNotEmpty) {
                              _failedImageUrls.add(cover);
                            }
                            return Container(
                              color: Colors.white.withValues(alpha: 0.08),
                              child: const Icon(Icons.music_note, color: Colors.white70),
                            );
                          },
                        );
                      });
                    }(),
                  ),
                ),
                title: Text(
                  _extractTrackTitle(item) ?? 'Track',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPlaying ? const Color(0xFF1DB954) : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  _extractTrackSubtitle(item) ?? fallbackSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                ),
                trailing: Row(
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
                    Text(
                      _plainText(item['duration'] ?? '').trim(),
                      style: TextStyle(
                        color: isPlaying ? const Color(0xFF1DB954) : Colors.white.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.more_vert,
                        color: isPlaying ? const Color(0xFF1DB954) : Colors.white.withValues(alpha: 0.7),
                      ),
                      onPressed: () {
                        _showTrackOptions(item, data);
                      },
                    ),
                  ],
                ),
                onTap: () => _playArtistTracks(items, startIndex: i, artistData: data),
              ),
            );
          },
        );
      },
      childCount: items.length,
    ),
  ),
);
}

Widget _buildLatestTracksSliver(Map<String, dynamic> data) {
    final isDark = _isDark;
    // Look for latest tracks in different possible fields
    final w = _findWidget(data, ['m_track_list', 'track_list'], ['latest', 'new', 'recent', 'latest_tracks', 'new_releases']);
    var items = w == null ? const <Map<String, dynamic>>[] : _widgetItems(w);
    
    // If no latest tracks found, try to get from popular tracks but show as latest
    if (items.isEmpty) {
      final popularW = _findWidget(data, ['m_track_list', 'track_list'], ['popular', 'popular tracks', 'tracks']);
      items = popularW == null ? const <Map<String, dynamic>>[] : _widgetItems(popularW);
    }
    
    // Apply search filter if query exists
    if (_searchQuery.isNotEmpty) {
      items = items.where((item) {
        final title = _extractTrackTitle(item)?.toLowerCase() ?? '';
        final subtitle = _extractTrackSubtitle(item)?.toLowerCase() ?? '';
        return title.contains(_searchQuery) || subtitle.contains(_searchQuery);
      }).toList();
    }
    
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Center(
            child: Text(
              _searchQuery.isEmpty ? 'No latest tracks found' : 'No songs match your search',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
            ),
          ),
        ),
      );
    }
    // Track items carry cover:null — use the artist image as fallback.
    final fallbackCover = _pickImage(data);
    final fallbackSubtitle = _plainText(data['name'] ?? data['title']);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            if (i >= items.length) return null;
            final item = items[i];
            final objectHash = (item['hash'] ?? item['object_hash'] ?? item['objectHash'])?.toString();
            final trackTitle = _extractTrackTitle(item);
            
            // Better matching: check both ID and title
            final isPlaying = _currentTrack != null && objectHash != null && (
              _currentTrack!.id == objectHash || 
              (_currentTrack!.title == trackTitle && trackTitle != null)
            );
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isPlaying
                    ? const Color(0xFF1DB954).withValues(alpha: 0.15)
                    : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isPlaying
                      ? const Color(0xFF1DB954).withValues(alpha: 0.3)
                      : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: () {
                      final cover = _extractCoverUrl(item) ?? fallbackCover;
                      if (cover == null || cover.isEmpty) {
                        return Container(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                          child: Icon(Icons.music_note, color: isDark ? Colors.white70 : Colors.black54),
                        );
                      }
                      return Builder(builder: (context) {
                        if (_failedImageUrls.contains(cover)) {
                          return Container(
                            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                            child: Icon(Icons.music_note, color: isDark ? Colors.white70 : Colors.black54),
                          );
                        }
                        return CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          maxHeightDiskCache: 640,
                          maxWidthDiskCache: 640,
                          memCacheHeight: 100,
                          memCacheWidth: 100,
                          placeholder: (_, __) => Container(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
                          errorWidget: (_, __, ___) {
                            if (cover.isNotEmpty) {
                              _failedImageUrls.add(cover);
                            }
                            return Container(
                              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                              child: Icon(Icons.music_note, color: isDark ? Colors.white70 : Colors.black54),
                            );
                          },
                        );
                      });
                    }(),
                  ),
                ),
                title: Text(
                  _extractTrackTitle(item) ?? 'Track',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPlaying ? const Color(0xFF1DB954) : (isDark ? Colors.white : Colors.black),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  _extractTrackSubtitle(item) ?? fallbackSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPlaying
                        ? const Color(0xFF1DB954).withValues(alpha: 0.8)
                        : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ),
                trailing: Row(
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPlaying
                            ? const Color(0xFF1DB954).withValues(alpha: 0.2)
                            : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _plainText(item['duration'] ?? '').trim(),
                        style: TextStyle(
                          color: isPlaying ? const Color(0xFF1DB954) : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.8),
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.more_vert,
                        color: isPlaying ? const Color(0xFF1DB954) : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7),
                      ),
                      onPressed: () {
                        _showTrackOptions(item, data);
                      },
                    ),
                  ],
                ),
                onTap: () => _playArtistTracks(items, startIndex: i, artistData: data),
              ),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildAlbumsSliver(Map<String, dynamic> data) {
    final w = _findWidget(data, ['m_album_grid', 'album_grid', 'm_album'], ['albums']);
    final items = w == null ? const <Map<String, dynamic>>[] : _widgetItems(w);
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.75,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            if (i >= items.length) return null;
            final it = items[i];
            final title = _plainText(it['title'] ?? it['name']);
            final sub = _plainText(it['sub_title'] ?? it['subtitle']);
            final cover = _extractCoverUrl(it);
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CollectionScreen(item: it),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      child: SizedBox(
                        height: 140,
                        width: double.infinity,
                        child: cover == null || cover.isEmpty
                            ? Container(
                                color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                                child: Icon(Icons.album, color: _isDark ? Colors.white70 : Colors.black54),
                              )
                            : Builder(builder: (context) {
                                if (_failedImageUrls.contains(cover)) {
                                  return Container(
                                    color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                                    child: Icon(Icons.album, color: _isDark ? Colors.white70 : Colors.black54),
                                  );
                                }
                                return CachedNetworkImage(
                                  imageUrl: cover!,
                                  fit: BoxFit.cover,
                                  maxHeightDiskCache: 640,
                                  maxWidthDiskCache: 640,
                                  memCacheHeight: 200,
                                  memCacheWidth: 200,
                                  placeholder: (_, __) => Container(color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
                                  errorWidget: (_, __, ___) {
                                    if (cover != null && cover.isNotEmpty) {
                                      _failedImageUrls.add(cover);
                                    }
                                    return Container(
                                      color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                                      child: Icon(Icons.album, color: _isDark ? Colors.white70 : Colors.black54),
                                    );
                                  },
                                );
                              }),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title.isEmpty ? 'Album' : title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: _isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                            if (sub.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.6), fontWeight: FontWeight.w600, fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildRelatedArtistsSliver(Map<String, dynamic> data) {
    final w = _findWidget(data, ['m_artist_grid', 'artist_grid', 'm_artist'], ['related', 'related artists']);
    final items = w == null ? const <Map<String, dynamic>>[] : _widgetItems(w);
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 190,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final it = items[i];
            final title = _plainText(it['title'] ?? it['name']);
            final cover = _extractCoverUrl(it);
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                final slug = _artistSlugFromItem(it);
                if (slug == null || slug.isEmpty) return;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ArtistScreen(artistSlug: slug, artistTitle: title),
                  ),
                );
              },
              child: SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 140,
                        height: 140,
                        child: cover == null || cover.isEmpty
                            ? Container(
                                color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                                child: Icon(Icons.person, color: _isDark ? Colors.white70 : Colors.black54),
                              )
                            : Builder(builder: (context) {
                                if (_failedImageUrls.contains(cover)) {
                                  return Container(
                                    color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                                    child: Icon(Icons.person, color: _isDark ? Colors.white70 : Colors.black54),
                                  );
                                }
                                return CachedNetworkImage(
                                  imageUrl: cover!,
                                  fit: BoxFit.cover,
                                  maxHeightDiskCache: 640,
                                  maxWidthDiskCache: 640,
                                  memCacheHeight: 140,
                                  memCacheWidth: 140,
                                  placeholder: (_, __) => Container(color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
                                  errorWidget: (_, __, ___) {
                                    if (cover != null && cover.isNotEmpty) {
                                      _failedImageUrls.add(cover);
                                    }
                                    return Container(
                                      color: (_isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                                      child: Icon(Icons.person, color: _isDark ? Colors.white70 : Colors.black54),
                                    );
                                  },
                                );
                              }),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title.isEmpty ? 'Artist' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String? _pickImage(Map<String, dynamic> data) {
    // CoverImageExtractor handles HTML <picture>/<source srcset>/<img>,
    // relative /files/... paths, cover_url, background, back, thumb, etc.
    final img = CoverImageExtractor.extract(data);
    if (kDebugMode) {
      debugPrint('[ArtistScreen] header image: ${img ?? 'none'}');
    }
    return img;
  }

  Widget _buildHeader(Map<String, dynamic> data) {
    final isDark = _isDark;
    final name = _plainText(data['name'] ?? data['title']);
    final stats = data['stats'];
    // stats arrives as a Map when authed and as a List of {icon,value}
    // chips for guests — handle both so counts don't collapse to zero.
    var followers = '';
    if (stats is Map) {
      followers = _plainText(stats['followers'] ?? stats['subs'] ?? stats['subscribers']);
    } else if (stats is List) {
      for (final e in stats) {
        if (e is! Map) continue;
        final v = _plainText(e['value']);
        final icon = (e['icon'] ?? '').toString().toLowerCase();
        final vl = v.toLowerCase();
        if (icon.contains('account') || icon.contains('user') || icon.contains('group') ||
            vl.contains('follower') || vl.contains('subscriber')) {
          final m = RegExp(r'([\d.,]+\s*[KMBkmb]?)').firstMatch(v);
          followers = (m != null ? m.group(0)! : v).trim();
          break;
        }
      }
    }
    final monthly = _plainText(data['monthly_listeners'] ?? data['listeners'] ?? data['s_subscribers']);
    // Single stats line keeps the header inside its fixed 250px height.
    final statsLine = [
      if (monthly.isNotEmpty) '$monthly monthly listeners',
      if (followers.isNotEmpty) '$followers followers',
    ].join('  ·  ');
    final img = _pickImage(data);
    final verified = _isVerified(data);

    final onHeader = isDark ? Colors.white : Colors.black;
    final onHeaderMuted = onHeader.withValues(alpha: 0.75);
    final headerOverlayStart = isDark ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.05);
    final headerOverlayEnd = isDark ? Colors.black.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.90);
    final chipBg = onHeader.withValues(alpha: 0.12);
    final chipBorder = onHeader.withValues(alpha: 0.18);

    return SizedBox(
      height: 250,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (img != null && img.isNotEmpty)
            Builder(builder: (context) {
              if (_failedImageUrls.contains(img)) {
                return const SizedBox.shrink();
              }
              return CachedNetworkImage(
                imageUrl: img,
                fit: BoxFit.cover,
                maxHeightDiskCache: 1600,
                maxWidthDiskCache: 1600,
                placeholder: (_, __) => Container(color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.3)),
                errorWidget: (_, __, ___) {
                  if (img != null && img.isNotEmpty) {
                    _failedImageUrls.add(img);
                  }
                  return const SizedBox.shrink();
                },
              );
            })
          else
            Container(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  headerOverlayStart,
                  headerOverlayEnd,
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            top: 0,
            // Bounded viewport: when the info column is taller than the
            // header, the top is clipped instead of throwing a RenderFlex
            // overflow (the ~42px striped banner).
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              reverse: true,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        name.isEmpty ? widget.artistSlug : name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: onHeader, fontSize: 34, fontWeight: FontWeight.w900, height: 1.05),
                      ),
                    ),
                    if (verified) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: chipBorder),
                        ),
                        child: Icon(Icons.verified_rounded, color: onHeader, size: 18),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (statsLine.isNotEmpty)
                  Text(
                    statsLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: onHeaderMuted, fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 12),
                // Controls row can exceed narrow widths — allow horizontal
                // scroll instead of a right-edge overflow stripe.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: _isLoadingFollow ? null : _toggleFollow,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: onHeader,
                        side: BorderSide(color: onHeader.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      child: _isLoadingFollow
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_following ? 'Subscribed' : 'Subscribe'),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: () async {
                        await PlayerService.instance.previous();
                      },
                      icon: Icon(Icons.skip_previous, color: onHeader.withValues(alpha: 0.9)),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: () async {
                        await PlayerService.instance.next();
                      },
                      icon: Icon(Icons.skip_next, color: onHeader.withValues(alpha: 0.9)),
                    ),
                    const SizedBox(width: 10),
                    _buildPlayNextButton(data),
                    const SizedBox(width: 10),
                    // Shuffle toggle (Spotify-style) — green when enabled.
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
                                : onHeader.withValues(alpha: 0.9),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: StreamBuilder<PlayerState>(
                        stream: PlayerService.instance.audioPlayer.playerStateStream,
                        builder: (context, playerStateSnapshot) {
                          final playerState = playerStateSnapshot.data;
                          final isPlayingAudio = playerState?.playing ?? false;
                          
                          return StreamBuilder<Track?>(
                            stream: PlayerService.instance.currentTrackStream,
                            builder: (context, trackSnapshot) {
                              final currentTrack = trackSnapshot.data;
                              
                              // Check if current playing track belongs to this artist
                              final w = _findWidget(data, ['m_track_list', 'track_list'], ['popular', 'popular tracks', 'tracks']);
                              final items = w == null ? const <Map<String, dynamic>>[] : _widgetItems(w);
                              
                              // Also check latest tracks
                              final latestW = _findWidget(data, ['m_track_list', 'track_list'], ['latest', 'new', 'recent', 'latest_tracks']);
                              final latestItems = latestW == null ? const <Map<String, dynamic>>[] : _widgetItems(latestW);
                              
                              final allTrackHashes = [
                                ...items.map((i) => (i['hash'] ?? i['object_hash'] ?? '').toString()).where((h) => h.isNotEmpty),
                                ...latestItems.map((i) => (i['hash'] ?? i['object_hash'] ?? '').toString()).where((h) => h.isNotEmpty),
                              ];
                              
                              final isPlayingThisArtist = currentTrack != null && 
                                                          allTrackHashes.contains(currentTrack.id);
                              
                              final showPauseIcon = isPlayingThisArtist && isPlayingAudio;
                              
                              return ElevatedButton(
                                onPressed: () async {
                                  if (isPlayingThisArtist) {
                                    // Toggle play/pause for this artist's track
                                    if (isPlayingAudio) {
                                      await PlayerService.instance.audioPlayer.pause();
                                    } else {
                                      await PlayerService.instance.audioPlayer.play();
                                    }
                                  } else {
                                    // Start playing this artist's tracks
                                    if (items.isNotEmpty) {
                                      await _playArtistTracks(items, startIndex: 0, artistData: data);
                                    } else if (latestItems.isNotEmpty) {
                                      await _playArtistTracks(latestItems, startIndex: 0, artistData: data);
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1DB954),
                                  foregroundColor: Colors.black,
                                  shape: const CircleBorder(),
                                  padding: EdgeInsets.zero,
                                ),
                                child: Icon(
                                  showPauseIcon ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  size: 34,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                  ),
                ),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayNextButton(Map<String, dynamic> data) {
    return IconButton(
      onPressed: () async {
        debugPrint('[ARTIST] Play Next button pressed');
        try {
          // Get popular tracks and add to queue
          final w = _findWidget(data, ['m_track_list', 'track_list'], ['popular', 'popular tracks', 'tracks']);
          final items = w == null ? const <Map<String, dynamic>>[] : _widgetItems(w);
          debugPrint('[ARTIST] Found ${items.length} tracks to add');
          
          if (items.isNotEmpty) {
            final fallbackCover = _pickImage(data);
            final fallbackSubtitle = _plainText(data['name'] ?? data['title']);
            final tracks = <Track>[];
            for (final it in items) {
              final objectType = (it['object_type'] ?? it['type'] ?? it['objectType'])?.toString();
              final objectHash = (it['hash'] ?? it['object_hash'] ?? it['objectHash'])?.toString();
              final title = _extractTrackTitle(it) ?? 'Track';
              final subtitle = _extractTrackSubtitle(it) ?? fallbackSubtitle;
              final cover = _extractCoverUrl(it) ?? fallbackCover;
              final url = (it['url'] ?? it['play'] ?? it['web_address'] ?? '').toString();

              if (objectHash == null || objectHash.isEmpty) continue;
              tracks.add(
                Track(
                  id: objectHash,
                  title: title,
                  subtitle: subtitle,
                  url: url,
                  coverUrl: cover,
                  objectType: objectType ?? 'm_track',
                  objectHash: objectHash,
                  aiPct: Track.aiPctFromJson(it),
                ),
              );
            }
            if (tracks.isNotEmpty) {
              // Add tracks to current queue
              final currentQueue = PlayerService.instance.queue;
              final currentIndex = PlayerService.instance.index;
              final newQueue = [...currentQueue];
              newQueue.insertAll(currentIndex + 1, tracks);
              debugPrint('[ARTIST] Adding ${tracks.length} tracks to queue');
              await PlayerService.instance.playQueue(newQueue, startIndex: currentIndex);
              debugPrint('[ARTIST] Tracks added successfully');
            }
          }
        } catch (e) {
          debugPrint('[ARTIST] Error in Play Next: $e');
        }
      },
      icon: const Icon(Icons.playlist_add, color: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        title: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasData) {
              final data = snap.data!;
              final name = _plainText(data['name'] ?? data['title']);
              return Text(
                name.isEmpty ? widget.artistSlug : name,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (snap.hasError) {
              return Center(
                child: Text(
                  snap.error.toString(),
                  style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.8)),
                ),
              );
            }

            final data = snap.data ?? const <String, dynamic>{};
            _syncButtonStates(data);

            return Column(
              children: [
                RepaintBoundary(child: _buildHeader(data)),
                Material(
                  color: isDark ? Colors.black : Colors.white,
                  child: TabBar(
                    controller: _tab,
                    indicatorColor: isDark ? Colors.white : Colors.black,
                    labelColor: isDark ? Colors.white : Colors.black,
                    unselectedLabelColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.65),
                    tabs: const [
                      Tab(text: 'Music'),
                      Tab(text: 'Latest'),
                      Tab(text: 'Clips'),
                      Tab(text: 'Events'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      RepaintBoundary(
                        child: RefreshIndicator(
                          onRefresh: () async {
                            setState(() {
                              _future = _load();
                            });
                          },
                          child: CustomScrollView(
                            slivers: [
                            // Bio section
                            SliverToBoxAdapter(
                              child: Builder(
                                builder: (context) {
                                  final bio = _extractBio(data);
                                  if (bio == null || bio.isEmpty) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'About',
                                          style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.95), fontSize: 18, fontWeight: FontWeight.w900),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          bio,
                                          maxLines: 4,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.75), fontSize: 14, height: 1.4),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          // Search bar
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) {
                                  _searchDebounce?.cancel();
                                  _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                                    if (mounted) {
                                      setState(() {
                                        _searchQuery = value.toLowerCase();
                                      });
                                    }
                                  });
                                },
                                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                                decoration: InputDecoration(
                                  hintText: 'Search songs...',
                                  hintStyle: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5)),
                                  prefixIcon: Icon(Icons.search, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7)),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(Icons.clear, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7)),
                                          onPressed: () {
                                            _searchDebounce?.cancel();
                                            _searchController.clear();
                                            setState(() {
                                              _searchQuery = '';
                                            });
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: _sectionTitle('Popular'),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                          _buildPopularSliver(data),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: _sectionTitle('Albums'),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                          _buildAlbumsSliver(data),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: _sectionTitle('Related artists'),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                          _buildRelatedArtistsSliver(data),
                          const SliverToBoxAdapter(child: SizedBox(height: 90)),
                        ],
                      ),
                        ),
                      ),
                      // Latest Tracks Tab
                      RepaintBoundary(
                        child: RefreshIndicator(
                          onRefresh: () async {
                            setState(() {
                              _future = _load();
                            });
                          },
                          child: CustomScrollView(
                            slivers: [
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                  child: Text(
                                    'Latest Releases',
                                    style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.95), fontSize: 22, fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                              const SliverToBoxAdapter(child: SizedBox(height: 12)),
                              _buildLatestTracksSliver(data),
                              const SliverToBoxAdapter(child: SizedBox(height: 90)),
                            ],
                          ),
                        ),
                      ),
                      RepaintBoundary(child: _buildClipsTab(data)),
                      ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text('Events', style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.95), fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 12),
                          Text('Coming soon', style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.65))),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: MiniPlayer(player: PlayerService.instance),
    );
  }

  /// Collects unique track items across the artist's track widgets — each
  /// carries a backend preview/clip source used for the Clips tab.
  List<Map<String, dynamic>> _clipItems(Map<String, dynamic> data) {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    void addItems(Iterable<dynamic> items) {
      for (final it in items) {
        if (it is! Map) continue;
        final m = Map<String, dynamic>.from(it);
        final h = (m['hash'] ?? m['object_hash'] ?? m['objectHash'])?.toString() ?? '';
        if (h.isEmpty || !seen.add(h)) continue;
        out.add(m);
      }
    }

    final widgets = data['widgets'];
    if (widgets is List) {
      for (final w in widgets) {
        if (w is! Map) continue;
        final m = Map<String, dynamic>.from(w);
        final display = m['display'];
        final ot = display is Map ? (display['o_type'] ?? display['type'])?.toString() : null;
        final id = (m['ID'] ?? m['id'] ?? '').toString().toLowerCase();
        if (ot != 'm_track' && !id.contains('track')) continue;
        addItems(_widgetItems(m));
      }
    }
    // The artist payload carries tracks directly under data.tracks — widgets
    // are often absent, which left the Clips tab empty.
    final tracks = data['tracks'];
    if (tracks is List) addItems(tracks);
    return out;
  }

  Future<void> _playClip(Map<String, dynamic> it, [String? fallbackCover]) async {
    final objectType = (it['object_type'] ?? it['type'] ?? it['objectType'] ?? it['ot'])?.toString();
    final objectHash = (it['hash'] ?? it['object_hash'] ?? it['objectHash'])?.toString();
    final title = _extractTrackTitle(it) ?? 'Clip';
    final subtitle = _extractTrackSubtitle(it) ?? '';
    final cover = _extractCoverUrl(it) ??
        ((fallbackCover != null && fallbackCover.isNotEmpty) ? fallbackCover : null);
    final url = (it['url'] ?? it['play'] ?? it['web_address'] ?? '').toString();

    final track = Track(
      id: (objectHash == null || objectHash.isEmpty) ? 'clip:$title' : objectHash,
      title: title,
      url: url,
      subtitle: subtitle,
      coverUrl: cover,
      artistSlug: _artistSlugFromItem(it),
      artistLink: it['sub_link']?.toString(),
      objectType: (objectType == null || objectType.isEmpty) ? 'm_track' : objectType,
      objectHash: objectHash,
      aiPct: Track.aiPctFromJson(it),
    );
    await PlayerService.instance.playClip(track);
    // A clip resolved to a video stream needs the full player surface —
    // the mini player has no video renderer.
    if (!mounted) return;
    if (PlayerService.instance.currentSourceType == 'video') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(player: PlayerService.instance),
        ),
      );
    }
  }

  Widget _buildClipsTab(Map<String, dynamic> data) {
    final isDark = _isDark;
    final clips = _clipItems(data);
    // Artist-level artwork as fallback — clip items often carry cover:null.
    final fallbackCover = _extractCoverUrl(data);
    if (clips.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Clips', style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.95), fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Text('No clips available', style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.65))),
        ],
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.66,
      ),
      itemCount: clips.length,
      itemBuilder: (context, i) => _clipCard(clips[i], isDark, fallbackCover),
    );
  }

  Widget _clipCard(Map<String, dynamic> it, bool isDark, [String? fallbackCover]) {
    final title = _extractTrackTitle(it) ?? 'Clip';
    final subtitle = _extractTrackSubtitle(it) ?? '';
    final cover = _extractCoverUrl(it) ??
        ((fallbackCover != null && fallbackCover.isNotEmpty) ? fallbackCover : null);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _playClip(it, fallbackCover),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover != null && cover.isNotEmpty)
              CachedNetworkImage(
                imageUrl: cover,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                  child: Icon(Icons.music_note, color: isDark ? Colors.white38 : Colors.black38),
                ),
              )
            else
              Container(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                child: Icon(Icons.music_note, color: isDark ? Colors.white38 : Colors.black38),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.45, 1.0],
                ),
              ),
            ),
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.5),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, color: Colors.white, size: 12),
                    SizedBox(width: 3),
                    Text('Clip', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, height: 1.2),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTrackOptions(Map<String, dynamic> item, Map<String, dynamic> data) {
    final title = _extractTrackTitle(item) ?? 'Track';
    final isDark = _isDark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF282828) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.play_circle_outline,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                title: Text(
                  'Play',
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _playArtistTracks([item], startIndex: 0, artistData: data);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.playlist_add,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                title: Text(
                  'Add to Queue',
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                ),
                onTap: () {
                  Navigator.pop(context);
                  final objectHash = (item['hash'] ?? item['object_hash'] ?? item['objectHash'])?.toString();
                  final objectType = (item['object_type'] ?? item['type'] ?? item['objectType'])?.toString();
                  final subtitle = _extractTrackSubtitle(item) ?? '';
                  final cover = _extractCoverUrl(item);
                  final url = (item['url'] ?? item['play'] ?? item['web_address'] ?? '').toString();
                  
                  if (objectHash != null && objectHash.isNotEmpty) {
                    final track = Track(
                      id: objectHash,
                      title: title,
                      subtitle: subtitle,
                      url: url,
                      coverUrl: cover,
                      objectType: objectType ?? 'm_track',
                      objectHash: objectHash,
                      aiPct: Track.aiPctFromJson(item),
                    );
                    final currentQueue = PlayerService.instance.queue;
                    final newQueue = [...currentQueue, track];
                    PlayerService.instance.playQueue(newQueue, startIndex: currentQueue.isEmpty ? 0 : PlayerService.instance.index);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added "$title" to queue')),
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.share_outlined,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                title: Text(
                  'Share',
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                ),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement share functionality
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
