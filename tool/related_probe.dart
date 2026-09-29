// Probe: related-artist links, muse_request_source sources (preview vs full),
// and search item shapes for clip/preview markers.
// Run: dart tool/related_probe.dart
import 'dart:convert';
import 'dart:io';

import 'api_smoke.dart' show call;

String js(Object? o, [int max = 700]) {
  var s = const JsonEncoder().convert(o);
  return s.length > max ? '${s.substring(0, max)}…' : s;
}

List<dynamic> flattenItems(dynamic items) {
  if (items is List) return items;
  if (items is Map) {
    return items.values.whereType<List>().expand((e) => e).toList();
  }
  return const [];
}

Future<void> main() async {
  final env = <String, String>{};
  for (final line in await File('.env').readAsLines()) {
    final i = line.indexOf('=');
    if (i > 0) env[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  final signKey = env['HITUNE_SIGN_KEY'] ?? '';
  const base = 'https://music.hitune.in/api/';
  final client = HttpClient();

  // ---------- 1) artist page -> find related artists ----------
  final artist = await call(client, base, signKey,
      'bofClient/single/m_artist/?slug=sonu_nigam', {});
  final body = artist['body'];
  stdout.writeln('=== artist keys: ${body is Map ? body.keys.toList() : body}');
  // dump data keys (artist object) to find image fields
  if (body is Map) {
    final data = body['data'];
    if (data is Map) {
      stdout.writeln('data keys: ${data.keys.toList()}');
      for (final k in data.keys) {
        final kl = k.toString().toLowerCase();
        if (kl.contains('img') || kl.contains('image') || kl.contains('cover') ||
            kl.contains('avatar') || kl.contains('photo') || kl.contains('thumb') ||
            kl == 'title' || kl == 'name' || kl == 'hash' || kl == 'id') {
          stdout.writeln('  data.$k = ${js(data[k], 300)}');
        }
      }
    }
  }

  // find related-artist widget items
  final related = <Map>[];
  final widgets = body is Map ? body['widgets'] : null;
  if (widgets is List) {
    for (final w in widgets) {
      if (w is! Map) continue;
      final wt = (w['widget_type'] ?? w['ID'] ?? '').toString();
      for (final it in flattenItems(w['items'])) {
        if (it is Map &&
            (it['ot'] == 'm_artist' || it['object_type'] == 'm_artist' ||
                wt.contains('artist'))) {
          related.add(it);
        }
      }
    }
  }
  stdout.writeln('\n=== related artists found: ${related.length}');
  for (final it in related.take(6)) {
    stdout.writeln('item keys: ${it.keys.toList()}');
    stdout.writeln('  title=${it['title']} url=${it['url']} link=${it['link']} sub_link=${it['sub_link']} slug=${it['slug']}');
    break; // just first shape
  }

  // ---------- 2) follow each related artist link like the app does ----------
  for (final it in related.take(4)) {
    final link = (it['sub_link'] ?? it['link'] ?? it['url'] ?? it['slug'] ?? '').toString();
    final cleaned = link.startsWith('/') ? link.substring(1) : link;
    final m = RegExp(r'^music/artist/([^/?#]+)', caseSensitive: false).firstMatch(cleaned);
    final slug = m?.group(1) ?? (it['slug']?.toString() ?? '');
    stdout.writeln('\n--- link="$link" -> slug="$slug"');
    if (slug.isEmpty) continue;
    final r = await call(client, base, signKey,
        'bofClient/single/m_artist/?slug=${Uri.encodeQueryComponent(slug)}', {});
    final b = r['body'];
    var snippet = const JsonEncoder().convert(b);
    if (snippet.length > 300) snippet = '${snippet.substring(0, 300)}…';
    stdout.writeln('    status=${r['_status']} body=$snippet');
  }

  // also try the exact url form without slug param
  if (related.isNotEmpty) {
    final it = related.first;
    final url = (it['url'] ?? '').toString();
    if (url.isNotEmpty) {
      final r = await call(client, base, signKey,
          'bofClient/single/m_artist/?slug=${Uri.encodeQueryComponent(url)}', {});
      var snippet = const JsonEncoder().convert(r['body']);
      if (snippet.length > 300) snippet = '${snippet.substring(0, 300)}…';
      stdout.writeln('\n--- url-as-slug "$url" status=${r['_status']}: $snippet');
    }
  }

  // ---------- 3) muse_request_source: preview vs full ----------
  // collect a few track hashes from home + artist widgets
  final hashes = <String>[];
  for (final page in ['bofClient/single/page/?slug=home',
      'bofClient/single/m_artist/?slug=sonu_nigam']) {
    final r = await call(client, base, signKey, page, {});
    final ws = r['body'] is Map ? r['body']['widgets'] : null;
    if (ws is List) {
      for (final w in ws) {
        if (w is! Map) continue;
        for (final it in flattenItems(w['items'])) {
          if (it is Map &&
              (it['ot'] == 'm_track' || it['object_type'] == 'm_track')) {
            final h = (it['hash'] ?? it['object_hash'])?.toString();
            if (h != null && !hashes.contains(h)) hashes.add(h);
          }
        }
      }
    }
    if (hashes.length >= 4) break;
  }
  stdout.writeln('\n=== track hashes: $hashes');
  for (final h in hashes.take(3)) {
    final src = await call(client, base, signKey, 'muse_request_source', {
      'object_type': 'm_track',
      'object_hash': h,
      'type': 'audio',
      'solve': 'false',
    });
    final b = src['body'];
    stdout.writeln('\n--- source for $h status=${src['_status']}');
    final sources = b is Map ? b['sources'] : null;
    if (sources is List) {
      for (var i = 0; i < sources.length && i < 4; i++) {
        final s = sources[i];
        if (s is! Map) continue;
        stdout.writeln('  source[$i] keys=${s.keys.toList()}');
        for (final k in s.keys) {
          if (k == 'data' || k == 'buttons') continue;
          stdout.writeln('    $k = ${js(s[k], 350)}');
        }
        final d = s['data'];
        if (d is Map) {
          stdout.writeln('    data.duration=${d['duration']} preview=${js(d['preview'], 200)}');
        }
      }
    } else {
      stdout.writeln('  body: ${js(b, 500)}');
    }
  }

  // ---------- 4) search: what do clip/preview items look like ----------
  final srch = await call(client, base, signKey, 'search',
      {'query': 'a', 'page': '1'});
  final sw = srch['body'] is Map ? srch['body']['widgets'] : null;
  stdout.writeln('\n=== search widgets type: ${sw.runtimeType}');
  final seen = <String>{};
  void scanItems(dynamic node, String path) {
    if (node is Map) {
      final ot = (node['ot'] ?? node['object_type'])?.toString();
      if (ot != null) {
        final dur = node['duration'] ?? node['len'] ?? node['length'];
        final key = '$ot|dur=$dur';
        if (!seen.contains(key)) {
          seen.add(key);
          stdout.writeln('  [$path] ot=$ot dur=$dur title=${js(node['title'], 80)} keys=${node.keys.toList()}');
        }
      }
      for (final e in node.entries) {
        if (e.value is Map || e.value is List) scanItems(e.value, '$path.${e.key}');
      }
    } else if (node is List) {
      for (var i = 0; i < node.length; i++) {
        scanItems(node[i], '$path[$i]');
      }
    }
  }
  scanItems(sw, 'widgets');

  client.close();
}
