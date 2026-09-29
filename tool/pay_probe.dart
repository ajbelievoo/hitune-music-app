// Probes payment endpoints to see their real response shape (guest session).
// Run: dart tool/pay_probe.dart
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

  smoke.show('user_pay_ini (guest)',
      await smoke.call(client, base, signKey, 'user_pay_ini', {}));
  smoke.show(
      'user_pay_get_link (guest)',
      await smoke.call(client, base, signKey, 'user_pay_get_link',
          {'gateway': 'paypal', 'amount': '10'}));
  smoke.show(
      'purchase_subs_plan (guest)',
      await smoke.call(client, base, signKey, 'purchase_subs_plan',
          {'hash': 'x', 'period': 'month'}));
  // guess alternates
  smoke.show('pay_ini (guest)',
      await smoke.call(client, base, signKey, 'pay_ini', {}));
  smoke.show('user_pay (guest)',
      await smoke.call(client, base, signKey, 'user_pay', {}));
  smoke.show('wallet (guest)',
      await smoke.call(client, base, signKey, 'user_edit?tab=wallet', {}));
  exit(0);
}
