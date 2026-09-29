import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';

/// A single in-app notification.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? imageUrl;
  final String? link;
  final bool isRead;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    this.body = '',
    this.imageUrl,
    this.link,
    this.isRead = false,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    DateTime? ts;
    final rawTs = json['created_at'] ?? json['timestamp'] ?? json['date'];
    if (rawTs is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(rawTs * (rawTs > 9999999999 ? 1 : 1000));
    } else if (rawTs != null) {
      ts = DateTime.tryParse(rawTs.toString());
    }
    return AppNotification(
      id: (json['id'] ?? json['hash'] ?? json['ID'] ?? '').toString(),
      title: (json['title'] ?? json['subject'] ?? 'Notification').toString(),
      body: (json['body'] ?? json['message'] ?? json['text'] ?? '').toString(),
      imageUrl: (json['image'] ?? json['image_url'] ?? json['icon'])?.toString(),
      link: (json['link'] ?? json['url'])?.toString(),
      isRead: json['is_read'] == true || json['is_read'] == 1 || json['is_read'] == '1' ||
          json['read'] == true || json['read'] == 1 || json['read'] == '1',
      createdAt: ts,
    );
  }
}

/// Fetches the in-app notification list from the backend.
///
/// Expected endpoints (documented in docs/BACKEND_REQUIREMENTS.md):
/// - `notifications`            -> list of notifications
/// - `notification_mark_read`   -> { notification_id }
/// - `notification_mark_all`    -> marks everything read
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final ApiService _api = ApiService.instance;

  Future<ApiResult<List<AppNotification>>> fetch({int page = 1}) async {
    final res = await _api.postPayloadRaw(
      endpoint: 'notifications',
      data: {'page': page.toString()},
    );
    if (!res.isSuccess || res.data == null) {
      return ApiResult.failure(res.error ?? const ApiError(code: 'no_data', message: 'No notifications'));
    }

    final data = res.data!;
    final raw = data['notifications'] ?? data['items'] ?? data['list'];
    final items = _flatten(raw)
        .map(AppNotification.fromJson)
        .toList();
    return ApiResult.success(items);
  }

  /// BOF responses may hand the list back as a plain List, a Map containing
  /// an `items` list, or a page-numbered map ({'1': [...], '2': [...]}).
  List<Map<String, dynamic>> _flatten(dynamic raw) {
    final out = <Map<String, dynamic>>[];
    void walk(dynamic node) {
      if (node is List) {
        for (final e in node) {
          if (e is Map) out.add(Map<String, dynamic>.from(e));
        }
      } else if (node is Map) {
        if (node['items'] != null) {
          walk(node['items']);
        } else if (node.containsKey('title') || node.containsKey('id') || node.containsKey('ID')) {
          out.add(Map<String, dynamic>.from(node));
        } else {
          node.values.forEach(walk);
        }
      }
    }
    walk(raw);
    return out;
  }

  Future<int> unreadCount() async {
    final res = await fetch();
    if (!res.isSuccess || res.data == null) return 0;
    return res.data!.where((n) => !n.isRead).length;
  }

  Future<void> markRead(String id) async {
    await _api.postRaw(endpoint: 'notification_mark_read', data: {'notification_id': id});
  }

  Future<void> markAllRead() async {
    await _api.postRaw(endpoint: 'notification_mark_all');
  }
}
