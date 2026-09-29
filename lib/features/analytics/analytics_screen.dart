import 'package:flutter/material.dart';

import '../../core/network/api_result.dart';
import 'analytics_service.dart';

class AnalyticsScreen extends StatefulWidget {
  final String artistSlug;

  const AnalyticsScreen({super.key, required this.artistSlug});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<ApiResult<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = AnalyticsService().fetchArtistAnalytics(artistSlug: widget.artistSlug);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Music Analytics')),
      body: FutureBuilder<ApiResult<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          final res = snapshot.data;
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (res == null) {
            return const Center(child: Text('No data'));
          }
          if (!res.isSuccess) {
            return Center(child: Text(res.error?.message ?? 'Failed'));
          }

          final data = res.data!;
          final name = (data['name'] ?? data['title'] ?? '').toString();

          int _int(dynamic v) => int.tryParse((v ?? '0').toString()) ?? 0;

          final views = _int(data['s_views'] ?? data['views']);
          final uniqueViews = _int(data['s_views_unique'] ?? data['views_unique']);
          final subs = _int(data['s_subscribers'] ?? data['subscribers']);
          final albums = _int(data['s_albums'] ?? data['albums']);
          final tracks = _int(data['s_tracks'] ?? data['tracks']);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(name.isEmpty ? widget.artistSlug : name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              _StatCard(title: 'Views', value: views.toString()),
              _StatCard(title: 'Unique Views', value: uniqueViews.toString()),
              _StatCard(title: 'Subscribers', value: subs.toString()),
              _StatCard(title: 'Albums', value: albums.toString()),
              _StatCard(title: 'Tracks', value: tracks.toString()),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;

  const _StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
