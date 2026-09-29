import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../player/models/track.dart';
import '../../core/ui/cover_image.dart';
import '../../core/utils/cover_image_extractor.dart';
import 'browse_feed_service.dart';
import '../player/player_service.dart';

class BrowseTracksScreen extends StatefulWidget {
  const BrowseTracksScreen({super.key});

  @override
  State<BrowseTracksScreen> createState() => _BrowseTracksScreenState();
}

class _BrowseTracksScreenState extends State<BrowseTracksScreen> {
  List<Track> _tracks = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      // No dedicated /tracks endpoint on the backend — pull m_track items
      // from the home page widgets and top up with recommendations.
      final raw = <Map<String, dynamic>>[
        ...await BrowseFeedService.instance.homeItems('m_track'),
        ...await BrowseFeedService.instance.recommendedTracks(),
      ];

      final tracks = <Track>[];
      final seen = <String>{};
      for (final item in raw) {
        final track = _parseTrack(item);
        if (track != null && seen.add(track.id)) {
          tracks.add(track);
        }
      }

      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading tracks: $e';
        _isLoading = false;
      });
    }
  }

  Track? _parseTrack(Map<String, dynamic> item) {
    final id = (item['ID'] ?? item['id'] ?? item['hash'] ?? item['object_hash']).toString();
    final title = (item['title'] ?? item['name'] ?? 'Unknown Track').toString();
    final subtitle = (item['sub_title'] ?? item['sub_data'] ?? item['artist'] ?? item['artist_name'] ?? item['subtitle'] ?? '').toString();
    final url = (item['url'] ?? item['play'] ?? item['web_address'] ?? '').toString();
    final cover = CoverImageExtractor.extract(item);
    final objectType = (item['object_type'] ?? item['ot'] ?? item['type'] ?? 'm_track').toString();
    final objectHash = (item['hash'] ?? item['object_hash'] ?? id).toString();
    final artistLink = (item['sub_link'] ?? item['artist_link'] ?? '').toString();
    var artistSlug = (item['artist_slug'] ?? item['artistSlug'] ?? '').toString();
    if (artistSlug.isEmpty && artistLink.contains('artist/')) {
      final parts = artistLink.split('?').first.split('/').where((e) => e.isNotEmpty).toList();
      if (parts.isNotEmpty) artistSlug = parts.last;
    }

    if (id.isEmpty) return null;

    return Track(
      id: id,
      title: title,
      subtitle: subtitle.isNotEmpty ? subtitle : null,
      url: url,
      coverUrl: cover,
      artistSlug: artistSlug.isEmpty ? null : artistSlug,
      artistLink: artistLink.isEmpty ? null : artistLink,
      objectType: objectType,
      objectHash: objectHash,
    );
  }

  void _playTrack(Track track) {
    final index = _tracks.indexWhere((t) => t.id == track.id);
    PlayerService.instance.playQueue(
      _tracks,
      startIndex: index < 0 ? 0 : index,
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
        title: Text(
          'Browse Tracks',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.white : Colors.black),
        ),
      );
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _error,
              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadTracks,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_tracks.isEmpty) {
      return Center(
        child: Text(
          'No tracks available',
          style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTracks,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tracks.length,
        itemBuilder: (context, index) {
          final track = _tracks[index];
          return _buildTrackItem(track, index, isDark);
        },
      ),
    );
  }

  Widget _buildTrackItem(Track track, int index, bool isDark) {
    final player = PlayerService.instance;
    return StreamBuilder<Track?>(
      stream: player.currentTrackStream,
      initialData: player.currentTrack,
      builder: (context, trackSnap) {
        final cur = trackSnap.data;
        final isCurrent = cur != null &&
            (cur.id == track.id ||
                (track.objectHash != null &&
                    track.objectHash!.isNotEmpty &&
                    cur.objectHash == track.objectHash));
        return StreamBuilder<PlayerState>(
          stream: player.audioPlayer.playerStateStream,
          initialData: player.audioPlayer.playerState,
          builder: (context, stateSnap) {
            final isPlaying = isCurrent && (stateSnap.data?.playing ?? false);
            final accent = Theme.of(context).colorScheme.primary;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isCurrent
                    ? accent.withValues(alpha: 0.14)
                    : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: isCurrent
                    ? Border.all(color: accent.withValues(alpha: 0.45))
                    : null,
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.purple.withValues(alpha: 0.2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CoverImage(
                      imageUrl: track.coverUrl,
                      lookupTitle: track.title,
                      lookupSubtitle: track.subtitle,
                      placeholder: Container(
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                        child: Icon(Icons.music_note, color: isDark ? Colors.white70 : Colors.black54),
                      ),
                    ),
                  ),
                ),
                title: Text(
                  track.title,
                  style: TextStyle(
                    color: isCurrent ? accent : (isDark ? Colors.white : Colors.black),
                    fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: track.subtitle != null
                    ? Text(
                        track.subtitle!,
                        style: TextStyle(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                trailing: IconButton(
                  icon: Icon(
                    isCurrent
                        ? (isPlaying ? Icons.graphic_eq_rounded : Icons.pause_circle_filled_rounded)
                        : Icons.play_circle_fill,
                    color: isCurrent ? accent : Colors.purple,
                    size: 32,
                  ),
                  onPressed: () {
                    if (isCurrent) {
                      player.togglePlayPause();
                    } else {
                      _playTrack(track);
                    }
                  },
                ),
                onTap: () {
                  if (isCurrent) {
                    player.togglePlayPause();
                  } else {
                    _playTrack(track);
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}
