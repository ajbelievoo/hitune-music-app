import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../player/models/track.dart';
import '../../core/utils/cover_image_extractor.dart';
import 'browse_feed_service.dart';
import '../player/player_service.dart';

class GenreRockScreen extends StatefulWidget {
  const GenreRockScreen({super.key});

  @override
  State<GenreRockScreen> createState() => _GenreRockScreenState();
}

class _GenreRockScreenState extends State<GenreRockScreen> {
  List<Track> _tracks = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadRockTracks();
  }

  Future<void> _loadRockTracks() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      // No /genre/* endpoint — genre browsing goes through `search`.
      final items = await BrowseFeedService.instance.searchGenre(const ['rock']);

      final tracks = <Track>[];
      for (final item in items) {
        final track = _parseTrack(item);
        if (track != null) {
          tracks.add(track);
        }
      }

      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading Rock tracks: $e';
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
    PlayerService.instance.playTrack(track);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          "Rock'n'Roll",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadRockTracks,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_tracks.isEmpty) {
      return const Center(
        child: Text(
          'No Rock tracks available',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRockTracks,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tracks.length,
        itemBuilder: (context, index) {
          final track = _tracks[index];
          return _buildTrackItem(track, index);
        },
      ),
    );
  }

  Widget _buildTrackItem(Track track, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.red.withValues(alpha: 0.2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: track.coverUrl != null
                ? CachedNetworkImage(
                    imageUrl: track.coverUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.white.withAlpha(8),
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.white.withAlpha(8),
                      child: const Icon(Icons.music_note, color: Colors.white70),
                    ),
                  )
                : const Icon(Icons.music_note, color: Colors.white70),
          ),
        ),
        title: Text(
          track.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: track.subtitle != null
            ? Text(
                track.subtitle!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.play_circle_fill, color: Colors.red, size: 32),
          onPressed: () => _playTrack(track),
        ),
        onTap: () => _playTrack(track),
      ),
    );
  }
}
