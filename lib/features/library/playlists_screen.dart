import 'package:flutter/material.dart';

import '../../core/ui/cover_image.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../auth/auth_gate.dart';
import 'user_library_service.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final _svc = UserLibraryService();

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _playlists = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _extractPlaylists(Map<String, dynamic> payload) {
    // Real backend shape (verified live): `widgets` is a List of widget
    // objects; the playlists widget has widget_type/ID == 'playlists' and its
    // `items` is a page-keyed map like { "1": [ ...items ] }.
    final widgets = payload['widgets'];
    dynamic plNode;
    if (widgets is List) {
      for (final w in widgets) {
        if (w is Map &&
            (w['widget_type'] == 'playlists' || w['ID'] == 'playlists')) {
          plNode = w;
          break;
        }
      }
      plNode ??= widgets.whereType<Map>().firstOrNull;
    } else if (widgets is Map) {
      final wm = Map<String, dynamic>.from(widgets);
      plNode = wm['playlists'] ?? wm['playlist'] ?? wm.values.firstOrNull;
    }

    dynamic items;
    if (plNode is Map) {
      final pm = Map<String, dynamic>.from(plNode);
      items = pm['items'] ?? (pm['data'] is Map ? (pm['data'] as Map)['items'] : null);
    }

    // Fallback shapes: a bare list on the payload, or `playlists` key.
    items ??= payload['playlists'] ?? payload['items'];

    final out = <Map<String, dynamic>>[];
    void collect(dynamic node) {
      if (node is List) {
        for (final e in node) {
          if (e is Map) out.add(Map<String, dynamic>.from(e));
        }
      } else if (node is Map) {
        // Page-keyed map: { "1": [...], "2": [...] }
        for (final v in node.values) {
          if (v is List) collect(v);
        }
      }
    }

    collect(items);
    return out;
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await _svc.fetchUserLibrary(tab: 'playlists', page: 1);
    if (!mounted) return;

    if (!res.isSuccess || res.data == null) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Failed to load playlists';
        _playlists = const [];
      });
      return;
    }

    final items = _extractPlaylists(res.data!);
    setState(() {
      _loading = false;
      _playlists = items;
    });
  }

  Future<void> _createPlaylist() async {
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to create playlists.');
    if (!ok) return;

    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Create playlist', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: ctrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Playlist name',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.1),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.7)))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    final n = (name ?? '').trim();
    if (n.isEmpty) return;

    setState(() => _loading = true);
    final res = await _svc.createPlaylist(name: n);
    if (!mounted) return;

    setState(() => _loading = false);
    if (!res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error?.message ?? 'Failed')));
      return;
    }

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Playlists'),
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: Icon(Icons.refresh_rounded, color: isDark ? Colors.white : Colors.black)),
          IconButton(onPressed: _loading ? null : _createPlaylist, icon: Icon(Icons.add_rounded, color: isDark ? Colors.white : Colors.black)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _playlists.isEmpty
                  ? _buildEmptyView()
                  : _buildPlaylistsList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _createPlaylist,
        backgroundColor: Colors.deepPurpleAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildErrorView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.redAccent.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.8), fontSize: 16)),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(Icons.playlist_play_rounded, size: 40, color: Colors.deepPurpleAccent.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 20),
            Text('No playlists yet', style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.9), fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Create your first playlist', style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.55))),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
              onPressed: _createPlaylist,
              icon: const Icon(Icons.add),
              label: const Text('Create Playlist'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistsList() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _playlists.length,
        itemBuilder: (context, i) => _buildPlaylistCard(_playlists[i]),
      ),
    );
  }

  String _playlistId(Map<String, dynamic> p) =>
      (p['hash'] ?? p['ID'] ?? p['id'] ?? p['object_hash'] ?? '').toString();

  Future<void> _renamePlaylist(Map<String, dynamic> p) async {
    final id = _playlistId(p);
    if (id.isEmpty) return;
    final ctrl = TextEditingController(text: (p['title'] ?? p['name'] ?? '').toString());
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Playlist name')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    final n = (name ?? '').trim();
    if (n.isEmpty || !mounted) return;
    final res = await _svc.renamePlaylist(playlistId: id, newName: n);
    if (!mounted) return;
    if (!res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error?.message ?? 'Rename failed')));
      return;
    }
    await _load();
  }

  Future<void> _deletePlaylist(Map<String, dynamic> p) async {
    final id = _playlistId(p);
    if (id.isEmpty) return;
    final title = (p['title'] ?? p['name'] ?? 'Playlist').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete playlist'),
        content: Text('Delete "$title"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await _svc.deletePlaylist(playlistId: id);
    if (!mounted) return;
    if (!res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error?.message ?? 'Delete failed')));
      return;
    }
    await _load();
  }

  Widget _buildPlaylistCard(Map<String, dynamic> p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = (p['title'] ?? p['name'] ?? 'Playlist').toString();
    final subtitle = (p['sub_title'] ?? p['subtitle'] ?? '${p['count'] ?? p['s_items'] ?? 0} tracks').toString();
    // Central extractor handles HTML covers and rejects dummy placeholders.
    final cover = CoverImageExtractor.extract(p);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CoverImage(
              imageUrl: cover,
              placeholder: Center(
                child: Icon(Icons.playlist_play_rounded, color: Colors.deepPurpleAccent.withValues(alpha: 0.7), size: 28),
              ),
            ),
          ),
        ),
        title: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(subtitle, style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.55), fontSize: 12)),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.4)),
          onSelected: (v) {
            if (v == 'rename') _renamePlaylist(p);
            if (v == 'delete') _deletePlaylist(p);
          },
          itemBuilder: (ctx) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () {
          // Navigate to playlist detail
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Opening $title...')));
        },
      ),
    );
  }
}

extension _FirstOrNull on Iterable {
  Object? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
