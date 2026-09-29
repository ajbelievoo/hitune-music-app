// Live API smoke test — replicates ApiService signing to verify the
// endpoints the Flutter client now depends on.
// Run: dart tool/api_smoke.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

String encodePhp(String input) {
  var encoded = Uri.encodeQueryComponent(input).replaceAll('%20', '+');
  return encoded
      .replaceAll('%21', '!')
      .replaceAll('%27', "'")
      .replaceAll('%28', '(')
      .replaceAll('%29', ')')
      .replaceAll('%2A', '*');
}

String buildQuery(Map<String, String> data) =>
    data.entries.map((e) => '${encodePhp(e.key)}=${encodePhp(e.value)}').join('&');

String sign(Map<String, String> data, String key) {
  final hmac = Hmac(sha256, utf8.encode(key));
  final hex = hmac.convert(utf8.encode(buildQuery(data))).toString();
  return md5.convert(utf8.encode(hex)).toString();
}

Future<Map<String, dynamic>> call(HttpClient client, String base, String signKey,
    String endpoint, Map<String, String> data,
    {String? sessKey, String? sessId}) async {
  final clean = <String, String>{...data};
  if (sessId != null) clean.putIfAbsent('sess_id', () => sessId);
  if (sessKey != null) clean.putIfAbsent('sess_key', () => sessKey);
  if (clean.isEmpty) clean['bof_ping'] = '1';

  final keys = clean.keys.toList()..sort();
  final sorted = {for (final k in keys) k: clean[k]!};
  final sig = sign(sorted, signKey);
  final body = buildQuery({...sorted, 'bof_signature': sig});

  final req = await client.postUrl(Uri.parse('$base$endpoint'));
  req.headers.set('x-bof-request-code', 'BusyOwlFrameWorkVersion201');
  req.headers.set('x-bof-platform', 'web');
  req.headers.set('x-bof-version', '2074');
  req.headers.set('x-bof-signature', sig);
  req.headers.set('content-type', 'application/x-www-form-urlencoded');
  req.headers.set('accept', 'application/json');
  if (sessKey != null) req.headers.set('x-bof-sess-key', sessKey);
  if (sessId != null) req.headers.set('cookie', 'PHPSESSID=$sessId');
  req.write(body);

  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();
  dynamic decoded;
  try {
    decoded = json.decode(text);
  } catch (_) {
    decoded = {'_raw': text.length > 400 ? text.substring(0, 400) : text};
  }
  return {'_status': res.statusCode, 'body': decoded};
}

void show(String label, Map<String, dynamic> r, {int maxLen = 1200}) {
  stdout.writeln('=== $label -> ${r['_status']}');
  var text = const JsonEncoder.withIndent('  ').convert(r['body']);
  if (text.length > maxLen) text = '${text.substring(0, maxLen)}…';
  stdout.writeln('$text\n');
}

/// Print just the top-level keys + items[0] shape of a list response.
void showShape(String label, Map<String, dynamic> r) {
  final body = r['body'];
  stdout.writeln('=== $label -> ${r['_status']}');
  if (body is! Map) {
    stdout.writeln('  (non-map body)');
    return;
  }
  stdout.writeln('  top keys: ${body.keys.toList()}');
  for (final k in ['items', 'data', 'tracks', 'albums', 'artists', 'radios', 'widgets', 'list']) {
    final v = body[k];
    if (v is List) {
      stdout.writeln('  $k: List(${v.length})');
      if (v.isNotEmpty && v.first is Map) {
        final first = v.first as Map;
        stdout.writeln('    item keys: ${first.keys.toList()}');
      }
    } else if (v is Map) {
      stdout.writeln('  $k: Map keys=${v.keys.toList()}');
    }
  }
  stdout.writeln('');
}

Future<void> main(List<String> args) async {
  final env = <String, String>{};
  for (final line in await File('.env').readAsLines()) {
    final i = line.indexOf('=');
    if (i > 0) env[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  final signKey = env['HITUNE_SIGN_KEY'] ?? '';
  if (signKey.isEmpty) {
    stderr.writeln('HITUNE_SIGN_KEY missing in .env');
    exit(1);
  }

  const base = 'https://music.hitune.in/api/';
  final client = HttpClient();

  // Inspect home page widgets — what object types do items carry?
  final home = await call(client, base, signKey, 'bofClient/single/page/?slug=home', {});
  final widgets = home['body']?['widgets'];
  if (widgets is List) {
    for (final w in widgets) {
      if (w is! Map) continue;
      stdout.writeln('widget: ${w['ID']} type=${w['widget_type']} display=${w['display'] is Map ? (w['display'] as Map)['title'] ?? w['display'] : w['display']}');
      final items = w['items'];
      if (items is List) {
        stdout.writeln('  items: ${items.length}');
        final types = <String, int>{};
        for (final it in items) {
          if (it is Map) {
            final t = (it['object_type'] ?? it['ot'] ?? '?').toString();
            types[t] = (types[t] ?? 0) + 1;
          }
        }
        stdout.writeln('  types: $types');
        if (items.isNotEmpty && items.first is Map) {
          stdout.writeln('  first item keys: ${(items.first as Map).keys.toList()}');
        }
      }
      stdout.writeln('');
    }
  }

  // Dump the first home widget fully — the 'New' widget had no `items` key
  final w0 = (widgets is List && widgets.isNotEmpty) ? widgets.first : null;
  show('home widget[0]', {'_status': 200, 'body': w0}, maxLen: 2500);

  // search(rock) widget groups — dump raw structure
  final rock = await call(client, base, signKey, 'search', {'query': 'rock', 'page': '2', 'ot': 'm_track'});
  final rw = rock['body']?['widgets'];
  if (rw is Map) {
    for (final e in rw.entries) {
      final v = e.value;
      var js = const JsonEncoder().convert(v);
      if (js.length > 700) js = '${js.substring(0, 700)}…';
      stdout.writeln('=== group ${e.key}:\n$js\n');
    }
  }

  client.close();
}
