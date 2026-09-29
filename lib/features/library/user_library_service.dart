import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';

class UserLibraryService {
  final ApiService _api = ApiService.instance;

  Future<ApiResult<Map<String, dynamic>>> fetchUserLibrary({
    required String tab,
    int page = 1,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final endpoint = 'user_library?tab=${Uri.encodeQueryComponent(tab)}&page=$safePage';
    final res = await _api.postPayloadRaw(endpoint: endpoint);
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final data = res.data;
    if (data == null) {
      return ApiResult.failure(const ApiError(code: 'invalid_user_library', message: 'User library payload missing'));
    }

    final msgs = data['messages'];
    if (msgs is List && msgs.isNotEmpty && msgs.first.toString() == '403') {
      return ApiResult.failure(const ApiError(code: 'forbidden', message: 'Forbidden (user_library). Login required or missing user permission.'));
    }

    return ApiResult.success(data);
  }

  Future<ApiResult<Map<String, dynamic>?>> createPlaylist({
    required String name,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'playlist_create',
      data: {
        'playlist': name,
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    final decoded = res.data;
    final msgs = decoded?['messages'];
    if (msgs is List && msgs.isNotEmpty && msgs.first.toString() == '403') {
      return ApiResult.failure(const ApiError(code: 'forbidden', message: 'Forbidden (playlist_create). Login required or missing user permission.'));
    }
    return ApiResult.success(decoded);
  }

  /// Adds a track/album to a playlist.
  /// Backend endpoint: `playlist_add` (see docs/BACKEND_REQUIREMENTS.md).
  Future<ApiResult<void>> addToPlaylist({
    required String playlistId,
    required String objectType,
    required String objectHash,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'playlist_add',
      data: {
        'playlist': playlistId,
        'object_type': objectType,
        'object': objectHash,
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(null);
  }

  /// Removes an item from a playlist.
  /// Backend endpoint: `playlist_remove`.
  Future<ApiResult<void>> removeFromPlaylist({
    required String playlistId,
    required String objectType,
    required String objectHash,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'playlist_remove',
      data: {
        'playlist': playlistId,
        'object_type': objectType,
        'object': objectHash,
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(null);
  }

  /// Renames a playlist.
  /// Backend endpoint: `playlist_rename`.
  Future<ApiResult<void>> renamePlaylist({
    required String playlistId,
    required String newName,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'playlist_rename',
      data: {
        'playlist': playlistId,
        'name': newName,
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(null);
  }

  /// Deletes a playlist.
  /// Backend endpoint: `playlist_delete`.
  Future<ApiResult<void>> deletePlaylist({
    required String playlistId,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'playlist_delete',
      data: {'playlist': playlistId},
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(null);
  }

  /// Reorders tracks inside a playlist.
  /// Backend endpoint: `playlist_reorder` - `order` is a comma-separated
  /// list of track hashes in the new order.
  Future<ApiResult<void>> reorderPlaylist({
    required String playlistId,
    required List<String> order,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'playlist_reorder',
      data: {
        'playlist': playlistId,
        'order': order.join(','),
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(null);
  }
}
