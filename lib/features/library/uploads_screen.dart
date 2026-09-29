import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'user_library_service.dart';
import 'upload_service.dart';
import '../player/player_service.dart';
import '../player/mini_player.dart';
import '../auth/auth_gate.dart';
import '../artist/artist_screen.dart';

class UploadsScreen extends StatefulWidget {
  const UploadsScreen({super.key});

  @override
  State<UploadsScreen> createState() => _UploadsScreenState();
}

class _UploadsScreenState extends State<UploadsScreen> {
  final _librarySvc = UserLibraryService();
  final _uploadSvc = UploadService();

  bool _loading = false;
  bool _isFetching = false;
  String? _error;
  List<dynamic> _items = const [];
  int _currentPage = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _fetchPage(1);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchPage(int page) async {
    if (_isFetching) return;
    _isFetching = true;

    final result = await _librarySvc.fetchUserLibrary(tab: 'uploads', page: page);

    if (!mounted) return;

    if (result.isSuccess) {
      final data = result.data!;
      final widgets = data['widgets'] as List<dynamic>? ?? [];

      if (widgets.isNotEmpty) {
        final widget = widgets.first as Map<String, dynamic>;
        final items = widget['items'] as List<dynamic>? ?? [];

        setState(() {
          if (page == 1) {
            _items = items;
          } else {
            _items = [..._items, ...items];
          }
          _currentPage = page;
          _hasMore = items.length >= 20;
        });
      } else {
        setState(() => _hasMore = false);
      }
    } else {
      final error = result.error!;
      if (error.code == 'forbidden' || error.code == '401') {
        final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to view uploads.');
        if (ok) {
          await _fetchPage(page);
          return;
        }
      }
      setState(() => _error = error.message);
    }

    _isFetching = false;
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isFetching) return;
    await _fetchPage(_currentPage + 1);
  }

  Future<void> _deleteItem(String itemHash) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Upload'),
        content: const Text('Are you sure you want to delete this upload? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    final result = await _uploadSvc.removeSingleItem(itemHash: itemHash);

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload deleted successfully')),
      );
      await _load();
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: ${result.error?.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('My Uploads'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: () {
              Navigator.of(context).pushNamed('/upload');
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _items.isEmpty
                  ? _buildEmptyState()
                  : _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).pushNamed('/upload');
        },
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: MiniPlayer(player: PlayerService.instance),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              'Failed to load uploads',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8), fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_outlined, size: 64, color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 16),
            Text(
              'No uploads yet',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload your music to see it here',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black38, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed('/upload');
              },
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Upload Music'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          if (notification.metrics.extentAfter < 200) {
            _loadMore();
          }
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final item = _items[index] as Map<String, dynamic>;
          return _UploadCard(
            item: item,
            onTap: () => _onItemTap(item),
            onDelete: () => _deleteItem(item['hash']?.toString() ?? item['ID']?.toString() ?? ''),
          );
        },
      ),
    );
  }

  void _onItemTap(Map<String, dynamic> item) {
    final slug = item['slug']?.toString() ?? item['ID']?.toString();
    final type = item['type']?.toString() ?? 'track';

    if (type == 'artist' && slug != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ArtistScreen(
            artistSlug: slug,
            artistTitle: (item['title'] ?? item['name'])?.toString(),
          ),
        ),
      );
    } else {
      // Play the track
    }
  }
}

class _UploadCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _UploadCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final title = item['title']?.toString() ?? item['name']?.toString() ?? 'Unknown';
    final subtitle = item['artist']?.toString() ?? item['sub_title']?.toString() ?? 'You';
    final cover = item['cover']?.toString() ?? item['image']?.toString() ?? '';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: cover.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: cover,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (context, url) => Container(
                              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                              child: Icon(Icons.music_note, color: isDark ? Colors.white54 : Colors.black54),
                            ),
                          )
                        : Container(
                            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                            child: Icon(Icons.music_note, color: isDark ? Colors.white54 : Colors.black54),
                          ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.more_vert, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
