import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_service.dart';
import '../iyol/iyol_deeplink.dart';

/// IyolMe stories rail — recent public stories from the IyolMe app,
/// fetched via the music server's `iyol/stories` public mirror.
/// Tapping a circle deep-links into IyolMe (iyolme://story/<id>).
/// Renders nothing when IyolMe isn't configured or has no stories.
class IyolStoriesRail extends StatelessWidget {
  const IyolStoriesRail({super.key});

  static Future<List<Map<String, dynamic>>> _fetch() async {
    final res = await ApiService.instance
        .postPayloadRaw(endpoint: 'iyol/stories', data: {'limit': '20'});
    if (!res.isSuccess || res.data == null) return const [];
    final raw = res.data!['stories'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetch(),
      builder: (context, snap) {
        final stories = snap.data ?? const <Map<String, dynamic>>[];
        // Always render — the leading "Your story" circle lets the user
        // post to IyolMe even when the feed has no stories yet.

        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text(
                    'IyolMe Stories',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE56BD8).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'IYOLME',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFE56BD8),
                          letterSpacing: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: stories.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, i) => i == 0
                    ? const _AddStoryCircle()
                    : _StoryCircle(story: stories[i - 1]),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Leading "+" circle — deep-links into IyolMe's story camera.
class _AddStoryCircle extends StatelessWidget {
  const _AddStoryCircle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(40),
      onTap: () => IyolDeepLink.openStoryCreate(),
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: const Icon(Icons.add_rounded, size: 30),
            ),
            const SizedBox(height: 4),
            Text('Your story',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _StoryCircle extends StatelessWidget {
  final Map<String, dynamic> story;
  const _StoryCircle({required this.story});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = story['user'] is Map ? story['user'] as Map<String, dynamic> : null;
    final name = (user?['fullname'] ?? user?['username'] ?? 'IyolMe').toString();
    final avatar = (user?['avatar'] ?? story['thumbnail'] ?? '').toString();
    final id = story['id'] is num ? (story['id'] as num).toInt() : int.tryParse('${story['id']}') ?? 0;

    return InkWell(
      borderRadius: BorderRadius.circular(40),
      onTap: id > 0 ? () => IyolDeepLink.openStory(id) : null,
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              padding: const EdgeInsets.all(2.5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF0FA8D4), Color(0xFFE56BD8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: CircleAvatar(
                backgroundColor: theme.colorScheme.surface,
                child: ClipOval(
                  child: avatar.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: avatar,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Icon(Icons.person),
                        )
                      : const Icon(Icons.person),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
