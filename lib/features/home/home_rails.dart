import 'package:flutter/material.dart';

import '../../core/ui/hi_tune_card.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../player/models/track.dart';
import '../player/player_service.dart';
import 'recommendations_service.dart';

/// Horizontal track rail fed by the recommendations-style endpoints
/// (`recommendations`, `daily_mix`, `recommendations_because`). Renders
/// nothing when the backend returns no items.
class HomeTrackRail extends StatelessWidget {
  final String title;
  final Future<List<Map<String, dynamic>>?> Function() fetcher;

  const HomeTrackRail({super.key, required this.title, required this.fetcher});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>?>(
      future: fetcher(),
      builder: (context, snap) {
        final items = snap.data;
        if (items == null || items.isEmpty) return const SizedBox.shrink();

        final tracks = <Track>[];
        for (final item in items) {
          final t = RecommendationsService.itemToTrack(item);
          if (t != null) {
            tracks.add(t.copyWith(coverUrl: CoverImageExtractor.extract(item) ?? t.coverUrl));
          }
        }
        if (tracks.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            SizedBox(
              height: 205,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tracks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  return HiTuneCard(
                    imageUrl: t.coverUrl,
                    title: t.title,
                    subtitle: t.subtitle,
                    width: 140,
                    height: 140,
                    onTap: () => PlayerService.instance.playQueue(tracks, startIndex: i),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
