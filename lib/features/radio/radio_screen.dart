import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../browse/browse_feed_service.dart';
import '../../core/network/api_service.dart';
import '../../core/ui/section_header.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../player/models/track.dart';
import '../player/player_service.dart';

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  List<Map<String, dynamic>> _radios = [];
  bool _isLoading = true;
  String _error = '';
  String? _startingStation;

  // HiTune-generated chart stations (doc §8) — popularity-weighted queues
  // of catalog tracks, served by POST /api/htx/radio.
  static const _htxStations = [
    ('viral', 'Viral Radio', 'This week\'s hottest tracks', Icons.local_fire_department_rounded),
    ('indie', 'Indie Radio', 'Independent artists on HiTune', Icons.star_outline_rounded),
    ('top_ai', 'AI Radio', 'Top AI Originals', Icons.auto_awesome_rounded),
    ('mixed', 'HiTune Radio', 'Popularity-weighted mix', Icons.radio_rounded),
  ];

  Future<void> _startHtxStation(String seed) async {
    setState(() => _startingStation = seed);
    final res = await ApiService.instance.postPayloadRaw(
      endpoint: 'htx/radio',
      data: {'chart': seed, 'limit': '30'},
    );
    if (!mounted) return;
    setState(() => _startingStation = null);
    if (!res.isSuccess || res.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.error?.message ?? 'Station failed to load')));
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
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Station queue is empty')));
      return;
    }
    await PlayerService.instance.playQueue(tracks);
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
      AppLogger.d('[RadioScreen] Error loading radios: $e');
      setState(() {
        _error = 'Error loading radios: $e';
        _isLoading = false;
      });
    }
  }

  Track? _radioToTrack(Map<String, dynamic> radio) {
    final radioUrl = radio['url']?.toString() ?? radio['stream_url']?.toString();
    if (radioUrl == null || radioUrl.isEmpty) return null;
    return Track(
      id: 'radio:$radioUrl',
      title: (radio['name'] ?? radio['title'] ?? 'Radio').toString(),
      subtitle: (radio['sub_title'] ?? radio['genre'] ?? 'Live Radio').toString(),
      url: radioUrl,
      coverUrl: (radio['image'] ?? radio['logo'] ?? radio['cover'])?.toString(),
      sourceType: 'audio',
      objectType: 'radio',
    );
  }

  Future<void> _playRadio(Map<String, dynamic> radio) async {
    // Queue every station so mini-player next/prev switches channels.
    final tracks = <Track>[];
    var startIndex = 0;
    for (final r in _radios) {
      final t = _radioToTrack(r);
      if (t == null) continue;
      if (identical(r, radio)) startIndex = tracks.length;
      tracks.add(t);
    }
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This station has no stream URL')),
      );
      return;
    }
    await PlayerService.instance.playQueue(tracks, startIndex: startIndex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Radio'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? _buildError(theme)
              : RefreshIndicator(
                      onRefresh: _loadRadios,
                      child: CustomScrollView(
                        slivers: [
                          const SliverToBoxAdapter(
                            child: SectionHeader(title: 'HiTune Stations'),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: 46,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _htxStations.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 8),
                                itemBuilder: (context, i) {
                                  final s = _htxStations[i];
                                  final starting = _startingStation == s.$1;
                                  return ActionChip(
                                    avatar: Icon(s.$4, size: 16),
                                    label: Text(starting ? 'Starting…' : s.$2),
                                    onPressed: starting ? null : () => _startHtxStation(s.$1),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(
                            child: SectionHeader(title: 'Featured Stations'),
                          ),
                          if (_radios.isEmpty)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text('No featured stations yet'),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _RadioTile(
                                    radio: _radios[index],
                                    onTap: () => _playRadio(_radios[index]),
                                  ),
                                  childCount: _radios.length,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_error, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadRadios, child: const Text('Retry')),
        ],
      ),
    );
  }

}

class _RadioTile extends StatelessWidget {
  final Map<String, dynamic> radio;
  final VoidCallback? onTap;

  const _RadioTile({required this.radio, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = radio['name']?.toString() ?? radio['radio_name']?.toString() ?? 'Unknown Radio';
    final description = radio['description']?.toString() ?? radio['about']?.toString() ?? radio['sub_title']?.toString() ?? '';
    final cover = radio['cover']?.toString() ?? radio['image']?.toString() ?? radio['logo']?.toString() ?? '';
    final genre = radio['genre']?.toString() ?? radio['category']?.toString() ?? 'Radio';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56,
            height: 56,
            child: cover.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: theme.colorScheme.surfaceContainerHighest),
                    errorWidget: (_, __, ___) => _placeholder(theme),
                  )
                : _placeholder(theme),
          ),
        ),
        title: Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: description.isNotEmpty
            ? Text(
                '$description · $genre',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              )
            : Text(genre, style: theme.textTheme.bodySmall),
        trailing: IconButton(
          onPressed: onTap,
          icon: Icon(Icons.play_circle_fill_rounded, color: theme.colorScheme.primary, size: 32),
        ),
        onTap: onTap,
      ),
    );
  }

  static const _avatarColors = [
    Color(0xFFE91E63), Color(0xFF9C27B0), Color(0xFF3F51B5),
    Color(0xFF2196F3), Color(0xFF009688), Color(0xFF4CAF50),
    Color(0xFFFF9800), Color(0xFFFF5722), Color(0xFF607D8B),
  ];

  Widget _placeholder(ThemeData theme) {
    // Backend sends no station art — derive a stable color + letter avatar.
    final name = radio['name']?.toString() ?? radio['title']?.toString() ?? 'R';
    final color = _avatarColors[name.hashCode.abs() % _avatarColors.length];
    return Container(
      color: color.withValues(alpha: 0.85),
      alignment: Alignment.center,
      child: Text(
        name.trim().isEmpty ? 'R' : name.trim()[0].toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
