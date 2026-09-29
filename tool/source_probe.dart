// Probe muse_request_source source structure (audio vs video entries).
import 'dart:convert';
import 'dart:io';

import 'api_smoke.dart' show call;

Future<void> main(List<String> args) async {
  final env = <String, String>{};
  for (final line in await File('.env').readAsLines()) {
    final i = line.indexOf('=');
    if (i > 0) env[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  final signKey = env['HITUNE_SIGN_KEY'] ?? '';
  const base = 'https://music.hitune.in/api/';
  final client = HttpClient();

  // hash from args, else find one from home
  String? hash = args.isNotEmpty ? args.first : null;
  if (hash == null) {
    final home = await call(client, base, signKey, 'bofClient/single/page/?slug=home', {});
    final hw = home['body']?['widgets'];
    if (hw is List) {
      for (final w in hw) {
        final items = w is Map ? w['items'] : null;
        final list = items is List
            ? items
            : (items is Map ? items.values.whereType<List>().expand((e) => e).toList() : null);
        if (list == null) continue;
        for (final it in list) {
          if (it is Map && (it['ot'] == 'm_track' || it['object_type'] == 'm_track')) {
            hash = (it['hash'] ?? it['object_hash'])?.toString();
            break;
          }
        }
        if (hash != null) break;
      }
    }
  }
  stdout.writeln('hash=$hash');
  if (hash == null) return;

  final src = await call(client, base, signKey, 'muse_request_source', {
    'object_type': 'm_track',
    'object_hash': hash,
  });
  final body = src['body'];
  if (body is! Map) {
    stdout.writeln('non-map: $body');
    return;
  }
  stdout.writeln('top keys: ${body.keys.toList()}');
  final sources = body['sources'];
  if (sources is List) {
    for (var i = 0; i < sources.length; i++) {
      final s = sources[i];
      if (s is! Map) continue;
      stdout.writeln('--- source[$i] keys: ${s.keys.toList()}');
      for (final k in s.keys) {
        if (k == 'data' || k == 'buttons') continue;
        var v = const JsonEncoder().convert(s[k]);
        if (v.length > 800) v = '${v.substring(0, 800)}…';
        stdout.writeln('  $k: $v');
      }
      final data = s['data'];
      if (data is Map) {
        stdout.writeln('  data.duration: ${data['duration']}  data.preview: ${const JsonEncoder().convert(data['preview']).substring(0, 300)}');
      }
    }
  }
  // Also check top-level preview/clip fields
  for (final k in ['preview', 'clip', 'video', 'trailer']) {
    if (body.containsKey(k)) {
      var v = const JsonEncoder().convert(body[k]);
      if (v.length > 500) v = '${v.substring(0, 500)}…';
      stdout.writeln('top-level $k: $v');
    }
  }

  // search for video object type — does backend have m_video clips?
  for (final ot in ['m_video', 'm_clip', 'm_reel', 'video']) {
    final r = await call(client, base, signKey, 'search', {'query': 'sonu', 'page': '2', 'ot': ot});
    final w = r['body']?['widgets'];
    var count = 'n/a';
    if (w is Map) {
      count = '0';
      for (final e in w.entries) {
        final items = e.value is Map ? (e.value as Map)['items'] : null;
        if (items is Map) count = '${items.values.whereType<List>().fold<int>(0, (a, l) => a + l.length)} groups=${w.keys.toList()}';
        if (items is List) count = '${items.length} groups=${w.keys.toList()}';
      }
    }
    stdout.writeln('search ot=$ot -> $count');
  }

  client.close();
}
