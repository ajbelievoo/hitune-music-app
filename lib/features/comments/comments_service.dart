import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';

/// A user comment on a track/album/playlist.
class Comment {
  final String id;
  final String author;
  final String? avatarUrl;
  final String text;
  final DateTime? createdAt;
  final int likeCount;

  const Comment({
    required this.id,
    required this.author,
    required this.text,
    this.avatarUrl,
    this.createdAt,
    this.likeCount = 0,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    DateTime? ts;
    final rawTs = json['created_at'] ?? json['timestamp'];
    if (rawTs is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(rawTs * (rawTs > 9999999999 ? 1 : 1000));
    } else if (rawTs != null) {
      ts = DateTime.tryParse(rawTs.toString());
    }
    final user = json['user'] is Map ? Map<String, dynamic>.from(json['user'] as Map) : null;
    return Comment(
      id: (json['id'] ?? json['hash'] ?? json['comment_id'] ?? '').toString(),
      author: (json['author'] ?? json['user_name'] ?? user?['name'] ?? 'User').toString(),
      avatarUrl: (json['avatar'] ?? user?['avatar'])?.toString(),
      text: (json['text'] ?? json['body'] ?? json['comment'] ?? '').toString(),
      createdAt: ts,
      likeCount: json['likes'] is int ? json['likes'] as int : int.tryParse('${json['likes']}') ?? 0,
    );
  }
}

/// Comments API client.
///
/// Expected endpoints (docs/BACKEND_REQUIREMENTS.md):
/// - `comments`       -> { object_type, object, page } -> list
/// - `comment_add`    -> { object_type, object, text } -> created comment
/// - `comment_delete` -> { comment_id }
class CommentsService {
  CommentsService._();
  static final CommentsService instance = CommentsService._();

  final ApiService _api = ApiService.instance;

  Future<ApiResult<List<Comment>>> fetch({
    required String objectType,
    required String objectHash,
    int page = 1,
  }) async {
    final res = await _api.postPayloadRaw(
      endpoint: 'comments',
      data: {
        'object_type': objectType,
        'object': objectHash,
        'page': page.toString(),
      },
    );
    if (!res.isSuccess || res.data == null) {
      return ApiResult.failure(res.error ?? const ApiError(code: 'no_data', message: 'No comments'));
    }
    final raw = res.data!['comments'] ?? res.data!['items'] ?? res.data!['list'];
    if (raw is! List) return ApiResult.success(const []);
    return ApiResult.success(
      raw.whereType<Map>().map((e) => Comment.fromJson(Map<String, dynamic>.from(e))).toList(),
    );
  }

  Future<ApiResult<void>> add({
    required String objectType,
    required String objectHash,
    required String text,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'comment_add',
      data: {
        'object_type': objectType,
        'object': objectHash,
        'text': text,
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(null);
  }

  Future<ApiResult<void>> delete({required String commentId}) async {
    final res = await _api.postRaw(
      endpoint: 'comment_delete',
      data: {'comment_id': commentId},
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(null);
  }
}
