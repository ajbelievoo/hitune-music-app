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
  final slug = args.isNotEmpty ? args.first : 'maher_zain';
  final res = await call(client, base, signKey,
      'bofClient/single/m_artist/?slug=$slug', {});
  final body = res['body'];
  final data = body is Map ? body['data'] : null;
  if (data is! Map) {
    stdout.writeln('no data: ${jsonEncode(body).substring(0, 400)}');
    return;
  }
  stdout.writeln('keys: ${data.keys.toList()}');
  stdout.writeln('stats: ${jsonEncode(data['stats'])}');
  stdout.writeln('buttons: ${jsonEncode(data['buttons'])}');
  stdout.writeln('subscribers: ${jsonEncode(data['subscribers'] ?? data['subs'])}');
  client.close();
}
