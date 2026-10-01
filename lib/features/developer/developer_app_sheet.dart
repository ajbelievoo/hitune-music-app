import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'developer_service.dart';

/// Bottom sheet to register a new developer app. On success the backend
/// returns `client_secret` exactly once — it is revealed in a follow-up
/// dialog and never stored.
class DeveloperAppSheet extends StatefulWidget {
  const DeveloperAppSheet({super.key});

  /// Returns true when an app was created (caller should refresh).
  static Future<bool> show(BuildContext context) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141418),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const DeveloperAppSheet(),
    );
    return created ?? false;
  }

  /// One-time reveal dialog for a freshly issued `client_secret` (app create
  /// or key regenerate). Public so the app-detail sheet can reuse it.
  static Future<void> showClientSecretDialog(
      BuildContext context, String secret) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B22),
        title: const Text('Your client secret',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Copy this now — it will not be shown again.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                secret,
                style: const TextStyle(
                  color: Colors.tealAccent,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: secret));
              Navigator.of(ctx).pop();
            },
            child: const Text('Copy & close'),
          ),
        ],
      ),
    );
  }

  @override
  State<DeveloperAppSheet> createState() => _DeveloperAppSheetState();
}

class _DeveloperAppSheetState extends State<DeveloperAppSheet> {
  final _nameCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  String _platform = 'web';
  bool _saving = false;
  String? _error;

  static const _platforms = ['web', 'android', 'ios', 'server'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'App name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await DeveloperService.instance.createApp(
      name: name,
      website: _websiteCtrl.text.trim(),
      platform: _platform,
    );
    if (!mounted) return;
    if (!res.isSuccess || res.data == null) {
      setState(() {
        _saving = false;
        _error = res.error?.message ?? 'Could not create app. Try again.';
      });
      return;
    }
    final data = res.data!;
    final secret =
        DeveloperService.strOf(data, ['client_secret', 'secret', 'api_secret']);
    Navigator.of(context).pop(true);
    if (secret.isNotEmpty) {
      await DeveloperAppSheet.showClientSecretDialog(context, secret);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New developer app',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDeco('App name', hint: 'My website player'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _websiteCtrl,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.url,
            decoration:
                _fieldDeco('Website / bundle id', hint: 'https://mysite.com'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _platform,
            dropdownColor: const Color(0xFF1B1B22),
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDeco('Platform'),
            items: _platforms
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => setState(() => _platform = v ?? 'web'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create app'),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.tealAccent),
        ),
      );
}
