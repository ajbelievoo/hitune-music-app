// Measures raw byte sizes of the app's most-fetched API payloads.
// Run: dart tool/payload_size_probe.dart
import 'dart:convert';
import 'dart:io';

import 'api_smoke.dart' as smoke;

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

  for (final ep in [
    'bofClient/single/page/?slug=home',
    'recommendations',
    'daily_mix',
    'recommendations_because',
    'client_config',
    'user_subs',
    'radios',
  ]) {
    try {
      final sw = Stopwatch()..start();
      final res = await smoke.call(client, base, signKey, ep, {});
      sw.stop();
      final bytes = utf8.encode(json.encode(res['body'])).length;
      stdout.writeln(
          '$ep -> ${(bytes / 1024).toStringAsFixed(1)} KB in ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      stdout.writeln('$ep -> ERROR $e');
    }
  }
  exit(0);
}
