import 'package:flutter/material.dart';

import '../../core/ui/cover_image.dart';
import '../../core/utils/cover_image_extractor.dart';
import 'browse_feed_service.dart';
import '../player/models/track.dart';
import '../player/player_service.dart';

class BrowseRadiosScreen extends StatefulWidget {
  const BrowseRadiosScreen({super.key});

  @override
  State<BrowseRadiosScreen> createState() => _BrowseRadiosScreenState();
}

class _BrowseRadiosScreenState extends State<BrowseRadiosScreen> {
  List<Map<String, dynamic>> _radios = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadRadios();
  }

  Future<void> _loadRadios() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      final radios = await BrowseFeedService.instance.radios();

      setState(() {
        _radios = radios;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading radios: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _playRadio(Map<String, dynamic> radio) async {
    final radioUrl = radio['url']?.toString() ?? radio['stream_url']?.toString();
    if (radioUrl == null || radioUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This station has no stream URL')),
      );
      return;
    }
    final name = (radio['name'] ?? radio['title'] ?? 'Radio').toString();
    final track = Track(
      id: 'radio:$radioUrl',
      title: name,
      subtitle: (radio['genre'] ?? 'Live Radio').toString(),
      url: radioUrl,
      coverUrl: (radio['image'] ?? radio['logo'] ?? radio['cover'])?.toString(),
      sourceType: 'audio',
    );
    await PlayerService.instance.playTrack(track);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Browse Radios',
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
              onPressed: _loadRadios,
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

    if (_radios.isEmpty) {
      return const Center(
        child: Text(
          'No radios available',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRadios,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _radios.length,
        itemBuilder: (context, index) {
          final radio = _radios[index];
          return _buildRadioItem(radio, index);
        },
      ),
    );
  }

  Widget _buildRadioItem(Map<String, dynamic> radio, int index) {
    final name = radio['name']?.toString() ?? radio['radio_name']?.toString() ?? 'Unknown Radio';
    final description = radio['description']?.toString() ?? radio['about']?.toString() ?? '';
    final cover = CoverImageExtractor.extract(radio) ??
        radio['image']?.toString() ??
        radio['logo']?.toString();
    final genre = radio['genre']?.toString() ?? radio['category']?.toString() ?? 'Radio';

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
            color: Colors.purple.withValues(alpha: 0.2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CoverImage(
              imageUrl: cover,
              placeholder: Container(
                color: Colors.white.withAlpha(8),
                child: const Icon(Icons.radio, color: Colors.white70),
              ),
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description.isNotEmpty)
              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 2),
            Text(
              genre,
              style: TextStyle(
                color: Colors.purple.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.play_circle_fill, color: Colors.purple, size: 32),
          onPressed: () => _playRadio(radio),
        ),
        onTap: () => _playRadio(radio),
      ),
    );
  }
}
