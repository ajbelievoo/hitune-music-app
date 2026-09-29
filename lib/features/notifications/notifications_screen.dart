import 'package:flutter/material.dart';

import '../auth/auth_gate.dart';
import 'notification_service.dart';

/// In-app notification inbox (backed by the `notifications` endpoint).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _svc = NotificationService.instance;
  bool _loading = true;
  String? _error;
  List<AppNotification> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _svc.fetch();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = res.isSuccess ? (res.data ?? const []) : const [];
      _error = res.isSuccess ? null : (res.error?.message ?? 'Failed to load');
    });
  }

  Future<void> _markAll() async {
    await _svc.markAllRead();
    await _load();
  }

  String _ago(DateTime? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_items.any((n) => !n.isRead))
            IconButton(
              onPressed: _markAll,
              icon: const Icon(Icons.done_all_rounded),
              tooltip: 'Mark all read',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none_rounded,
                              size: 56, color: theme.iconTheme.color?.withValues(alpha: 0.35)),
                          const SizedBox(height: 12),
                          Text('No notifications', style: theme.textTheme.titleMedium),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => Divider(color: theme.dividerColor, height: 1),
                        itemBuilder: (context, i) {
                          final n = _items[i];
                          return ListTile(
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: n.isRead
                                    ? theme.colorScheme.surfaceContainerHighest
                                    : theme.colorScheme.primary.withValues(alpha: 0.15),
                              ),
                              child: Icon(
                                Icons.notifications_rounded,
                                color: n.isRead
                                    ? theme.iconTheme.color?.withValues(alpha: 0.5)
                                    : theme.colorScheme.primary,
                                size: 22,
                              ),
                            ),
                            title: Text(
                              n.title,
                              style: TextStyle(
                                fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w800,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (n.body.isNotEmpty)
                                  Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                                if (n.createdAt != null)
                                  Text(
                                    _ago(n.createdAt),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                                    ),
                                  ),
                              ],
                            ),
                            onTap: () {
                              if (!n.isRead) _svc.markRead(n.id);
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}

/// App bar bell button with unread badge. Uses AuthGate before opening.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final count = await NotificationService.instance.unreadCount();
    if (mounted) setState(() => _unread = count);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text(_unread > 99 ? '99+' : '$_unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () async {
        final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to view notifications.');
        if (!ok || !context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        );
        _refresh();
      },
    );
  }
}
