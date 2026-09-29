import 'package:flutter/material.dart';

import '../../core/ui/cover_image.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../collection/collection_screen.dart';
import '../player/models/track.dart';
import '../player/player_service.dart';
import 'recommendations_service.dart';

/// "Made for you" horizontal rail. Renders nothing when the backend does not
/// return recommendations, so it is safe to include unconditionally.
class MadeForYouSection extends StatelessWidget {
  const MadeForYouSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Map<String, dynamic>>?>(
      future: RecommendationsService.instance.fetchRecommendations(),
      builder: (context, snap) {
        final items = snap.data;
        if (items == null || items.isEmpty) return const SizedBox.shrink();

        // Pre-convert track items so tapping plays them as a queue.
        final tracks = <Track?>[
          for (final item in items)
            RecommendationsService.itemToTrack(item)?.copyWith(
              coverUrl: CoverImageExtractor.extract(item),
            ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Made for you',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final item = items[i];
                  final track = tracks[i];
                  final title = (item['title'] ?? item['name'] ?? 'Mix').toString();
                  final sub = (item['sub_title'] ?? item['sub_data'] ?? item['subtitle'] ?? '').toString();
                  final cover = CoverImageExtractor.extract(item);
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      if (track != null) {
                        final playable = tracks.whereType<Track>().toList();
                        PlayerService.instance.playQueue(
                          playable,
                          startIndex: playable.indexOf(track),
                        );
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => CollectionScreen(item: item)),
                      );
                    },
                    child: SizedBox(
                      width: 140,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: 140,
                              height: 140,
                              child: CoverImage(
                                imageUrl: cover,
                                lookupTitle: title,
                                lookupSubtitle: sub,
                                placeholder: _ph(theme),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (sub.isNotEmpty)
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _ph(ThemeData theme) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.auto_awesome_rounded),
      );
}
