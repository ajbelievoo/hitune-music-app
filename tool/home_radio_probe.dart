// Probe: radios + home widget item shape + album page.
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

Future<Map<String, dynamic>> call(HttpClient client, String signKey,
    String endpoint, Map<String, String> data) async {
  final clean = <String, String>{...data};
  if (clean.isEmpty) clean['bof_ping'] = '1';
  final keys = clean.keys.toList()..sort();
  final sorted = {for (final k in keys) k: clean[k]!};
  final sig = sign(sorted, signKey);
  final body = buildQuery({...sorted, 'bof_signature': sig});

  final req = await client.postUrl(
      Uri.parse('https://music.hitune.in/api/$endpoint'));
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

void dump(String label, Object? v, {int maxLen = 900}) {
  var js = const JsonEncoder.withIndent(' ').convert(v);
  if (js.length > maxLen) js = '${js.substring(0, maxLen)}…';
  stdout.writeln('=== $label\n$js\n');
}

Future<void> main() async {
  final env = <String, String>{};
  for (final line in await File('.env').readAsLines()) {
    final i = line.indexOf('=');
    if (i > 0) env[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  final signKey = env['HITUNE_SIGN_KEY'] ?? '';
  if (signKey.isEmpty) {
    stderr.writeln('HITUNE_SIGN_KEY missing');
    exit(1);
  }
  final client = HttpClient();

  // 1) radios endpoint — actual item keys
  final radios = await call(client, signKey, 'radios', {});
  stdout.writeln('radios status=${radios['_status']}');
  final rbody = radios['body'];
  if (rbody is Map) {
    stdout.writeln('radios top keys: ${rbody.keys.toList()}');
    final items = rbody['items'] ?? rbody['radios'] ?? rbody['data'];
    if (items is List && items.isNotEmpty) {
      dump('radio item[0]', items.first, maxLen: 2000);
      stdout.writeln('radio count: ${items.length}');
    } else {
      dump('radios body', rbody, maxLen: 2000);
    }
  }

  // 2) home widgets — every widget: id, title, item count, first item keys
  final home = await call(client, signKey, 'bofClient/single/page/?slug=home', {});
  final widgets = home['body']?['widgets'];
  stdout.writeln('home widgets type: ${widgets.runtimeType}');
  final wList = widgets is List ? widgets : (widgets is Map ? widgets.values.toList() : const []);
  stdout.writeln('widget count: ${wList.length}');
  for (final w in wList) {
    if (w is! Map) continue;
    final display = w['display'];
    final title = display is Map ? display['title'] : display;
    final otype = display is Map ? display['o_type'] : null;
    stdout.writeln('widget id=${w['ID']} type=${w['widget_type']} o_type=$otype title=$title link=${display is Map ? display['link'] : ''}');
    final items = w['items'];
    stdout.writeln('  items type=${items.runtimeType} len=${items is List ? items.length : items is Map ? items.length : '-'}');
    if (items is List && items.isNotEmpty && items.first is Map) {
      stdout.writeln('  item[0] keys: ${(items.first as Map).keys.toList()}');
      stdout.writeln('  item[0] cover=${items.first['cover']} ot=${items.first['ot'] ?? items.first['object_type']}');
    } else if (items is Map) {
      for (final e in items.entries.take(1)) {
        stdout.writeln('  items.${e.key} type=${e.value.runtimeType}');
        if (e.value is List && (e.value as List).isNotEmpty && e.value.first is Map) {
          stdout.writeln('    first keys: ${(e.value.first as Map).keys.toList()}');
        }
      }
    }
  }

  // 3) first m_track home item fully — check cover field format
  for (final w in wList) {
    if (w is! Map) continue;
    final items = w['items'];
    final list = items is List
        ? items
        : items is Map
            ? items.values.expand((v) => v is List ? v : const []).toList()
            : const [];
    for (final it in list) {
      if (it is Map && (it['ot'] ?? it['object_type']) == 'm_track') {
        dump('m_track item', it, maxLen: 2500);
        break;
      }
    }
    break;
  }

  // 4) album page (m_album single) — slug-based
  // find an album link from home items first
  String? albumSlug;
  for (final w in wList) {
    if (w is! Map) continue;
    final items = w['items'];
    final list = items is List
        ? items
        : items is Map
            ? items.values.expand((v) => v is List ? v : const []).toList()
            : const [];
    for (final it in list) {
      if (it is Map && (it['ot'] ?? it['object_type']) == 'm_album') {
        final link = (it['link'] ?? it['url'] ?? '').toString();
        albumSlug = link.contains('/') ? link.split('/').last : null;
        stdout.writeln('found album: ${it['title']} link=$link slug=$albumSlug');
      }
      if (albumSlug != null) break;
    }
    if (albumSlug != null) break;
  }
  if (albumSlug != null) {
    final album = await call(client, signKey, 'bofClient/single/m_album/?slug=$albumSlug', {});
    stdout.writeln('album status=${album['_status']}');
    final abody = album['body'];
    if (abody is Map) {
      stdout.writeln('album keys: ${abody.keys.toList()}');
      final data = abody['data'];
      if (data is Map) {
        stdout.writeln('album.data keys: ${data.keys.toList()}');
        dump('album.data head', {
          'title': data['title'],
          'cover': data['cover'],
          'background': data['background'],
          'art': data['art'],
          'tracks_type': data['tracks']?.runtimeType,
        }, maxLen: 2500);
      }
      final aw = abody['widgets'];
      if (aw is Map) stdout.writeln('album widgets keys: ${aw.keys.toList()}');
      if (aw is List) stdout.writeln('album widgets len: ${aw.length}');
    }
  }

  // 5) "See all" -> actual endpoint used by CollectionService.fetchListWidget
  final list = await call(client, signKey, 'bofClient/list/dd91883e52/?page=1', {});
  stdout.writeln('bofClient/list status=${list['_status']}');
  dump('list body', list['body'], maxLen: 1200);

  // 6) widget[0] (New) display.type + recommendations/daily_mix shapes
  if (wList.isNotEmpty && wList.first is Map) {
    dump('widget[0].display', (wList.first as Map)['display'], maxLen: 1200);
    final items0 = (wList.first as Map)['items'];
    if (items0 is Map) {
      final l1 = items0['1'];
      if (l1 is List && l1.isNotEmpty) dump('widget[0] item[0]', l1.first, maxLen: 1500);
    }
  }
  for (final ep in ['recommendations', 'daily_mix', 'recommendations_because']) {
    final r = await call(client, signKey, ep, {});
    stdout.writeln('$ep status=${r['_status']}');
    final b = r['body'];
    if (b is Map) {
      stdout.writeln('  keys: ${b.keys.toList()}');
      for (final k in ['items', 'mixes', 'data', 'recommendations']) {
        final v = b[k];
        if (v is List && v.isNotEmpty) {
          stdout.writeln('  $k len=${v.length} first keys=${(v.first is Map ? (v.first as Map).keys.toList() : v.first.runtimeType)}');
        }
      }
    }
  }

  // 7) album page widgets — where are the tracks?
  if (albumSlug != null) {
    final album = await call(client, signKey, 'bofClient/single/m_album/?slug=$albumSlug', {});
    final aw = (album['body'] as Map)?['widgets'];
    final awList = aw is List ? aw : (aw is Map ? aw.values.toList() : const []);
    for (final w in awList) {
      if (w is! Map) continue;
      final display = w['display'];
      stdout.writeln('album widget id=${w['ID']} type=${display is Map ? display['type'] : null} o_type=${display is Map ? display['o_type'] : null} title=${display is Map ? display['title'] : null} link=${display is Map ? display['link'] : null}');
      final items = w['items'];
      stdout.writeln('  items type=${items.runtimeType} len=${items is List ? items.length : items is Map ? items.length : '-'}');
      if (items is List && items.isNotEmpty && items.first is Map) {
        stdout.writeln('  item keys: ${(items.first as Map).keys.toList()}');
      }
      if (items is Map) {
        for (final e in items.entries.take(1)) {
          if (e.value is List && (e.value as List).isNotEmpty && e.value.first is Map) {
            stdout.writeln('  items.${e.key}[0] keys: ${(e.value.first as Map).keys.toList()}');
          }
        }
      }
    }
  }

  // 8) does m_album accept ?hash= (collection service uses this)?
  final byHash = await call(client, signKey, 'bofClient/single/m_album/?hash=a707a165a34037a082c2960fd1c83568', {});
  stdout.writeln('m_album?hash status=${byHash['_status']}');
  final bh = byHash['body'];
  if (bh is Map) {
    stdout.writeln('  keys: ${bh.keys.toList()}');
    final bw = bh['widgets'];
    final bwList = bw is List ? bw : (bw is Map ? bw.values.toList() : const []);
    for (final w in bwList) {
      if (w is! Map) continue;
      final items = w['items'];
      stdout.writeln('  widget ${w['ID']}: items ${items is List ? items.length : items is Map ? 'map:${items.length}' : items}');
    }
  }

  client.close();
}
// appended probe part 2 — run via main2
