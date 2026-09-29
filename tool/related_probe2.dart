// Probe 2: dump data.related_artists item shape and follow each link the way
// the app does; also test a bogus slug's failure mode + dump search item keys.
// Run: dart tool/related_probe2.dart
import 'dart:convert';
import 'dart:io';

import 'api_smoke.dart' show call;

String js(Object? o, [int max = 700]) {
  var s = const JsonEncoder().convert(o);
  return s.length > max ? '${s.substring(0, max)}…' : s;
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

  // ---------- data.related_artists shape ----------
  final artist = await call(client, base, signKey,
      'bofClient/single/m_artist/?slug=sonu_nigam', {});
  final data = (artist['body'] as Map?)?['data'];
  if (data is Map) {
    for (final k in ['tracks', 'albums', 'related_artists']) {
      final v = data[k];
      stdout.writeln('=== data.$k type=${v.runtimeType}');
      final list = v is List ? v : (v is Map ? v.values.whereType<List>().expand((e) => e).toList() : null);
      if (list != null && list.isNotEmpty) {
        stdout.writeln('  count=${list.length} first=${js(list.first, 900)}');
      }
    }
    // background field for header image
    stdout.writeln('data.background = ${js(data['background'], 250)}');
    stdout.writeln('data.before_stats = ${js(data['before_stats'], 250)}');
  }

  // ---------- follow related artist links ----------
  final rel = data is Map ? data['related_artists'] : null;
  final relItems = rel is List ? rel : (rel is Map ? rel.values.whereType<List>().expand((e) => e).toList() : const []);
  for (final it in relItems.take(5)) {
    if (it is! Map) continue;
    final slug = (it['slug'] ?? it['artist_slug'] ?? '').toString();
    final link = (it['sub_link'] ?? it['link'] ?? it['url'] ?? '').toString();
    final cleaned = link.startsWith('/') ? link.substring(1) : link;
    final m = RegExp(r'^music/artist/([^/?#]+)', caseSensitive: false).firstMatch(cleaned);
    final appSlug = slug.isNotEmpty ? slug : (m?.group(1) ?? '');
    stdout.writeln('\n--- ${it['title']}: slug="$slug" link="$link" url=${it['url']} -> appSlug="$appSlug"');
    if (appSlug.isEmpty) {
      stdout.writeln('    (app would show "Artist link not available")');
      continue;
    }
    final r = await call(client, base, signKey,
        'bofClient/single/m_artist/?slug=${Uri.encodeQueryComponent(appSlug)}', {});
    var snippet = const JsonEncoder().convert(r['body']);
    if (snippet.length > 250) snippet = '${snippet.substring(0, 250)}…';
    stdout.writeln('    status=${r['_status']} body=$snippet');
  }

  // ---------- bogus slug failure mode ----------
  final bad = await call(client, base, signKey,
      'bofClient/single/m_artist/?slug=no_such_artist_xyz_123', {});
  stdout.writeln('\n=== bogus slug status=${bad['_status']} body=${js(bad['body'], 300)}');

  // ---------- search raw structure ----------
  final srch = await call(client, base, signKey, 'search', {'query': 'bhole', 'page': '1'});
  final sb = srch['body'];
  stdout.writeln('\n=== search top keys: ${sb is Map ? sb.keys.toList() : sb}');
  var s = const JsonEncoder().convert(sb);
  if (s.length > 3000) s = '${s.substring(0, 3000)}…';
  stdout.writeln(s);

  client.close();
}
