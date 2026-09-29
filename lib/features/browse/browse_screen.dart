import 'package:flutter/material.dart';

import '../radio/radio_screen.dart';
import 'browse_albums_screen.dart';
import 'browse_artists_screen.dart';
import 'browse_radios_screen.dart';
import 'browse_tracks_screen.dart';
import 'genre_hiphop_screen.dart';
import 'genre_rock_screen.dart';

class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key});

  final List<_BrowseCategory> _categories = const [
    _BrowseCategory(title: 'Tracks', icon: Icons.music_note, color: Color(0xFFFF6B6B), screen: BrowseTracksScreen()),
    _BrowseCategory(title: 'Albums', icon: Icons.album, color: Color(0xFF4ECDC4), screen: BrowseAlbumsScreen()),
    _BrowseCategory(title: 'Artists', icon: Icons.person, color: Color(0xFF45B7D1), screen: BrowseArtistsScreen()),
    _BrowseCategory(title: 'Radio', icon: Icons.radio, color: Color(0xFF96CEB4), screen: RadioScreen()),
    _BrowseCategory(title: 'Rock', icon: Icons.rocket, color: Color(0xFFDDA0DD), screen: GenreRockScreen()),
    _BrowseCategory(title: 'Hip Hop', icon: Icons.headphones, color: Color(0xFFFFD93D), screen: GenreHipHopScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Browse'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Discover Music',
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final cat = _categories[index];
                  return _CategoryCard(
                    title: cat.title,
                    icon: cat.icon,
                    color: cat.color,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => cat.screen),
                    ),
                  );
                },
                childCount: _categories.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }
}

class _BrowseCategory {
  final String title;
  final IconData icon;
  final Color color;
  final Widget screen;

  const _BrowseCategory({
    required this.title,
    required this.icon,
    required this.color,
    required this.screen,
  });
}

class _CategoryCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: -4,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                bottom: -18,
                child: Icon(icon, size: 84, color: color.withValues(alpha: 0.25)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(icon, color: color, size: 22),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
