import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_service.dart';
import '../auth/auth_gate.dart';
import '../player/models/track.dart';
import '../player/player_service.dart';

/// Live listening parties (strategy doc §8): fans listen to the same track
/// in sync — the host controls what's playing; listeners join and follow.
/// Data: /api/htx/party (list|state|create|join|leave|set_track|end).
class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key});

  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  final _api = ApiService.instance;
  List<Map<String, dynamic>> _parties = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _api.postPayloadRaw(endpoint: 'htx/party', data: const {'action': 'list'});
    if (!mounted) return;
    final list = res.data?['parties'];
    setState(() {
      _loading = false;
      _parties = list is List
          ? list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const [];
      _error = res.isSuccess ? null : (res.error?.message ?? 'Could not load parties');
    });
  }

  Future<void> _create() async {
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to host a party.');
    if (!ok || !mounted) return;
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Host a listening party'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Party name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final res = await _api.postPayloadRaw(endpoint: 'htx/party', data: {'action': 'create', 'name': name});
    if (!mounted) return;
    if (res.isSuccess && res.data?['hash'] != null) {
      _load();
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PartyRoomScreen(hash: res.data!['hash'].toString(), isHost: true),
      ));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not create party')));
    }
  }

  Future<void> _join(Map<String, dynamic> p) async {
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to join a party.');
    if (!ok || !mounted) return;
    final hash = p['hash']?.toString() ?? '';
    final res = await _api.postPayloadRaw(endpoint: 'htx/party', data: {'action': 'join', 'hash': hash});
    if (!mounted) return;
    if (!res.isSuccess) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not join party')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PartyRoomScreen(hash: hash, isHost: false),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Listening Parties')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Host'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _parties.isEmpty
                  ? const Center(child: Text('No live parties — host the first one'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _parties.length,
                        itemBuilder: (context, i) {
                          final p = _parties[i];
                          final track = p['track'] is Map ? p['track'] as Map : null;
                          return ListTile(
                            leading: Icon(Icons.surround_sound_rounded,
                                color: theme.colorScheme.primary),
                            title: Text(p['name']?.toString() ?? 'Party',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${p['host'] ?? ''} • ${track?['title'] ?? 'Waiting for track'}'
                              '${track != null && track['artist'] != null ? ' — ${track['artist']}' : ''}'
                              ' • ${p['listeners'] ?? 0} listening',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _join(p),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// Inside a party — polls room state and keeps local playback in sync with
/// the host's track + position. Host sets the track from their own player.
class PartyRoomScreen extends StatefulWidget {
  final String hash;
  final bool isHost;
  const PartyRoomScreen({super.key, required this.hash, required this.isHost});

  @override
  State<PartyRoomScreen> createState() => _PartyRoomScreenState();
}

class _PartyRoomScreenState extends State<PartyRoomScreen> {
  final _api = ApiService.instance;
  Timer? _timer;
  Map<String, dynamic>? _party;
  String? _playingHash;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _api.postPayloadRaw(endpoint: 'htx/party', data: {'action': 'leave', 'hash': widget.hash});
    super.dispose();
  }

  Future<void> _poll() async {
    final res = await _api.postPayloadRaw(
        endpoint: 'htx/party?action=state&hash=${widget.hash}', data: const {});
    if (!mounted) return;
    final p = res.data?['party'];
    if (p is! Map) return;
    setState(() => _party = Map<String, dynamic>.from(p));

    // sync playback to the host's current track + position
    final track = p['track'];
    if (track is Map && track['hash'] != null) {
      final hash = track['hash'].toString();
      final pos = (p['position_sec'] as num?)?.toInt() ?? 0;
      final stateAt = DateTime.tryParse('${p['state_at']}');
      final drift = stateAt == null
          ? 0
          : DateTime.now().toUtc().difference(stateAt.toUtc()).inSeconds;
      if (_playingHash != hash) {
        _playingHash = hash;
        final t = Track(
          id: hash,
          title: (track['title'] ?? '').toString(),
          subtitle: (track['artist'] ?? '').toString(),
          url: '',
          objectType: 'm_track',
          objectHash: hash,
        );
        await PlayerService.instance.playTrack(t);
        await PlayerService.instance.audioPlayer.seek(Duration(seconds: pos + drift));
      }
    }
  }

  Future<void> _setTrack() async {
    final cur = PlayerService.instance.currentTrack;
    if (cur == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Play a track first — it becomes the party track')));
      return;
    }
    final hash = cur.objectHash ?? cur.id;
    final pos = PlayerService.instance.audioPlayer.position.inSeconds;
    await _api.postPayloadRaw(endpoint: 'htx/party', data: {
      'action': 'set_track',
      'hash': widget.hash,
      'track_hash': hash,
      'position_sec': '$pos',
    });
    _poll();
  }

  Future<void> _end() async {
    await _api.postPayloadRaw(endpoint: 'htx/party', data: {'action': 'end', 'hash': widget.hash});
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _party;
    final track = p?['track'] is Map ? p!['track'] as Map : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(p?['name']?.toString() ?? 'Party'),
        actions: [
          if (widget.isHost)
            IconButton(icon: const Icon(Icons.stop_rounded), tooltip: 'End party', onPressed: _end),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.surround_sound_rounded, size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 18),
              Text(track?['title']?.toString() ?? 'Waiting for the host…',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              if (track?['artist'] != null)
                Text(track!['artist'].toString(), style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text('${p?['listeners'] ?? 0} listening together',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 26),
              if (widget.isHost)
                FilledButton.icon(
                  onPressed: _setTrack,
                  icon: const Icon(Icons.music_note_rounded),
                  label: const Text('Play current track for everyone'),
                )
              else
                Text('Synced with the host', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
