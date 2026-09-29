import 'package:flutter/material.dart';

import '../../core/ui/cover_image.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../collection/collection_screen.dart';
import 'browse_feed_service.dart';

class BrowseAlbumsScreen extends StatefulWidget {
  const BrowseAlbumsScreen({super.key});

  @override
  State<BrowseAlbumsScreen> createState() => _BrowseAlbumsScreenState();
}

class _BrowseAlbumsScreenState extends State<BrowseAlbumsScreen> {
  List<Map<String, dynamic>> _albums = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      // No dedicated /albums endpoint — collect m_album items from the
      // home page widgets.
      final albums = await BrowseFeedService.instance.homeItems('m_album');

      setState(() {
        _albums = albums;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading albums: $e';
        _isLoading = false;
      });
    }
  }

  String? _extractCoverUrl(Map<String, dynamic> album) {
    // Central extractor handles every backend shape (cover maps, picture
    // HTML, srcset, plain URLs), upgrades CDN thumbs to hi-res and rejects
    // dummy placeholders.
    return CoverImageExtractor.extract(album);
  }

  void _playAlbum(Map<String, dynamic> album) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CollectionScreen(item: album)),
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
          'Browse Albums',
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
              onPressed: _loadAlbums,
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

    if (_albums.isEmpty) {
      return Center(
        child: Text(
          'No albums available',
          style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAlbums,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.8,
        ),
        itemCount: _albums.length,
        itemBuilder: (context, index) {
          final album = _albums[index];
          return _buildAlbumItem(album, index, isDark);
        },
      ),
    );
  }

  Widget _buildAlbumItem(Map<String, dynamic> album, int index, bool isDark) {
    final name = album['name']?.toString() ?? album['title']?.toString() ?? album['album_name']?.toString() ?? 'Unknown Album';
    final artist = album['artist']?.toString() ?? album['artist_name']?.toString() ?? album['sub_data']?.toString() ?? 'Unknown Artist';
    final cover = _extractCoverUrl(album);
    final tracksCount = album['tracks_count']?.toString() ?? album['s_tracks']?.toString() ?? '0';

    return GestureDetector(
      onTap: () => _playAlbum(album),
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
                    lookupSubtitle: artist,
                    placeholder: Container(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                      child: Icon(Icons.album, color: isDark ? Colors.white70 : Colors.black54, size: 48),
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
                  const SizedBox(height: 4),
                  Text(
                    artist,
                    style: TextStyle(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$tracksCount tracks',
                    style: TextStyle(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
