// Checks client_config for payment/gateway related settings.
// Run: dart tool/config_pay_probe.dart
import 'dart:io';

import 'api_smoke.dart' as smoke;

Future<void> main() async {
  final env = <String, String>{};
  for (final line in await File('.env').readAsLines()) {
    final i = line.indexOf('=');
    if (i > 0) env[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  final client = HttpClient();
  final r = await smoke.call(client, 'https://music.hitune.in/api/',
      env['HITUNE_SIGN_KEY']!, 'client_config', {});
  final body = r['body'];
  if (body is Map) {
    void walk(Object? o, String path) {
      if (o is Map) {
        o.forEach((k, v) {
          final kp = '$path.$k';
          final kl = k.toString().toLowerCase();
          if (kl.contains('pay') ||
              kl.contains('gateway') ||
              kl.contains('stripe') ||
              kl.contains('razor') ||
              kl.contains('money') ||
              kl.contains('currency') ||
              kl.contains('iap') ||
              kl.contains('wallet')) {
            stdout.writeln('$kp = ${v.toString().length > 120 ? '${v.toString().substring(0, 120)}...' : v}');
          }
          if (v is Map || v is List) walk(v, kp);
        });
      } else if (o is List) {
        for (var i = 0; i < o.length && i < 50; i++) {
          walk(o[i], '$path[$i]');
        }
      }
    }

    walk(body, 'root');
    final pages = body['pages'];
    if (pages is Map) {
      stdout.writeln('\n--- pages.user_pay ---');
      stdout.writeln(pages['user_pay']);
      stdout.writeln('\n--- pages keys containing pay/sub/purchase ---');
      for (final k in pages.keys) {
        if (k.toString().contains(RegExp('pay|subs|purchase|wallet|premium'))) {
          stdout.writeln('  $k');
        }
      }
    }
  }
  exit(0);
}
