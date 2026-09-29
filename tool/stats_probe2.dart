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
  for (final slug in args.isNotEmpty ? args : ['maher_zain']) {
    final res = await call(client, base, signKey,
        'bofClient/single/m_artist/?slug=$slug', {});
    final body = res['body'];
    final data = body is Map ? body['data'] : null;
    if (data is! Map) {
      stdout.writeln('no data');
      continue;
    }
    stdout.writeln('=== $slug');
    stdout.writeln('before_stats: ${jsonEncode(data['before_stats'])}');
    stdout.writeln('subscribed: ${jsonEncode(data['subscribed'])}');
    stdout.writeln('head_play_title: ${jsonEncode(data['head_play_title'])}');
    // search whole payload for follower-ish keys
    final raw = jsonEncode(data);
    for (final m in RegExp(r'"[a-z_]*(?:sub|follow|like)[a-z_]*"\s*:\s*[^,}\]]{1,60}').allMatches(raw)) {
      stdout.writeln('match: ${m.group(0)}');
    }
  }
  client.close();
}
