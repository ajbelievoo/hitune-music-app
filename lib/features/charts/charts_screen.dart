import 'package:flutter/material.dart';

import '../../core/network/api_service.dart';
import '../../core/ui/ai_badge.dart';
import '../../core/ui/cover_image.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../player/models/track.dart';
import '../player/player_service.dart';

/// Weekly leaderboard charts (strategy doc §8):
/// "Top 50 AI Songs", "Top 100 Indie Stars", "Viral HiTune Tracks".
/// Data: POST /api/htx/charts (app-shaped variant of the v1 dev API).
class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  static const _charts = [
    ('viral', 'Viral HiTune Tracks', Icons.trending_up_rounded),
    ('top_ai', 'Top 50 AI Songs', Icons.auto_awesome_rounded),
    ('indie', 'Top 100 Indie Stars', Icons.star_outline_rounded),
  ];

  final _api = ApiService.instance;
  int _tab = 0;
  final Map<int, List<Track>> _cache = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  Future<void> _load(int tab) async {
    setState(() {
      _tab = tab;
      _loading = true;
      _error = null;
    });
    final res = await _api.postPayloadRaw(
      endpoint: 'htx/charts',
      data: {'chart': _charts[tab].$1, 'limit': '50'},
    );
    if (!mounted) return;
    if (!res.isSuccess || res.data == null) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Could not load chart';
      });
      return;
    }
    final list = res.data!['items'];
    final tracks = <Track>[];
    if (list is List) {
      for (final it in list) {
        if (it is! Map) continue;
        final t = _trackFromItem(Map<String, dynamic>.from(it));
        if (t != null) tracks.add(t);
      }
    }
    setState(() {
      _cache[tab] = tracks;
      _loading = false;
    });
  }

  Track? _trackFromItem(Map<String, dynamic> item) {
    final id = (item['ID'] ?? item['id'] ?? item['hash'] ?? item['object_hash'])?.toString();
    if (id == null || id.isEmpty) return null;
    return Track(
      id: id,
      title: (item['title'] ?? 'Unknown').toString(),
      subtitle: (item['sub_title'] ?? item['sub_data'] ?? '').toString(),
      url: (item['url'] ?? '').toString(),
      coverUrl: CoverImageExtractor.extract(item),
      objectType: (item['object_type'] ?? item['ot'] ?? 'm_track').toString(),
      objectHash: (item['hash'] ?? item['object_hash'] ?? id).toString(),
      aiPct: Track.aiPctFromJson(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracks = _cache[_tab] ?? const <Track>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Charts')),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _charts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final sel = i == _tab;
                return ChoiceChip(
                  avatar: Icon(_charts[i].$3, size: 16),
                  label: Text(_charts[i].$2),
                  selected: sel,
                  onSelected: (_) => _load(i),
                );
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : tracks.isEmpty
                        ? const Center(child: Text('No chart entries yet'))
                        : ListView.builder(
                            itemCount: tracks.length,
                            itemBuilder: (context, i) {
                              final t = tracks[i];
                              return ListTile(
                                leading: SizedBox(
                                  width: 64,
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        child: Text('${i + 1}',
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(fontWeight: FontWeight.w800)),
                                      ),
                                      const SizedBox(width: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: SizedBox(
                                          width: 36,
                                          height: 36,
                                          child: CoverImage(
                                            imageUrl: t.coverUrl,
                                            lookupTitle: t.title,
                                            lookupSubtitle: t.subtitle,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(t.title,
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                    if (t.aiPct > 0) ...[
                                      const SizedBox(width: 6),
                                      AiBadge(aiPct: t.aiPct),
                                    ],
                                  ],
                                ),
                                subtitle: Text(t.subtitle ?? '',
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                onTap: () =>
                                    PlayerService.instance.playQueue(tracks, startIndex: i),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
