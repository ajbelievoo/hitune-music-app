import 'package:flutter/material.dart';

import '../auth/auth_gate.dart';
import '../player/models/track.dart';
import 'comments_service.dart';

/// Comments bottom sheet for a track/album/playlist.
class CommentsSheet extends StatefulWidget {
  final String objectType;
  final String objectHash;
  final String title;

  const CommentsSheet({
    super.key,
    required this.objectType,
    required this.objectHash,
    this.title = '',
  });

  static Future<void> show(BuildContext context, Track track) {
    return CommentsSheet.open(
      context,
      objectType: track.objectType ?? 'm_track',
      objectHash: track.objectHash ?? track.id,
      title: track.title,
    );
  }

  static Future<void> open(
    BuildContext context, {
    required String objectType,
    required String objectHash,
    String title = '',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: CommentsSheet(objectType: objectType, objectHash: objectHash, title: title),
      ),
    );
  }

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _svc = CommentsService.instance;
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<Comment> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await _svc.fetch(objectType: widget.objectType, objectHash: widget.objectHash);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = res.isSuccess ? (res.data ?? const []) : const [];
      _error = res.isSuccess ? null : (res.error?.message ?? 'Failed to load comments');
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to comment.');
    if (!ok) return;
    setState(() => _sending = true);
    final res = await _svc.add(objectType: widget.objectType, objectHash: widget.objectHash, text: text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.isSuccess) {
      _ctrl.clear();
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error?.message ?? 'Could not post comment')),
      );
    }
  }

  String _ago(DateTime? ts) {
    if (ts == null) return '';
    final d = DateTime.now().difference(ts);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
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
                    widget.title.isEmpty ? 'Comments' : 'Comments • ${widget.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
          Divider(color: theme.dividerColor, height: 8),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, style: theme.textTheme.bodyMedium),
                            TextButton(onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : _items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('Be the first to comment', style: theme.textTheme.bodyMedium),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _items.length,
                            itemBuilder: (context, i) {
                              final c = _items[i];
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                  child: Text(
                                    c.author.isNotEmpty ? c.author[0].toUpperCase() : '?',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(c.author,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                    ),
                                    if (c.createdAt != null)
                                      Text(_ago(c.createdAt), style: theme.textTheme.bodySmall),
                                  ],
                                ),
                                subtitle: Text(c.text),
                              );
                            },
                          ),
          ),
          Divider(color: theme.dividerColor, height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.send_rounded, color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
