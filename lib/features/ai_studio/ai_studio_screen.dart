import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/cover_image_extractor.dart';

/// AI Creator Studio (strategy doc §4/§9) — karaoke vocal isolation,
/// mastering, smart lyrics sync and cover-art jobs, gated per-plan by the
/// backend's daily AI quota.
class AiStudioScreen extends StatefulWidget {
  const AiStudioScreen({super.key});

  @override
  State<AiStudioScreen> createState() => _AiStudioScreenState();
}

class _AiStudioScreenState extends State<AiStudioScreen> {
  final _api = ApiService.instance;
  final _searchCtrl = TextEditingController();
  Map<String, dynamic> _tools = {};
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;
  String? _quota;
  bool _loading = true;

  static const _toolMeta = {
    'song_gen': ('Create Song', 'Prompt se poora song banao', Icons.auto_awesome),
    'karaoke': ('Karaoke', 'Remove vocals to sing along', Icons.mic_none),
    'master': ('Mastering', 'Studio loudness & polish', Icons.graphic_eq),
    'lyrics': ('Lyrics Sync', 'Auto timecode LRC file', Icons.subtitles),
    'cover_art': ('Cover Art', 'Generate artwork from a prompt', Icons.image),
  };

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final t = await _api.postPayloadRaw(endpoint: 'ai_studio', data: {'action': 'tools'});
    final q = await _api.postPayloadRaw(endpoint: 'ai_studio', data: {'action': 'quota'});
    final l = await _api.postPayloadRaw(endpoint: 'ai_studio', data: {'action': 'list'});
    if (!mounted) return;
    setState(() {
      _tools = (t.data?['tools'] is Map) ? Map<String, dynamic>.from(t.data!['tools']) : {};
      _quota = (q.data?['quota'] is Map) ? '${q.data!['quota']['left']} left today' : null;
      _jobs = (l.data?['jobs'] is List)
          ? (l.data!['jobs'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : [];
      _loading = false;
    });
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) return;
    final res = await _api.postPayloadRaw(endpoint: 'search', data: {'query': q.trim(), 'ot': 'm_track'});
    if (!mounted) return;
    final out = <Map<String, dynamic>>[];
    final widgets = res.data?['widgets'];
    if (widgets is Map) {
      for (final g in widgets.values) {
        if (g is! Map) continue;
        final items = g['items'];
        if (items is List) {
          for (final it in items) {
            if (it is Map) out.add(Map<String, dynamic>.from(it));
          }
        }
      }
    }
    setState(() => _results = out.take(15).toList());
  }

  Future<void> _submit(String type, {String? prompt, String? title, bool? instrumental, int? seconds}) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = <String, String>{'action': 'submit', 'type': type};
    if (_selected != null) {
      final raw = _selected!['raw'];
      final id = raw is Map ? (raw['ID'] ?? _selected!['ID']) : _selected!['ID'];
      if (id != null) data['track_id'] = '$id';
      data['track_hash'] = '${_selected!['hash'] ?? _selected!['ID']}';
    }
    if (prompt != null && prompt.isNotEmpty) data['prompt'] = prompt;
    if (title != null && title.isNotEmpty) data['title'] = title;
    if (instrumental == true) data['instrumental'] = '1';
    if (seconds != null) data['seconds'] = '$seconds';
    final res = await _api.postPayloadRaw(endpoint: 'ai_studio', data: data);
    if (!mounted) return;
    if (res.isSuccess && res.data?['job'] is Map) {
      messenger.showSnackBar(const SnackBar(content: Text('Job queued')));
      _refresh();
    } else {
      final code = res.data?['error']?['code'] ?? res.error?.message ?? 'failed';
      messenger.showSnackBar(SnackBar(content: Text('Failed: $code')));
    }
  }

  Future<void> _coverPrompt() async {
    final ctrl = TextEditingController();
    final p = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Describe your cover art'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'e.g. neon city skyline, synthwave')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Generate')),
        ],
      ),
    );
    if (p != null) _submit('cover_art', prompt: p);
  }

  Future<void> _songPrompt() async {
    final pCtrl = TextEditingController();
    final tCtrl = TextEditingController();
    var instrumental = false;
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Create a song with AI'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pCtrl,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Describe your song — genre, mood, vocals...'),
              ),
              const SizedBox(height: 10),
              TextField(controller: tCtrl, decoration: const InputDecoration(hintText: 'Title (optional)')),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Instrumental only'),
                value: instrumental,
                onChanged: (v) => setD(() => instrumental = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(c, {'prompt': pCtrl.text.trim(), 'title': tCtrl.text.trim(), 'instrumental': instrumental}),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (res != null && (res['prompt'] as String).isNotEmpty) {
      _submit('song_gen', prompt: res['prompt'], title: res['title'], instrumental: res['instrumental'] as bool, seconds: 45);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Studio'),
        actions: [
          if (_quota != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text(_quota!, style: theme.textTheme.bodySmall)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // tool tiles
                  for (final e in _toolMeta.entries)
                    _toolTile(theme, e.key, e.value.$1, e.value.$2, e.value.$3),
                  const SizedBox(height: 16),
                  if (_selected != null)
                    Chip(
                      avatar: const Icon(Icons.audiotrack, size: 16),
                      label: Text('${_selected!['title'] ?? _selected!['name'] ?? 'track'}'),
                      onDeleted: () => setState(() => _selected = null),
                    ),
                  // track search (for audio tools)
                  TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Pick a track (search)...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: _search,
                  ),
                  for (final r in _results)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.music_note),
                      title: Text('${r['title'] ?? r['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${r['sub_title'] ?? r['sub_data'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      selected: identical(_selected, r),
                      onTap: () => setState(() => _selected = r),
                    ),
                  const Divider(height: 32),
                  Text('Recent jobs', style: theme.textTheme.titleSmall),
                  for (final j in _jobs) _jobTile(theme, j),
                ],
              ),
            ),
    );
  }

  Widget _toolTile(ThemeData theme, String key, String title, String sub, IconData icon) {
    final t = _tools[key];
    final enabled = t is Map && t['enabled'] == true;
    final allowed = t is! Map || t['allowed'] != false;
    final needsTrack = key != 'cover_art' && key != 'song_gen';
    final note = !enabled
        ? 'Disabled by admin'
        : (!allowed ? 'Not in your plan — upgrade' : sub);
    return Card(
      child: ListTile(
        leading: Icon(icon, color: (enabled && allowed) ? theme.colorScheme.primary : theme.disabledColor),
        title: Text(title),
        subtitle: Text(note),
        trailing: (enabled && allowed)
            ? FilledButton.tonal(
                onPressed: needsTrack && _selected == null
                    ? null
                    : () {
                        if (key == 'cover_art') _coverPrompt();
                        else if (key == 'song_gen') _songPrompt();
                        else _submit(key);
                      },
                child: const Text('Run'),
              )
            : (!allowed ? const Icon(Icons.lock_outline, size: 18) : null),
      ),
    );
  }

  Widget _jobTile(ThemeData theme, Map<String, dynamic> j) {
    final status = '${j['status']}';
    final url = j['result_url']?.toString();
    return ListTile(
      dense: true,
      leading: Icon(switch (status) {
        'done' => Icons.check_circle,
        'failed' => Icons.error_outline,
        _ => Icons.hourglass_top,
      }, color: switch (status) {
        'done' => Colors.green,
        'failed' => theme.colorScheme.error,
        _ => theme.colorScheme.primary,
      }),
      title: Text('${j['type']} · ${j['engine'] ?? ''}'),
      subtitle: Text(status == 'failed' ? '${j['error'] ?? 'failed'}' : status),
      trailing: url != null && url.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            )
          : null,
      onTap: status == 'pending' || status == 'processing' ? () => _pollJob(j['id']) : null,
    );
  }

  Future<void> _pollJob(dynamic id) async {
    try {
      final res = await _api.postPayloadRaw(endpoint: 'ai_studio', data: {'action': 'status', 'job_id': '$id'});
      if (res.isSuccess) _refresh();
    } catch (e) {
      AppLogger.d('ai job poll failed: $e');
    }
  }
}
