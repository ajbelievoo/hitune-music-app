import 'package:flutter/material.dart';

import '../player/models/track.dart';
import 'user_library_service.dart';

/// Sheet that lists the user's playlists so a track can be added to one,
/// or a new playlist can be created on the fly.
class PlaylistPickerSheet extends StatefulWidget {
  final Track track;

  const PlaylistPickerSheet({super.key, required this.track});

  static Future<void> show(BuildContext context, Track track) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PlaylistPickerSheet(track: track),
    );
  }

  @override
  State<PlaylistPickerSheet> createState() => _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends State<PlaylistPickerSheet> {
  final _svc = UserLibraryService();
  bool _loading = true;
  List<Map<String, dynamic>> _playlists = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _svc.fetchUserLibrary(tab: 'playlists', page: 1);
    if (!mounted) return;
    List<Map<String, dynamic>> items = const [];
    if (res.isSuccess && res.data != null) {
      items = _extract(res.data!);
    }
    setState(() {
      _loading = false;
      _playlists = items;
    });
  }

  List<Map<String, dynamic>> _extract(Map<String, dynamic> payload) {
    final widgets = payload['widgets'];
    dynamic plNode;
    if (widgets is Map) {
      final wm = Map<String, dynamic>.from(widgets);
      plNode = wm['playlists'] ?? wm['playlist'] ?? wm.values.firstOrNull;
    } else if (widgets is List && widgets.isNotEmpty) {
      plNode = widgets.first;
    }
    dynamic items;
    if (plNode is Map) {
      final pm = Map<String, dynamic>.from(plNode);
      items = pm['items'] ?? (pm['data'] is Map ? (pm['data'] as Map)['items'] : null);
    }
    if (items is! List) return const [];
    return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false);
  }

  String _playlistId(Map<String, dynamic> p) =>
      (p['hash'] ?? p['ID'] ?? p['id'] ?? p['object_hash'] ?? '').toString();

  Future<void> _addTo(Map<String, dynamic> playlist) async {
    final playlistId = _playlistId(playlist);
    if (playlistId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final res = await _svc.addToPlaylist(
      playlistId: playlistId,
      objectType: widget.track.objectType ?? 'm_track',
      objectHash: widget.track.objectHash ?? widget.track.id,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    final name = (playlist['title'] ?? playlist['name'] ?? 'playlist').toString();
    messenger.showSnackBar(
      SnackBar(content: Text(res.isSuccess ? 'Added to $name' : 'Failed: ${res.error?.message ?? 'unknown error'}')),
    );
  }

  Future<void> _createAndAdd() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    final n = (name ?? '').trim();
    if (n.isEmpty || !mounted) return;

    final res = await _svc.createPlaylist(name: n);
    if (!mounted) return;
    if (!res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error?.message ?? 'Could not create playlist')),
      );
      return;
    }
    await _load();
    // Try to add to the newest playlist if the backend returned an id.
    final created = res.data ?? const <String, dynamic>{};
    final newId = (created['playlist_hash'] ?? created['hash'] ?? created['id'])?.toString();
    if (newId != null && newId.isNotEmpty) {
      await _addTo({'hash': newId, 'title': n});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Playlist created. Select it to add the track.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add to playlist',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          ListTile(
            dense: true,
            leading: Icon(Icons.add_rounded, color: theme.colorScheme.primary),
            title: Text('New playlist', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
            onTap: _createAndAdd,
          ),
          Divider(color: theme.dividerColor, height: 8),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : _playlists.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No playlists yet', style: theme.textTheme.bodyMedium),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _playlists.length,
                        itemBuilder: (context, i) {
                          final p = _playlists[i];
                          final title = (p['title'] ?? p['name'] ?? 'Playlist').toString();
                          final count = (p['count'] ?? p['tracks_count'] ?? '').toString();
                          return ListTile(
                            dense: true,
                            leading: Icon(Icons.playlist_play_rounded,
                                color: theme.iconTheme.color?.withValues(alpha: 0.7)),
                            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: count.isNotEmpty ? Text('$count tracks') : null,
                            onTap: () => _addTo(p),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
