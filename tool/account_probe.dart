// Authenticated probe: sign up a throwaway user, then inspect the real
// response shapes for user_subs / user_library / playlist_create /
// user_edit (security + notifications tabs).
// Run: dart tool/account_probe.dart
import 'dart:convert';
import 'dart:io';

import 'api_smoke.dart' show call, show;

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

  final ts = DateTime.now().millisecondsSinceEpoch;
  final email = 'devin.probe.$ts@example.com';
  const password = 'Probe#Pass123';

  // ---- signup ----
  final su = await call(client, base, signKey, 'user_auth?bof=submit&do=signup', {
    'email': email,
    'username': 'devinprobe$ts',
    'password': password,
    'password_repeat': password,
    'agree': 'on',
  });
  show('signup', su, maxLen: 2000);

  String? sessId;
  String? sessKey;
  void harvest(Map<String, dynamic> r) {
    final body = r['body'];
    if (body is! Map) return;
    for (final node in [body, body['message'], body['messages']]) {
      if (node is Map) {
        sessId ??= (node['sess_id'] ?? node['sessId'] ?? node['session_id'])?.toString();
        sessKey ??= (node['sess_key'] ?? node['sessKey'] ?? node['session_key'])?.toString();
      }
      if (node is List && node.isNotEmpty && node.first is Map) {
        final m = node.first as Map;
        sessId ??= (m['sess_id'] ?? m['sessId'] ?? m['session_id'])?.toString();
        sessKey ??= (m['sess_key'] ?? m['sessKey'] ?? m['session_key'])?.toString();
      }
    }
  }

  harvest(su);

  // If signup didn't return a session, try login.
  if (sessId == null || sessKey == null || sessId!.isEmpty || sessKey!.isEmpty) {
    final li = await call(client, base, signKey, 'user_auth?bof=submit&do=login', {
      'email': email,
      'password': password,
    });
    show('login', li, maxLen: 2000);
    harvest(li);
  }

  stdout.writeln('>>> sessId=$sessId sessKey=$sessKey\n');
  if (sessId == null || sessKey == null) {
    stderr.writeln('No session — aborting');
    client.close();
    exit(2);
  }

  // ---- client_config: what type is user.plan? ----
  final cc = await call(client, base, signKey, 'client_config', {},
      sessKey: sessKey, sessId: sessId);
  final ccBody = cc['body'];
  if (ccBody is Map) {
    final msg = ccBody['message'] ?? (ccBody['messages'] is List && (ccBody['messages'] as List).isNotEmpty ? (ccBody['messages'] as List).first : null);
    if (msg is Map) {
      final user = msg['user'];
      stdout.writeln('=== client_config user keys: ${user is Map ? user.keys.toList() : user}');
      if (user is Map) {
        stdout.writeln('    user.plan = ${const JsonEncoder().convert(user['plan'])}  (${user['plan'].runtimeType})');
        for (final k in ['password', 'has_password', 'social', 'provider', 'registered_via', 'oauth', 'is_social']) {
          if (user.containsKey(k)) stdout.writeln('    user.$k = ${const JsonEncoder().convert(user[k])}');
        }
        final udata = user['data'];
        if (udata is Map) {
          for (final k in udata.keys) {
            if (k.toString().toLowerCase().contains('pass') ||
                k.toString().toLowerCase().contains('social') ||
                k.toString().toLowerCase().contains('oauth') ||
                k.toString().toLowerCase().contains('provider')) {
              stdout.writeln('    user.data.$k = ${const JsonEncoder().convert(udata[k])}');
            }
          }
        }
      }
    }
  }

  // ---- user_subs ----
  final subs = await call(client, base, signKey, 'user_subs', {},
      sessKey: sessKey, sessId: sessId);
  show('user_subs', subs, maxLen: 3000);

  // ---- user_library?tab=playlists (before) ----
  final libBefore = await call(client, base, signKey, 'user_library?tab=playlists&page=1', {},
      sessKey: sessKey, sessId: sessId);
  show('user_library playlists (before)', libBefore, maxLen: 3000);

  // ---- playlist_create ----
  final pc = await call(client, base, signKey, 'playlist_create', {
    'playlist': 'Probe Playlist $ts',
  }, sessKey: sessKey, sessId: sessId);
  show('playlist_create', pc, maxLen: 2000);

  // ---- user_library?tab=playlists (after) ----
  final libAfter = await call(client, base, signKey, 'user_library?tab=playlists&page=1', {},
      sessKey: sessKey, sessId: sessId);
  show('user_library playlists (after)', libAfter, maxLen: 4000);

  // ---- user_edit?tab=security ----
  final sec = await call(client, base, signKey, 'user_edit?tab=security', {},
      sessKey: sessKey, sessId: sessId);
  show('user_edit security', sec, maxLen: 4000);

  // ---- user_edit?tab=notifications ----
  final notif = await call(client, base, signKey, 'user_edit?tab=notifications', {},
      sessKey: sessKey, sessId: sessId);
  show('user_edit notifications', notif, maxLen: 6000);

  client.close();
}
