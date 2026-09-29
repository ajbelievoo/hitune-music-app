// Probe what cover payloads the recommendation endpoints actually return.
// Run: dart tool/cover_probe.dart
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
    String endpoint, Map<String, String> data) async {
  final clean = <String, String>{...data};
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
  req.write(body);
  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();
  dynamic decoded;
  try {
    decoded = json.decode(text);
  } catch (_) {
    decoded = {'_raw': text.length > 300 ? text.substring(0, 300) : text};
  }
  return {'_status': res.statusCode, 'body': decoded};
}

void dumpItems(String label, Map<String, dynamic> r) {
  stdout.writeln('=== $label -> ${r['_status']}');
  final body = r['body'];
  if (body is! Map) {
    stdout.writeln('  non-map: $body');
    return;
  }
  for (final key in ['items', 'mixes', 'recommendations', 'data']) {
    final v = body[key];
    if (v is List && v.isNotEmpty) {
      stdout.writeln('  $key: ${v.length} items');
      for (var i = 0; i < v.length && i < 3; i++) {
        final it = v[i];
        if (it is Map) {
          stdout.writeln('  [$i] keys: ${it.keys.toList()}');
          stdout.writeln('      title: ${it['title']}');
          stdout.writeln('      cover: ${it['cover']}');
          stdout.writeln('      cover_url: ${it['cover_url']}');
          stdout.writeln('      image: ${it['image']}');
          stdout.writeln('      image_thumb: ${it['image_thumb']}');
          stdout.writeln('      thumb: ${it['thumb']}');
        }
      }
    }
  }
  stdout.writeln('');
}

Future<void> main() async {
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

  dumpItems('daily_mix', await call(client, base, signKey, 'daily_mix', {}));
  dumpItems('recommendations', await call(client, base, signKey, 'recommendations', {}));
  dumpItems('recommendations_because', await call(client, base, signKey, 'recommendations_because', {}));

  client.close();
}
