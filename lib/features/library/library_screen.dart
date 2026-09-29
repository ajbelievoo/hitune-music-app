import 'package:flutter/material.dart';

import '../../core/ui/cover_image.dart';
import '../../core/ui/hi_tune_card.dart';
import '../../core/ui/section_header.dart';
import '../auth/auth_gate.dart';
import '../browse/browse_albums_screen.dart';
import '../browse/browse_artists_screen.dart';
import '../browse/browse_tracks_screen.dart';
import '../player/player_service.dart';
import '../downloads/downloads_screen.dart';
import 'liked_songs_screen.dart';
import 'playlists_screen.dart';
import 'recently_played_screen.dart';
import 'subscriptions_screen.dart';
import 'history_screen.dart';
import 'uploads_screen.dart';
import 'upload_redirect_screen.dart';

class LibraryScreen extends StatefulWidget {
  final bool useScaffold;
  const LibraryScreen({super.key, this.useScaffold = true});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _player = PlayerService.instance;
  int _likedCount = 0;
  int _recentlyPlayedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final likedIds = await _player.likedIdsStream.first;
    final recentlyPlayedIds = await _player.recentlyPlayedIdsStream.first;
    setState(() {
      _likedCount = likedIds.length;
      _recentlyPlayedCount = recentlyPlayedIds.length;
    });
  }

  Future<void> _push(Widget screen, {bool requireLogin = false}) async {
    if (requireLogin) {
      final ok = await AuthGate.ensureLoggedIn(
        context,
        reason: 'Login required to view this library section.',
      );
      if (!ok) return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final body = RefreshIndicator(
      onRefresh: _loadCounts,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          const SectionHeader(title: 'Library'),
          _LibraryTile(
            title: 'Playlists',
            subtitle: 'Your playlists',
            icon: Icons.playlist_play_rounded,
            iconColor: theme.colorScheme.primary,
            onTap: () => _push(const PlaylistsScreen(), requireLogin: true),
          ),
          _LibraryTile(
            title: 'Artists',
            subtitle: 'Your followed artists',
            icon: Icons.person_rounded,
            iconColor: const Color(0xFFFF6B6B),
            onTap: () => _push(const BrowseArtistsScreen()),
          ),
          _LibraryTile(
            title: 'Albums',
            subtitle: 'Your favorite albums',
            icon: Icons.album_rounded,
            iconColor: const Color(0xFF4ECDC4),
            onTap: () => _push(const BrowseAlbumsScreen()),
          ),
          _LibraryTile(
            title: 'Songs',
            subtitle: 'All songs',
            icon: Icons.music_note_rounded,
            iconColor: const Color(0xFF45B7D1),
            onTap: () => _push(const BrowseTracksScreen()),
          ),
          _LibraryTile(
            title: 'Liked Songs',
            subtitle: '$_likedCount songs',
            icon: Icons.favorite_rounded,
            iconColor: theme.colorScheme.primary,
            onTap: () => _push(const LikedSongsScreen(), requireLogin: true),
          ),
          const SectionHeader(title: 'Recently Played'),
          _LibraryTile(
            title: 'Recently Played',
            subtitle: '$_recentlyPlayedCount songs',
            icon: Icons.history_rounded,
            iconColor: const Color(0xFFFFA726),
            onTap: () => _push(const RecentlyPlayedScreen(), requireLogin: true),
          ),
          if (_recentlyPlayedCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: HiTuneCard(
                imageUrl: null,
                title: 'Continue Listening',
                subtitle: '$_recentlyPlayedCount songs',
                width: double.infinity,
                height: 180,
                onTap: () => _push(const RecentlyPlayedScreen(), requireLogin: true),
              ),
            ),
          const SectionHeader(title: 'Your Content'),
          _LibraryTile(
            title: 'Subscriptions',
            subtitle: 'Artists you follow',
            icon: Icons.subscriptions_rounded,
            iconColor: const Color(0xFF66BB6A),
            onTap: () => _push(const SubscriptionsScreen(), requireLogin: true),
          ),
          _LibraryTile(
            title: 'History',
            subtitle: 'Your listening history',
            icon: Icons.access_time_rounded,
            iconColor: const Color(0xFF26A69A),
            onTap: () => _push(const HistoryScreen(), requireLogin: true),
          ),
          _LibraryTile(
            title: 'Downloads',
            subtitle: 'Offline songs on this device',
            icon: Icons.download_rounded,
            iconColor: const Color(0xFF64B5F6),
            onTap: () => _push(const DownloadsScreen()),
          ),
          _LibraryTile(
            title: 'My Uploads',
            subtitle: 'Manage your uploads',
            icon: Icons.cloud_upload_rounded,
            iconColor: const Color(0xFFAB47BC),
            onTap: () => _push(const UploadsScreen(), requireLogin: true),
          ),
          _LibraryTile(
            title: 'Upload Music',
            subtitle: 'Via HiTune Distribution portal',
            icon: Icons.add_circle_rounded,
            iconColor: const Color(0xFF9CCC65),
            onTap: () => _push(const UploadRedirectScreen(), requireLogin: true),
          ),
        ],
      ),
    );

    if (!widget.useScaffold) return body;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text('Edit'),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _LibraryTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? coverUrl;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  const _LibraryTile({
    required this.title,
    required this.subtitle,
    this.coverUrl,
    this.icon,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 52,
          height: 52,
          child: _buildLeading(theme),
        ),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall,
      ),
      trailing: Icon(Icons.chevron_right, color: theme.iconTheme.color?.withValues(alpha: 0.3), size: 22),
      onTap: onTap,
    );
  }

  Widget _buildLeading(ThemeData theme) {
    return CoverImage(
      imageUrl: coverUrl,
      placeholder: _iconPlaceholder(theme),
    );
  }

  Widget _iconPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        icon ?? Icons.music_note,
        color: iconColor ?? theme.colorScheme.primary,
        size: 26,
      ),
    );
  }
}
