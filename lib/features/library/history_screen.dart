import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'user_library_service.dart';
import '../player/models/track.dart';
import '../player/player_service.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../player/mini_player.dart';
import '../auth/auth_gate.dart';
import '../artist/artist_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _svc = UserLibraryService();

  bool _loading = false;
  bool _isFetching = false;
  String? _error;
  List<dynamic> _items = const [];
  int _currentPage = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _fetchPage(1);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchPage(int page) async {
    if (_isFetching) return;
    _isFetching = true;

    final result = await _svc.fetchUserLibrary(tab: 'history', page: page);

    if (!mounted) return;

    if (result.isSuccess) {
      final data = result.data!;
      final widgets = data['widgets'] as List<dynamic>? ?? [];

      if (widgets.isNotEmpty) {
        final widget = widgets.first as Map<String, dynamic>;
        final items = widget['items'] as List<dynamic>? ?? [];

        setState(() {
          if (page == 1) {
            _items = items;
          } else {
            _items = [..._items, ...items];
          }
          _currentPage = page;
          _hasMore = items.length >= 20;
        });
      } else {
        setState(() => _hasMore = false);
      }
    } else {
      final error = result.error!;
      if (error.code == 'forbidden' || error.code == '401') {
        final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to view history.');
        if (ok) {
          await _fetchPage(page);
          return;
        }
      }
      setState(() => _error = error.message);
    }

    _isFetching = false;
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isFetching) return;
    await _fetchPage(_currentPage + 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('History'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _items.isEmpty
                  ? _buildEmptyState()
                  : _buildContent(),
      bottomNavigationBar: MiniPlayer(player: PlayerService.instance),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              'Failed to load history',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8), fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64, color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 16),
            Text(
              'No listening history yet',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tracks you play will appear here',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black38, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          if (notification.metrics.extentAfter < 200) {
            _loadMore();
          }
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final item = _items[index] as Map<String, dynamic>;
          return _HistoryListTile(
            item: item,
            onTap: () => _onItemTap(item),
          );
        },
      ),
    );
  }

  void _onItemTap(Map<String, dynamic> item) {
    // Play the track or navigate to album/artist
    final type = item['type']?.toString() ?? 'track';
    final id = item['ID']?.toString();
    final slug = item['slug']?.toString();

    if (type == 'artist' && (slug != null || id != null)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ArtistScreen(artistSlug: slug ?? id!),
        ),
      );
    } else {
      // Try to play the track
      final trackData = item['track'] as Map<String, dynamic>? ?? item;
      if (trackData.containsKey('source')) {
        final track = Track(
          id: trackData['ID']?.toString() ?? trackData['id']?.toString() ?? '',
          title: trackData['title']?.toString() ?? 'Unknown',
          url: trackData['source']?.toString() ?? '',
          subtitle: trackData['artist']?.toString(),
          coverUrl: CoverImageExtractor.extract(trackData),
          aiPct: Track.aiPctFromJson(trackData),
        );
        PlayerService.instance.playTrack(track);
      }
    }
  }
}

class _HistoryListTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _HistoryListTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final title = item['title']?.toString() ?? item['name']?.toString() ?? 'Unknown';
    final subtitle = item['artist']?.toString() ?? item['sub_title']?.toString() ?? '';
    final cover = item['cover']?.toString() ?? item['image']?.toString() ?? '';
    final type = item['type']?.toString() ?? 'Track';
    final duration = item['duration_hr']?.toString() ?? '';

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: cover.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                          child: Icon(Icons.music_note, color: isDark ? Colors.white54 : Colors.black54),
                        ),
                      )
                    : Container(
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                        child: Icon(Icons.music_note, color: isDark ? Colors.white54 : Colors.black54),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  type,
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 11,
                  ),
                ),
                if (duration.isNotEmpty)
                  Text(
                    duration,
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: isDark ? Colors.white24 : Colors.black12),
          ],
        ),
      ),
    );
  }
}
