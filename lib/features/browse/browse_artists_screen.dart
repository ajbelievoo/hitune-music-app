import 'package:flutter/material.dart';

import '../../core/ui/cover_image.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../artist/artist_screen.dart';
import 'browse_feed_service.dart';

class BrowseArtistsScreen extends StatefulWidget {
  const BrowseArtistsScreen({super.key});

  @override
  State<BrowseArtistsScreen> createState() => _BrowseArtistsScreenState();
}

class _BrowseArtistsScreenState extends State<BrowseArtistsScreen> {
  List<Map<String, dynamic>> _artists = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadArtists();
  }

  Future<void> _loadArtists() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      // No dedicated /artists endpoint — collect m_artist items from the
      // home page widgets, else derive artists from track sub_links.
      var artists = await BrowseFeedService.instance.homeItems('m_artist');
      if (artists.isEmpty) {
        artists = await BrowseFeedService.instance.derivedArtists();
      }

      setState(() {
        _artists = artists;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading artists: $e';
        _isLoading = false;
      });
    }
  }

  void _playArtistTracks(Map<String, dynamic> artist) {
    // Backend items carry url like "music/artist/<slug>" — extract the slug.
    final link = (artist['url'] ?? artist['link'] ?? artist['sub_link'] ?? '').toString();
    final slug = link.contains('/') ? link.split('/').last : link;
    if (slug.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ArtistScreen(artistSlug: slug)),
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
          'Browse Artists',
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
              onPressed: _loadArtists,
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

    if (_artists.isEmpty) {
      return Center(
        child: Text(
          'No artists available',
          style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadArtists,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.8,
        ),
        itemCount: _artists.length,
        itemBuilder: (context, index) {
          final artist = _artists[index];
          return _buildArtistItem(artist, index, isDark);
        },
      ),
    );
  }

  Widget _buildArtistItem(Map<String, dynamic> artist, int index, bool isDark) {
    final name = artist['name']?.toString() ?? artist['artist_name']?.toString() ?? 'Unknown Artist';
    final cover = CoverImageExtractor.extract(artist);
    final tracksCount = artist['tracks_count']?.toString() ?? '';

    return GestureDetector(
      onTap: () => _playArtistTracks(artist),
      child: Container(
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  color: Colors.purple.withValues(alpha: 0.2),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: CoverImage(
                    imageUrl: cover,
                    lookupTitle: name,
                    placeholder: Container(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                      child: Icon(Icons.person, color: isDark ? Colors.white70 : Colors.black54, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (tracksCount.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$tracksCount tracks',
                      style: TextStyle(
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
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
}
