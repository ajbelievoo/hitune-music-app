import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../../core/network/api_service.dart';
import '../../core/ui/hi_tune_list_tile.dart';
import '../../core/ui/section_header.dart';
import '../auth/auth_gate.dart';
import '../artist/artist_screen.dart';
import '../collection/collection_screen.dart';
import '../player/models/track.dart';
import '../player/player_service.dart';
import 'search_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/cover_image_extractor.dart';

/// One search result row — a playable track, an artist profile, or a
/// collection (album/playlist) that opens CollectionScreen.
class _SearchResult {
  final String kind; // 'track' | 'artist' | 'collection'
  final String ot; // backend object_type (m_track / m_artist / m_album / m_playlist / ...)
  final Track? track;
  final String title;
  final String? subtitle;
  final String? coverUrl;
  final String? artistSlug;
  final Map<String, dynamic>? collectionItem;

  const _SearchResult._({
    required this.kind,
    required this.ot,
    required this.title,
    this.track,
    this.subtitle,
    this.coverUrl,
    this.artistSlug,
    this.collectionItem,
  });

  /// Client-side type filter — the backend `search` endpoint ignores `ot`
  /// and always returns every widget group, so filtering happens here.
  bool matchesType(String type) {
    if (type == 'all') return true;
    if (type == 'm_track') return kind == 'track';
    if (type == 'm_artist') return kind == 'artist';
    if (type == 'm_playlist') {
      return ot == 'm_playlist' || ot == 'u_playlist' || ot == 'playlist';
    }
    return ot == type;
  }

  factory _SearchResult.track(Track t) => _SearchResult._(
        kind: 'track',
        ot: 'm_track',
        track: t,
        title: t.title,
        subtitle: t.subtitle,
        coverUrl: t.coverUrl,
        artistSlug: t.artistSlug,
      );

  factory _SearchResult.artist({
    required String title,
    required String slug,
    String? subtitle,
    String? coverUrl,
  }) =>
      _SearchResult._(
        kind: 'artist',
        ot: 'm_artist',
        title: title,
        subtitle: subtitle ?? 'Artist',
        coverUrl: coverUrl,
        artistSlug: slug,
      );

  factory _SearchResult.collection(String ot, Map<String, dynamic> item, {String? title, String? subtitle, String? coverUrl}) =>
      _SearchResult._(
        kind: 'collection',
        ot: ot,
        title: title ?? 'Collection',
        subtitle: subtitle,
        coverUrl: coverUrl,
        collectionItem: item,
      );
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  final ApiService _api = ApiService.instance;
  final SearchService _searchService = SearchService.instance;
  Timer? _debounce;

  bool _loading = false;
  String? _error;
  List<_SearchResult> _results = const [];

  // Result type filter ('all' = every object type the backend returns)
  String _type = 'all';
  static const _typeOptions = <String, String>{
    'all': 'All',
    'm_track': 'Songs',
    'm_album': 'Albums',
    'm_artist': 'Artists',
    'm_playlist': 'Playlists',
  };

  // Recent search queries (local history)
  List<String> _recent = const [];
  static const _recentKey = 'recent_searches';
  static const _recentMax = 12;

  // Store search history for searchSubmit API
  String? _searchHistory;
  
  // Search suggestions
  List<SearchSuggestion> _suggestions = const [];
  bool _showSuggestions = false;

  String? _extractTextFromHtml(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  String? _extractTitle(Map<String, dynamic> t) {
    final title = _extractTextFromHtml(t['title']?.toString());
    if (title != null) return title;

    final raw = t['raw'];
    if (raw is Map && raw['title'] != null) {
      return _extractTextFromHtml(raw['title']?.toString());
    }

    final tds = t['tds'];
    if (tds is List) {
      for (final cell in tds) {
        if (cell is! Map) continue;
        final cls = (cell['class'] ?? '').toString();
        if (!cls.split(' ').contains('title')) continue;
        final val = _extractTextFromHtml((cell['val'] ?? '').toString());
        if (val != null) return val;
      }
    }

    return null;
  }

  String? _extractSubtitle(Map<String, dynamic> t) {
    final sub = _extractTextFromHtml(t['sub_title']?.toString());
    if (sub != null) return sub;

    // Search items carry the artist line as `sub_data`.
    final subData = _extractTextFromHtml(t['sub_data']?.toString());
    if (subData != null) return subData;

    final raw = t['raw'];
    if (raw is Map && raw['sub_title'] != null) {
      return _extractTextFromHtml(raw['sub_title']?.toString());
    }

    return null;
  }

  String? _extractCoverUrl(Map<String, dynamic> t) {
    return CoverImageExtractor.extract(t);
  }

  /// Extracts the artist slug from a search item (link like
  /// `music/artist/<slug>` or `artist/<slug>`).
  String? _artistSlugFromItem(Map<String, dynamic> t, Map<String, dynamic>? rawMap) {
    final candidates = <String>[
      (t['artist_slug'] ?? rawMap?['artist_slug'] ?? '').toString(),
      (t['link'] ?? rawMap?['link'] ?? '').toString(),
      (t['sub_link'] ?? rawMap?['sub_link'] ?? '').toString(),
      (t['url'] ?? rawMap?['url'] ?? '').toString(),
    ];
    for (final c in candidates) {
      if (c.isEmpty) continue;
      final m = RegExp(r'artist/([^\s/?#]+)', caseSensitive: false).firstMatch(c);
      final slug = m?.group(1);
      if (slug != null && slug.isNotEmpty) return slug;
      // If it looks like a bare slug (no slashes), use it directly.
      if (!c.contains('/') && !c.contains('http') && c.length < 80) return c;
    }
    return null;
  }

  List<_SearchResult> _resultsFromPayload(Map<String, dynamic> payload) {
    final widgetsNode = payload['widgets'];

    // Backend search returns widgets as a map keyed by object type.
    // It can also be a list in some flows.
    final widgetMaps = <Map<String, dynamic>>[];
    if (widgetsNode is Map) {
      // Prefer tracks first.
      final wTrack = widgetsNode['m_track'];
      if (wTrack is Map) widgetMaps.add(Map<String, dynamic>.from(wTrack));
      for (final v in widgetsNode.values) {
        if (v is! Map) continue;
        final m = Map<String, dynamic>.from(v);
        if (identical(m, wTrack)) continue;
        widgetMaps.add(m);
      }
    } else if (widgetsNode is List) {
      for (final w in widgetsNode) {
        if (w is Map) widgetMaps.add(Map<String, dynamic>.from(w));
      }
    } else {
      return const [];
    }

    final out = <_SearchResult>[];
    for (final wm in widgetMaps) {
      final display = wm['display'];
      final widgetOType = (display is Map ? (display['o_type'] ?? '') : '').toString();

      final itemsNode = wm['items'];

      final items = <Map<String, dynamic>>[];
      if (itemsNode is List) {
        items.addAll(itemsNode.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      } else if (itemsNode is Map) {
        // Search endpoint uses: items: { "1": [ ... ] }
        for (final v in itemsNode.values) {
          if (v is List) {
            items.addAll(v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
          }
        }
      }

      for (final t in items) {
        final rawNode = t['raw'];
        final rawMap = rawNode is Map ? Map<String, dynamic>.from(rawNode) : null;
        final hash = (t['hash'] ?? rawMap?['hash'] ?? t['object_hash'] ?? t['ID'] ?? '').toString();
        final ot = (t['ot'] ?? t['o_type'] ?? t['object_type'] ?? widgetOType).toString();
        final kind = ot.isEmpty ? 'm_track' : ot;

        // Clip/preview-only objects never belong in normal search results.
        const clipTypes = {'m_clip', 'clip', 'm_preview', 'preview', 'video_clip', 'm_hook', 'm_reel'};
        if (clipTypes.contains(kind)) continue;

        if (kind == 'm_artist') {
          final slug = _artistSlugFromItem(t, rawMap);
          if (slug == null || slug.isEmpty) continue;
          out.add(_SearchResult.artist(
            title: _extractTitle(t) ?? 'Artist',
            slug: slug,
            subtitle: _extractSubtitle(t) ?? 'Artist',
            coverUrl: _extractCoverUrl(t),
          ));
          continue;
        }

        if (kind != 'm_track') {
          // Albums, playlists, etc. open the collection screen.
          final item = Map<String, dynamic>.from(t);
          item['ot'] = kind;
          if (item['object_type'] == null) item['object_type'] = kind;
          // CollectionScreen reads `link` (list/<hash>) — search items carry
          // `url` (music/album/...), keep both available.
          if ((item['link'] ?? '').toString().isEmpty && (item['url'] ?? '').toString().isNotEmpty) {
            item['link'] = item['url'];
          }
          out.add(_SearchResult.collection(
            kind,
            item,
            title: _extractTitle(t) ?? (kind == 'm_album' ? 'Album' : 'Playlist'),
            subtitle: _extractSubtitle(t),
            coverUrl: _extractCoverUrl(t),
          ));
          continue;
        }

        // Tracks must have a resolvable 32-char hash.
        if (hash.isEmpty) continue;
        if (!RegExp(r'^[a-f0-9]{32}$', caseSensitive: false).hasMatch(hash)) {
          continue;
        }

        final artistLink = (t['sub_link'] ?? rawMap?['sub_link'] ?? '').toString();
        var artistSlug = (t['artist_slug'] ?? rawMap?['artist_slug'] ?? '').toString();
        if (artistSlug.isEmpty && artistLink.contains('artist/')) {
          final parts = artistLink.split('?').first.split('/').where((e) => e.isNotEmpty).toList();
          if (parts.isNotEmpty) artistSlug = parts.last;
        }
        out.add(
          _SearchResult.track(
            Track(
              id: hash,
              title: _extractTitle(t) ?? 'Track',
              subtitle: _extractSubtitle(t),
              url: (t['url'] ?? '').toString(),
              coverUrl: _extractCoverUrl(t),
              artistSlug: artistSlug.isEmpty ? null : artistSlug,
              artistLink: artistLink.isEmpty ? null : artistLink,
              objectType: 'm_track',
              objectHash: hash,
              aiPct: Track.aiPctFromJson(t),
            ),
          ),
        );
      }
    }

    return out;
  }

  Future<void> _searchNow(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
        _searchHistory = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // NOTE: backend endpoint_search enforces page min=2 (bug/quirk),
    // so we send 2 as the first page to avoid validation failure.
    final res = await _api.postPayloadRaw(
      endpoint: 'search',
      data: {
        'query': q,
        'page': '2',
        if (_type != 'all') 'ot': _type,
      },
    );

    if (!mounted) return;

    if (!res.isSuccess || res.data == null) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Search failed';
        _results = const [];
        _searchHistory = null;
      });
      return;
    }

    final payload = res.data!;
    final results = _resultsFromPayload(payload);
    
    // Extract history from response for searchSubmit API
    final history = payload['history']?.toString();
    if (history != null && history.isNotEmpty) {
      _searchHistory = history;
    }

    unawaited(_saveRecent(q));
    
    setState(() {
      _loading = false;
      _error = null;
      _results = results;
    });
  }

  Widget _resultTile(_SearchResult r) {
    if (r.kind == 'track' && r.track != null) {
      final trackQueue = _results
          .where((e) => e.kind == 'track' && e.track != null)
          .map((e) => e.track!)
          .toList();
      final qIndex = trackQueue.indexOf(r.track!);
      return _TrackTile(
        track: r.track!,
        queue: trackQueue,
        index: qIndex < 0 ? 0 : qIndex,
        searchHistory: _searchHistory,
      );
    }

    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: r.coverUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(r.kind == 'artist' ? 20 : 6),
              child: Image.network(
                r.coverUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  r.kind == 'artist' ? Icons.person_rounded : Icons.album_rounded,
                  color: theme.iconTheme.color?.withValues(alpha: 0.6),
                ),
              ),
            )
          : Icon(
              r.kind == 'artist' ? Icons.person_rounded : Icons.album_rounded,
              color: theme.iconTheme.color?.withValues(alpha: 0.6),
            ),
      title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: r.subtitle != null
          ? Text(r.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      onTap: () {
        if (r.kind == 'artist' && r.artistSlug != null) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => ArtistScreen(artistSlug: r.artistSlug!, artistTitle: r.title)),
          );
        } else if (r.kind == 'collection' && r.collectionItem != null) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => CollectionScreen(item: r.collectionItem!)),
          );
        }
      },
    );
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_recentKey) ?? const <String>[];
    if (mounted) setState(() => _recent = raw);
  }

  Future<void> _saveRecent(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final list = List<String>.from(_recent)..removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    list.insert(0, q);
    if (list.length > _recentMax) list.removeRange(_recentMax, list.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentKey, list);
    if (mounted) setState(() => _recent = list);
  }

  Future<void> _clearRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentKey);
    if (mounted) setState(() => _recent = const []);
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    
    // Fetch suggestions for non-empty queries
    if (value.trim().isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 200), () async {
        final suggestions = await _searchService.getSuggestions(value);
        if (mounted) {
          setState(() {
            _suggestions = suggestions;
            _showSuggestions = suggestions.isNotEmpty;
          });
        }
      });
    } else {
      setState(() {
        _suggestions = const [];
        _showSuggestions = false;
      });
    }
    
    // Full search after longer delay
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchNow(value);
      setState(() => _showSuggestions = false);
    });
  }

  void _onSuggestionTap(String suggestion) {
    _q.text = suggestion;
    _q.selection = TextSelection.collapsed(offset: suggestion.length);
    setState(() {
      _suggestions = const [];
      _showSuggestions = false;
    });
    _searchNow(suggestion);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (_q.text.trim().isNotEmpty) {
            await _searchNow(_q.text);
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _q,
              onChanged: _onQueryChanged,
              onSubmitted: _searchNow,
              decoration: const InputDecoration(
                hintText: 'What do you want to listen to?',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            // Type filter chips
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _typeOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final key = _typeOptions.keys.elementAt(i);
                  final label = _typeOptions[key]!;
                  final selected = _type == key;
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) {
                      // Backend ignores `ot` — always returns all widget
                      // groups. Filter client-side, no refetch needed.
                      setState(() => _type = key);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Recent searches (shown when field is empty)
            if (_q.text.trim().isEmpty && !_showSuggestions && _recent.isNotEmpty) ...[
              Row(
                children: [
                  const Expanded(child: SectionHeader(title: 'Recent searches')),
                  TextButton(
                    onPressed: _clearRecent,
                    child: const Text('Clear'),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final term in _recent)
                    InputChip(
                      avatar: const Icon(Icons.history_rounded, size: 18),
                      label: Text(term, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onPressed: () => _onSuggestionTap(term),
                      onDeleted: () async {
                        final list = List<String>.from(_recent)..remove(term);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setStringList(_recentKey, list);
                        if (mounted) setState(() => _recent = list);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            // Search suggestions
            if (_showSuggestions && _suggestions.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < _suggestions.length && i < 5; i++)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.search, color: theme.iconTheme.color?.withValues(alpha: 0.5), size: 20),
                        title: Text(
                          _suggestions[i].text,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _onSuggestionTap(_suggestions[i].text),
                      ),
                  ],
                ),
              ),
            if (_showSuggestions && _suggestions.isNotEmpty) const SizedBox(height: 16),
            const SectionHeader(title: 'Top results'),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_error != null)
              Text(
                _error!,
                style: theme.textTheme.bodyMedium,
              )
            else if (_results.isEmpty)
              Text(
                _q.text.trim().isEmpty ? 'Type to search' : 'No results',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              for (final r in _type == 'all'
                  ? _results
                  : _results.where((e) => e.matchesType(_type)))
                _resultTile(r),
              if (_type != 'all' && _results.every((e) => !e.matchesType(_type)))
                Text(
                  'No ${_typeOptions[_type] ?? ''} results',
                  style: theme.textTheme.bodyMedium,
                ),
            ],
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}

class _TrackTile extends StatefulWidget {
  final Track track;
  final List<Track> queue;
  final int index;
  final String? searchHistory;

  const _TrackTile({required this.track, required this.queue, required this.index, this.searchHistory});

  @override
  State<_TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<_TrackTile> {
  bool _loading = false;

  Future<void> _tryPlay() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final ok = await AuthGate.ensureLoggedIn(
        context,
        reason: 'Login required to play tracks.',
      );
      if (!ok) return;

      // Call searchSubmit API in background when user clicks on search result
      final history = widget.searchHistory;
      final track = widget.track;
      if (history != null && history.isNotEmpty && track.objectHash != null) {
        // Fire and forget - don't wait for this
        ApiService.instance.postRaw(
          endpoint: 'searchSubmit',
          data: {
            'history': history,
            'ot': track.objectType ?? 'm_track',
            'hash': track.objectHash!,
          },
        ).then((res) {
          if (res.isSuccess) {
            AppLogger.d('[SearchScreen] searchSubmit success for ${track.objectHash}');
          } else {
            AppLogger.d('[SearchScreen] searchSubmit failed: ${res.error?.message}');
          }
        }).catchError((e) {
          AppLogger.d('[SearchScreen] searchSubmit error: $e');
        });
      }

      // INSTANT PLAY: PlayerService resolves the URL itself (muse_request_source
      // with solve=false + cache). No caller-side timeout — the service has its
      // own 15s/20s timeouts; a short one here caused false "unavailable" toasts
      // while the real resolution was still running.
      await PlayerService.instance.playQueue(widget.queue, startIndex: widget.index);

      if (!mounted) return;
      final err = PlayerService.instance.lastError;
      final now = PlayerService.instance.currentTrack;
      if (err != null && err.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Play failed: $err')),
        );
      } else if (now != null && now.id.isNotEmpty && now.id != track.id) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selected track unavailable. Playing: ${now.title}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Play failed: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = widget.track;

    return HiTuneListTile(
      imageUrl: track.coverUrl,
      title: track.title,
      subtitle: track.subtitle,
      onTap: _tryPlay,
      trailing: IconButton(
        onPressed: _loading ? null : _tryPlay,
        icon: _loading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.play_circle_outline, color: theme.colorScheme.primary),
      ),
    );
  }
}
