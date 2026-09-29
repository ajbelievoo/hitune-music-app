import 'package:flutter/material.dart';

import '../auth/auth_gate.dart';
import 'user_edit_service.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  static Future<void> openWithAuth(BuildContext context) async {
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to manage sessions.');
    if (!ok) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SessionsScreen()),
    );
  }

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final _svc = UserEditService();

  bool _loading = false;
  String? _error;
  List<_SessionRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<_SessionRow> _parseSessions(Map<String, dynamic> payload) {
    final sessions = payload['sessions'];
    final html = (sessions is Map ? sessions['html'] : payload['html'])?.toString() ?? '';
    if (html.isEmpty) return const [];

    String stripTags(String s) =>
        s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final out = <_SessionRow>[];
    // Attribute quotes in the backend HTML can be single or double.
    final re = RegExp(r'''<tr class=["']session[^"']*["']>[\s\S]*?<\/tr>''');
    for (final m in re.allMatches(html)) {
      final chunk = m.group(0) ?? '';
      final cells = RegExp(r'''<td[^>]*>([\s\S]*?)<\/td>''')
          .allMatches(chunk)
          .map((e) => stripTags(e.group(1) ?? ''))
          .where((e) => e.isNotEmpty)
          .toList();
      var ip = RegExp(r'''<td class=["']ip["']><span>([^<]+)<''').firstMatch(chunk)?.group(1)?.trim() ??
          RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').firstMatch(chunk)?.group(0) ?? '';
      final platform = RegExp(r'''<td class=["']platform["']>([^<]+)<''').allMatches(chunk).map((e) => e.group(1)?.trim() ?? '').toList();
      var lastSeen = RegExp(r'''<td class=["']time_online["']>([^<]+)<''').firstMatch(chunk)?.group(1)?.trim() ?? '';
      final sessId = RegExp(r'''data-sess-id=["']([^"']+)["']''').firstMatch(chunk)?.group(1)?.trim() ?? '';

      var plat = platform.isNotEmpty ? platform.first : '';
      var os = platform.length > 1 ? platform[1] : '';
      var browser = platform.length > 2 ? platform[2] : '';
      // Positional fallback when class names don't match the markup.
      if (plat.isEmpty && cells.length > 1) plat = cells[1];
      if (os.isEmpty && cells.length > 2) os = cells[2];
      if (browser.isEmpty && cells.length > 3) browser = cells[3];
      if (lastSeen.isEmpty && cells.isNotEmpty) lastSeen = cells.last;
      if (ip.isEmpty && cells.isNotEmpty) ip = cells.first;

      if (ip.isEmpty && sessId.isEmpty) continue;
      out.add(_SessionRow(ip: ip, platform: plat, os: os, browser: browser, lastSeen: lastSeen, sessionId: sessId));
    }
    return out;
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final loggedIn = await AuthGate.isLoggedIn();
    debugPrint('[SESSIONS] _load() - loggedIn: $loggedIn');
    if (!mounted) return;
    if (!loggedIn) {
      setState(() {
        _loading = false;
        _rows = const [];
      });
      return;
    }

    final res = await _svc.fetchTab(tab: 'sessions');
    debugPrint('[SESSIONS] _load() - fetchTab result: isSuccess=${res.isSuccess}, error=${res.error?.message}');
    if (!mounted) return;

    if (!res.isSuccess || res.data == null) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Failed to load sessions';
      });
      return;
    }

    debugPrint('[SESSIONS] _load() - data keys: ${res.data!.keys}');
    final rows = _parseSessions(res.data!);
    debugPrint('[SESSIONS] _load() - parsed sessions count: ${rows.length}');
    setState(() {
      _loading = false;
      _rows = rows;
    });
  }

  Future<void> _revoke(_SessionRow row) async {
    if (row.sessionId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout this device?'),
        content: Text('IP: ${row.ip}\n${row.os} • ${row.browser}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Logout')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _loading = true);
    final res = await _svc.revokeSession(sessionId: row.sessionId);
    if (!mounted) return;
    setState(() => _loading = false);

    if (!res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error?.message ?? 'Failed')));
      return;
    }

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthGate.isLoggedIn(),
      builder: (context, snap) {
        final loggedIn = snap.data == true;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('Sessions'),
            backgroundColor: Colors.black,
            actions: [
              IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
            ],
          ),
          body: !loggedIn
              ? _buildGuestView()
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorView()
                      : _rows.isEmpty
                          ? _buildEmptyView()
                          : _buildSessionsList(),
        );
      },
    );
  }

  Widget _buildGuestView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(Icons.devices_outlined, size: 40, color: Colors.blueAccent.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 20),
            Text('Login to manage sessions', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('View and revoke logged-in devices', style: TextStyle(color: Colors.white.withValues(alpha: 0.55))),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to manage sessions.');
                if (!ok) return;
                await _load();
              },
              child: const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.redAccent.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16)),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.devices_outlined, size: 64, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No sessions found', style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildSessionsList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _rows.length,
      itemBuilder: (context, i) => _buildSessionCard(_rows[i]),
    );
  }

  Widget _buildSessionCard(_SessionRow r) {
    final sub = [r.platform, r.os, r.browser, r.lastSeen].where((e) => e.trim().isNotEmpty).join(' • ');
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.devices, color: Colors.blueAccent.withValues(alpha: 0.8)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.ip.isEmpty ? 'Session' : r.ip,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                ),
                if (sub.isNotEmpty)
                  Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
              ],
            ),
          ),
          if (r.sessionId.isNotEmpty)
            IconButton(
              onPressed: () => _revoke(r),
              icon: Icon(Icons.close_rounded, color: Colors.redAccent.withValues(alpha: 0.7)),
            ),
        ],
      ),
    );
  }
}

class _SessionRow {
  final String ip;
  final String platform;
  final String os;
  final String browser;
  final String lastSeen;
  final String sessionId;

  const _SessionRow({
    required this.ip,
    required this.platform,
    required this.os,
    required this.browser,
    required this.lastSeen,
    required this.sessionId,
  });
}
