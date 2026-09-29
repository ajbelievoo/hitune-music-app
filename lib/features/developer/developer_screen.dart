import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_service.dart' show JsonMap;
import '../auth/auth_gate.dart';
import 'developer_app_sheet.dart';
import 'developer_service.dart';

/// Developer portal — manage third-party API apps, keys, usage and plans.
/// Only reachable when `client_config.setting.developer_portal` is true;
/// the profile entry point checks [DeveloperService.isPortalEnabled].
class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  static Future<void> openWithAuth(BuildContext context) async {
    final ok = await AuthGate.ensureLoggedIn(context,
        reason: 'Login required to manage developer apps.');
    if (!ok || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DeveloperScreen()),
    );
  }

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  bool _loading = true;
  bool _portalEnabled = true;
  String? _error;
  List<JsonMap> _apps = const [];
  List<JsonMap> _plans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final svc = DeveloperService.instance;
    final results =
        await Future.wait([svc.fetchApps(), svc.fetchPlans()]);
    if (!mounted) return;

    final appsRes = results[0];
    final plansRes = results[1];
    if (!appsRes.isSuccess && !plansRes.isSuccess) {
      setState(() {
        _loading = false;
        _error = appsRes.error?.message ??
            'Could not reach the developer API. Try again.';
      });
      return;
    }

    final plansPayload = plansRes.data;
    final enabled = plansPayload?['enabled'];
    setState(() {
      _apps = DeveloperService.mapList(appsRes.data, ['apps', 'items']);
      _plans = DeveloperService.mapList(plansPayload, ['plans', 'items']);
      _portalEnabled =
          enabled == null || enabled == true || enabled == 1 || enabled == '1';
      _loading = false;
    });
  }

  Future<void> _createApp() async {
    final created = await DeveloperAppSheet.show(context);
    if (created) _load();
  }

  Future<void> _subscribe(JsonMap plan) async {
    final planHash = plan['hash']?.toString() ?? plan['id']?.toString() ?? '';
    final res =
        await DeveloperService.instance.subscribe(planHash: planHash);
    if (!mounted) return;
    final link =
        res.isSuccess && res.data != null ? DeveloperService.extractPaymentLink(res.data!) : null;
    if (link == null || link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No payment link received. Contact support.')),
      );
      return;
    }
    await launchUrl(Uri.parse(link), mode: LaunchMode.inAppWebView);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Developer API'),
        backgroundColor: Colors.black,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : !_portalEnabled
                  ? const _InfoView(
                      icon: Icons.code_off,
                      title: 'Developer portal is not enabled',
                      subtitle:
                          'The public API program is not open yet. Check back later.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 24),
                          _buildAppsSection(),
                          const SizedBox(height: 24),
                          _buildPlansSection(),
                        ],
                      ),
                    ),
      floatingActionButton: _loading || _error != null || !_portalEnabled
          ? null
          : FloatingActionButton.extended(
              onPressed: _createApp,
              icon: const Icon(Icons.add),
              label: const Text('New app'),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.teal.withValues(alpha: 0.25),
            Colors.blue.withValues(alpha: 0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.api, color: Colors.tealAccent),
            SizedBox(width: 8),
            Text('HiTune for Developers',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Text(
            'Play HiTune tracks inside your own website or app. Create an app, '
            'copy your API key, and embed our player or call the REST API.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildAppsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Your apps'),
        const SizedBox(height: 10),
        if (_apps.isEmpty)
          _InfoCard(
            icon: Icons.apps_outlined,
            text: 'No apps yet — tap "New app" to get your API keys.',
          )
        else
          ..._apps.map(_buildAppCard),
      ],
    );
  }

  Widget _buildAppCard(JsonMap app) {
    final name = DeveloperService.strOf(app, ['name', 'title'], 'App');
    final status =
        DeveloperService.strOf(app, ['status'], 'active').toLowerCase();
    final plan = DeveloperService.strOf(app, ['plan', 'plan_name'], 'sandbox');
    final clientId =
        DeveloperService.strOf(app, ['client_id', 'api_key'], '—');
    final statusColor = switch (status) {
      'active' => Colors.greenAccent,
      'pending' => Colors.orangeAccent,
      _ => Colors.redAccent,
    };
    return Card(
      color: Colors.white.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.widgets_outlined, color: Colors.tealAccent),
        title: Text(name, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          clientId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontFamily: 'monospace',
              fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(status,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            Text(plan,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
          ],
        ),
        onTap: () => _openAppDetail(app),
      ),
    );
  }

  Future<void> _openAppDetail(JsonMap app) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141418),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AppDetailSheet(app: app),
    );
    if (changed == true) _load();
  }

  Widget _buildPlansSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('API plans'),
        const SizedBox(height: 10),
        if (_plans.isEmpty)
          const _InfoCard(
            icon: Icons.workspace_premium_outlined,
            text: 'Plan catalogue is empty for now.',
          )
        else
          ..._plans.map(_buildPlanCard),
      ],
    );
  }

  Widget _buildPlanCard(JsonMap plan) {
    final name = DeveloperService.strOf(plan, ['name', 'title'], 'Plan');
    final hash =
        DeveloperService.strOf(plan, ['hash', 'id']);
    final comment = DeveloperService.strOf(plan, ['comment', 'description']);
    final quota =
        DeveloperService.strOf(plan, ['quota', 'monthly_requests']);
    final rate =
        DeveloperService.strOf(plan, ['rate_limit', 'requests_per_minute']);

    final prices = plan['prices'];
    final period = plan['period_first']?.toString() ?? 'monthly';
    String priceText = 'Custom';
    if (prices is Map) {
      final fin = prices['final'];
      final raw =
          (fin is Map ? fin[period] : null) ?? prices['min'];
      final parsed = num.tryParse(raw?.toString() ?? '');
      if (parsed != null) {
        priceText = parsed == 0
            ? 'Free'
            : (parsed == parsed.truncateToDouble()
                ? parsed.toStringAsFixed(0)
                : parsed.toStringAsFixed(2));
      } else if (raw != null) {
        priceText = raw.toString();
      }
    } else {
      final p = plan['price'];
      final parsed = num.tryParse(p?.toString() ?? '');
      if (parsed != null) {
        priceText = parsed == 0 ? 'Free' : parsed.toString();
      }
    }

    final features = plan['features'];
    final featureList =
        features is List ? features.map((e) => e.toString()).toList() : <String>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ),
              Text(priceText,
                  style: const TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(comment,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13)),
          ],
          const SizedBox(height: 10),
          if (quota.isNotEmpty)
            _planLine(Icons.all_inclusive,
                quota == 'unlimited' ? 'Unlimited requests' : '$quota requests / month'),
          if (rate.isNotEmpty)
            _planLine(Icons.speed, '$rate requests / min'),
          ...featureList.map((f) => _planLine(Icons.check_circle_outline, f)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: hash.isEmpty ? null : () => _subscribe(plan),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.tealAccent,
                side: BorderSide(
                    color: Colors.tealAccent.withValues(alpha: 0.5)),
              ),
              child: const Text('Choose plan'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planLine(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 16, color: Colors.tealAccent.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13)),
          ),
        ]),
      );

  Widget _sectionTitle(String t) => Text(t,
      style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 15,
          fontWeight: FontWeight.w800));
}

class _AppDetailSheet extends StatefulWidget {
  final JsonMap app;
  const _AppDetailSheet({required this.app});

  @override
  State<_AppDetailSheet> createState() => _AppDetailSheetState();
}

class _AppDetailSheetState extends State<_AppDetailSheet> {
  bool _usageLoading = true;
  JsonMap? _usage;
  bool _busy = false;

  String get _hash =>
      DeveloperService.strOf(widget.app, ['hash', 'id']);

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    final res = await DeveloperService.instance.fetchUsage(_hash);
    if (!mounted) return;
    setState(() {
      _usageLoading = false;
      if (res.isSuccess) _usage = res.data;
    });
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  Future<void> _regenerate(String which) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B22),
        title: const Text('Regenerate key?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'The old key stops working immediately. Apps using it must be updated.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Regenerate', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    final res = await DeveloperService.instance
        .regenerateKey(hash: _hash, which: which);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.isSuccess || res.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error?.message ?? 'Regenerate failed')),
      );
      return;
    }
    final secret = DeveloperService.strOf(
        res.data!, ['client_secret', 'secret', 'api_secret']);
    if (secret.isNotEmpty) {
      await DeveloperAppSheet.showClientSecretDialog(context, secret);
    } else {
      final pub = DeveloperService.strOf(
          res.data!, ['publishable_key', 'api_key', 'public_key']);
      if (pub.isNotEmpty) _copy('Publishable key', pub);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Key regenerated')),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B22),
        title:
            const Text('Delete app?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'All its API keys stop working. This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    final res = await DeveloperService.instance.deleteApp(_hash);
    if (!mounted) return;
    if (res.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error?.message ?? 'Delete failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final name = DeveloperService.strOf(app, ['name', 'title'], 'App');
    final clientId = DeveloperService.strOf(app, ['client_id', 'api_key']);
    final pubKey =
        DeveloperService.strOf(app, ['publishable_key', 'public_key']);
    final website = DeveloperService.strOf(app, ['website', 'url']);
    final platform = DeveloperService.strOf(app, ['platform'], 'web');

    final quota = _usage?['quota'];
    final used = num.tryParse(
            (quota is Map ? quota['used'] : null)?.toString() ?? '') ??
        0;
    final limit = num.tryParse(
            (quota is Map ? quota['limit'] : null)?.toString() ?? '') ??
        0;
    final progress = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('$platform${website.isNotEmpty ? ' · $website' : ''}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13)),
            const SizedBox(height: 16),
            _keyRow('Client ID', clientId),
            if (pubKey.isNotEmpty) _keyRow('Publishable key', pubKey),
            const SizedBox(height: 16),
            if (_usageLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (limit > 0) ...[
              Text('Monthly quota: $used / $limit requests',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13)),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                color: progress > 0.9 ? Colors.redAccent : Colors.tealAccent,
              ),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _regenerate('publishable'),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('New public key'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _regenerate('secret'),
                  icon: const Icon(Icons.vpn_key_outlined, size: 18),
                  label: const Text('New secret'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _delete,
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.redAccent),
                  label: const Text('Delete',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _copy(label, value),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.tealAccent,
                            fontFamily: 'monospace',
                            fontSize: 13)),
                  ),
                  Icon(Icons.copy,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.4)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65), fontSize: 13)),
        ),
      ]),
    );
  }
}

class _InfoView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoView(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 56, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: Colors.redAccent.withValues(alpha: 0.8)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
          ),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
