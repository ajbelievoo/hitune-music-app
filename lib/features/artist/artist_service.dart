import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';

class ArtistService {
  final ApiService _api = ApiService.instance;

  Future<ApiResult<Map<String, dynamic>>> fetchArtist({required String slug}) async {
    final endpoint = 'bofClient/single/m_artist/?slug=${Uri.encodeQueryComponent(slug)}';
    final res = await _api.postPayloadRaw(endpoint: endpoint);
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    final payload = res.data;
    if (payload == null) {
      return ApiResult.failure(const ApiError(code: 'invalid_artist', message: 'Artist payload missing'));
    }
    final data = payload['data'];
    if (data is Map) {
      return ApiResult.success(Map<String, dynamic>.from(data));
    }
    return ApiResult.failure(const ApiError(code: 'invalid_artist', message: 'Artist data missing'));
  }

  Future<ApiResult<Map<String, dynamic>>> toggleFollow({
    required String artistHash,
    required bool follow,
  }) async {
    final endpoint = 'm_artist_sub';
    final res = await _api.postRaw(
      endpoint: endpoint,
      data: {
        'hash': artistHash,
        'sub': follow ? '1' : '0',
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(res.data ?? <String, dynamic>{});
  }
}
