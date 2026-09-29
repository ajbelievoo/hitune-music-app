import 'package:flutter/material.dart';

import '../player/models/track.dart';
import '../player/player_service.dart';
import 'download_service.dart';

/// Lists downloaded tracks and lets the user play them offline or delete them.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _dl = DownloadService.instance;
  List<DownloadedTrack> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
    _dl.itemsStream.listen((items) {
      if (mounted) setState(() => _items = items);
    });
  }

  Future<void> _reload() async {
    final items = await _dl.list();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _playAll(int startIndex) async {
    final tracks = _items.map((d) => d.toTrack()).toList();
    await PlayerService.instance.playQueue(tracks, startIndex: startIndex);
  }

  Future<void> _removeItem(DownloadedTrack item) async {
    await _dl.remove(item.toTrack());
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove all downloads'),
        content: const Text('All downloaded songs will be deleted from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await _dl.clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Remove all',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_done_rounded, size: 56, color: theme.iconTheme.color?.withValues(alpha: 0.35)),
                      const SizedBox(height: 12),
                      Text('No downloads yet', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('Downloaded songs appear here and play offline.', style: theme.textTheme.bodySmall),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      return ListTile(
                        leading: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.download_done_rounded),
                        ),
                        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [item.subtitle ?? '', _fmtSize(item.bytes)].where((s) => s.isNotEmpty).join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _removeItem(item),
                        ),
                        onTap: () => _playAll(i),
                      );
                    },
                  ),
                ),
      floatingActionButton: _items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _playAll(0),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play all'),
            ),
    );
  }
}
