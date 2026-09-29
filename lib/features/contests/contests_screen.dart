import 'package:flutter/material.dart';

import '../../core/network/api_service.dart';

/// Monthly collab competitions (strategy doc §8): active contests with
/// live leaderboards — "Best AI Song", "Best Indie Track".
/// Data: POST /api/htx/contests.
class ContestsScreen extends StatefulWidget {
  const ContestsScreen({super.key});

  @override
  State<ContestsScreen> createState() => _ContestsScreenState();
}

class _ContestsScreenState extends State<ContestsScreen> {
  final _api = ApiService.instance;
  List<Map<String, dynamic>> _contests = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _api.postPayloadRaw(endpoint: 'htx/contests', data: const {'board_limit': '20'});
    if (!mounted) return;
    final list = res.data?['contests'];
    setState(() {
      _loading = false;
      _contests = list is List
          ? list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const [];
      _error = res.isSuccess
          ? (_contests.isEmpty ? 'No active contests right now' : null)
          : (res.error?.message ?? 'Could not load contests');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Contests')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center)))
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _contests.length,
                  itemBuilder: (context, i) => _ContestCard(contest: _contests[i], theme: theme),
                ),
    );
  }
}

class _ContestCard extends StatelessWidget {
  final Map<String, dynamic> contest;
  final ThemeData theme;
  const _ContestCard({required this.contest, required this.theme});

  @override
  Widget build(BuildContext context) {
    final board = contest['leaderboard'];
    final items = board is List ? board : const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.emoji_events_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(contest['title']?.toString() ?? 'Contest',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ]),
            if ((contest['prize'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Prize: ${contest['prize']}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary)),
            ],
            if ((contest['ends_at'] ?? '').toString().isNotEmpty)
              Text('Ends: ${contest['ends_at']}', style: theme.textTheme.bodySmall),
            const Divider(height: 20),
            ...items.take(10).map((e) {
              final it = e is Map ? Map<String, dynamic>.from(e) : const <String, dynamic>{};
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(
                    width: 26,
                    child: Text('#${it['rank'] ?? ''}',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(it['title']?.toString() ?? '',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          if (it['ai_badge'] != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('AI',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary, fontSize: 9)),
                            ),
                          ],
                        ]),
                        Text(it['artist']?.toString() ?? '',
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Text('${it['plays'] ?? 0} plays', style: theme.textTheme.bodySmall),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }
}
