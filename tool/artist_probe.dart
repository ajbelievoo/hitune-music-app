// Probe: artist page widgets + a track's muse_request_source payload.
// Run: dart tool/artist_probe.dart
import 'dart:convert';
import 'dart:io';

import 'api_smoke.dart' show call;

Future<void> main() async {
  final env = <String, String>{};
  for (final line in await File('.env').readAsLines()) {
    final i = line.indexOf('=');
    if (i > 0) env[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  final signKey = env['HITUNE_SIGN_KEY'] ?? '';
  const base = 'https://music.hitune.in/api/';
  final client = HttpClient();

  String js(Object? o, [int max = 900]) {
    var s = const JsonEncoder().convert(o);
    return s.length > max ? '${s.substring(0, max)}…' : s;
  }

  // 1) Artist page — widget list + first item of each
  final artist = await call(client, base, signKey, 'bofClient/single/m_artist/?slug=sonu_nigam', {});
  final body = artist['body'];
  stdout.writeln('=== artist status=${artist['_status']} top keys: ${body is Map ? body.keys.toList() : body}');
  final widgets = body is Map ? body['widgets'] : null;
  if (widgets is List) {
    for (final w in widgets) {
      if (w is! Map) continue;
      final display = w['display'] is Map ? (w['display'] as Map)['title'] : null;
      stdout.writeln('widget ${w['ID']} title=$display o_type=${w['display'] is Map ? (w['display'] as Map)['o_type'] : null}');
      final items = w['items'];
      if (items is List && items.isNotEmpty) {
        stdout.writeln('  items=${items.length} first keys=${(items.first as Map).keys.toList()}');
        stdout.writeln('  first: ${js(items.first, 600)}');
      } else if (items is Map) {
        stdout.writeln('  items=Map keys=${items.keys.toList()}');
        final firstPage = items.values.whereType<List>().firstOrNull;
        if (firstPage != null && firstPage.isNotEmpty) {
          stdout.writeln('  first item keys=${(firstPage.first as Map).keys.toList()}');
          stdout.writeln('  first: ${js(firstPage.first, 700)}');
        }
      }
    }
  } else if (widgets is Map) {
    for (final e in widgets.entries) {
      stdout.writeln('widget group ${e.key}: ${js(e.value, 400)}');
    }
  }

  // 2) muse_request_source for a track hash — see audio vs video sources
  // grab a track hash from home widgets first
  String? hash;
  final home = await call(client, base, signKey, 'bofClient/single/page/?slug=home', {});
  final hw = home['body']?['widgets'];
  if (hw is List) {
    for (final w in hw) {
      final items = w is Map ? w['items'] : null;
      final list = items is List ? items : (items is Map ? items.values.whereType<List>().expand((e) => e).toList() : null);
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
  stdout.writeln('\n=== track hash: $hash');
  if (hash != null) {
    final src = await call(client, base, signKey, 'muse_request_source', {
      'object_type': 'm_track',
      'object_hash': hash,
    });
    stdout.writeln(js(src['body'], 3000));
  }

  client.close();
}
