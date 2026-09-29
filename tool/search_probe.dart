// One-off probe: dump real `search` endpoint structure for all types.
// Run: dart tool/search_probe.dart
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
    decoded = {'_raw': text.length > 400 ? text.substring(0, 400) : text};
  }
  return {'_status': res.statusCode, 'body': decoded};
}

void dumpItems(String label, dynamic widgetNode) {
  stdout.writeln('=== $label');
  if (widgetNode is! Map) {
    stdout.writeln('  (not a map: ${widgetNode.runtimeType})');
    return;
  }
  stdout.writeln('  display: ${const JsonEncoder().convert(widgetNode['display'])}');
  final itemsNode = widgetNode['items'];
  final items = <Map>[];
  if (itemsNode is List) {
    items.addAll(itemsNode.whereType<Map>());
  } else if (itemsNode is Map) {
    for (final v in itemsNode.values) {
      if (v is List) items.addAll(v.whereType<Map>());
    }
  }
  stdout.writeln('  items: ${items.length}');
  for (int i = 0; i < items.length && i < 2; i++) {
    var js = const JsonEncoder().convert(items[i]);
    if (js.length > 1500) js = '${js.substring(0, 1500)}…';
    stdout.writeln('  item[$i]: $js');
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

  for (final q in ['arijit singh', 'kishore', 'arijit']) {
    final r = await call(client, base, signKey, 'search',
        {'query': q, 'page': '2', 'ot': 'all'});
    stdout.writeln('##### query="$q" status=${r['_status']}');
    final body = r['body'];
    if (body is! Map) {
      stdout.writeln('  body: $body\n');
      continue;
    }
    stdout.writeln('  top keys: ${body.keys.toList()}');
    final w = body['widgets'];
    if (w is Map) {
      for (final e in w.entries) {
        dumpItems('widget[${e.key}]', e.value);
      }
    } else if (w is List) {
      for (int i = 0; i < w.length; i++) {
        dumpItems('widget[$i]', w[i]);
      }
    } else {
      stdout.writeln('  widgets: ${w.runtimeType}');
    }
    stdout.writeln('');
  }

  // Verify a search-result track hash resolves via muse_request_source
  final src = await call(client, base, signKey, 'muse_request_source', {
    'object_type': 'm_track',
    'object_hash': 'cdeb1ff804f049b4c2b972b07f2ec103',
    'type': 'audio_quality_8',
    'solve': 'false',
  });
  var js = const JsonEncoder().convert(src['body']);
  if (js.length > 1200) js = '${js.substring(0, 1200)}…';
  stdout.writeln('##### muse_request_source status=${src['_status']}\n$js');

  client.close();
}
