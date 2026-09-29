import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_service.dart';

/// Fan tipping wallet + history (strategy doc §4): balance, tips sent and
/// received, and a Razorpay top-up entry point.
/// Data: /api/dist/tip actions wallet|history|topup.
class TipHistoryScreen extends StatefulWidget {
  const TipHistoryScreen({super.key});

  @override
  State<TipHistoryScreen> createState() => _TipHistoryScreenState();
}

class _TipHistoryScreenState extends State<TipHistoryScreen> {
  final _api = ApiService.instance;
  Map<String, dynamic>? _wallet;
  List<Map<String, dynamic>> _sent = const [];
  List<Map<String, dynamic>> _received = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await _api.postPayloadRaw(endpoint: 'dist/tip', data: const {'action': 'wallet'});
    final h = await _api.postPayloadRaw(endpoint: 'dist/tip', data: const {'action': 'history'});
    if (!mounted) return;
    final wd = w.data;
    final hd = h.data;
    setState(() {
      _loading = false;
      _wallet = wd != null ? Map<String, dynamic>.from(wd) : null;
      if (hd != null) {
        _sent = hd['sent'] is List
            ? (hd['sent'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : const [];
        _received = hd['received'] is List
            ? (hd['received'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : const [];
      }
    });
  }

  Future<void> _topup() async {
    final res = await _api.postPayloadRaw(endpoint: 'dist/tip', data: {
      'action': 'topup',
      'amount': '100',
    });
    if (!mounted) return;
    final url = res.data?['payment_url'] ?? res.data?['url'];
    if (url != null) {
      launchUrl(Uri.parse(url.toString()), mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Top-up is not available right now')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tips & Wallet')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Wallet', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text('₹${(_wallet?['balance'] ?? 0)}',
                              style: theme.textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                            'Sent ₹${_wallet?['tips_sent'] ?? 0} • Earned ₹${_wallet?['tips_earned'] ?? 0}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: _topup,
                            icon: const Icon(Icons.add_card_rounded),
                            label: const Text('Top up ₹100'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_received.isNotEmpty) ...[
                    Text('Tips received', style: theme.textTheme.titleSmall),
                    ..._received.map((t) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.volunteer_activism_rounded),
                          title: Text('+₹${t['artist_amount'] ?? t['amount'] ?? ''}'),
                          subtitle: Text('from ${t['from_name'] ?? 'fan'} • ${t['created_at'] ?? ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  const SizedBox(height: 10),
                  Text('Tips sent', style: theme.textTheme.titleSmall),
                  if (_sent.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No tips yet — open a track’s actions and tap "Tip Artist".'),
                    )
                  else
                    ..._sent.map((t) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.favorite_outline_rounded),
                          title: Text('₹${t['amount'] ?? ''}'),
                          subtitle: Text('to ${t['to_name'] ?? 'artist'} • ${t['created_at'] ?? ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        )),
                ],
              ),
            ),
    );
  }
}
