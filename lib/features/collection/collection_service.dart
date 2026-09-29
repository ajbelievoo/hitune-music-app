import 'package:flutter/foundation.dart';

import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';
import '../../core/utils/app_logger.dart';

class CollectionService {
  final ApiService _api = ApiService.instance;

  Future<ApiResult<Map<String, dynamic>>> fetchListWidget({
    required String widgetHash,
    int page = 1,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final endpoint = 'bofClient/list/$widgetHash/?page=$safePage';

    final res = await _api.postPayloadRaw(endpoint: endpoint);
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final data = res.data;
    if (data is! Map<String, dynamic>) {
      return ApiResult.failure(const ApiError(code: 'invalid_list', message: 'List response is not a JSON object'));
    }

    return ApiResult.success(data);
  }

  Future<ApiResult<Map<String, dynamic>>> fetchCollectionDetail({
    required String hash,
    String? slug,
  }) async {
    // m_album resolves by slug (e.g. "maher_zain-never_let_me_down" from the
    // item's `url` field). `?hash=` returns 404 on this backend.
    final key = (slug != null && slug.isNotEmpty) ? slug : hash;
    final endpoint = 'bofClient/single/m_album/?slug=$key';

    final res = await _api.postPayloadRaw(endpoint: endpoint);
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final data = res.data;
    if (data is! Map<String, dynamic>) {
      return ApiResult.failure(const ApiError(code: 'invalid_album', message: 'Album response is not a JSON object'));
    }

    return ApiResult.success(data);
  }

  Future<ApiResult<Map<String, dynamic>>> fetchRelatedTracks({
    required String trackHash,
    int limit = 10,
  }) async {
    // Try to get recommended tracks from home page
    final homeEndpoints = [
      'bofClient/home?page=1',
      'bofClient/search?limit=$limit',
    ];
    
    for (final endpoint in homeEndpoints) {
      try {
        if (kDebugMode) AppLogger.d('[CollectionService] Trying endpoint: $endpoint');
        final res = await _api.postPayloadRaw(endpoint: endpoint);
        if (kDebugMode) AppLogger.d('[CollectionService] Response success: ${res.isSuccess}, data type: ${res.data?.runtimeType}');
        
        if (res.isSuccess && res.data is Map<String, dynamic>) {
          final data = res.data as Map<String, dynamic>;
          if (kDebugMode) AppLogger.d('[CollectionService] Response keys: ${data.keys.toList()}');
          
          // Extract tracks from widgets
          final widgets = data['widgets'];
          if (kDebugMode) AppLogger.d('[CollectionService] Widgets type: ${widgets.runtimeType}');
          
          if (widgets is List && widgets.isNotEmpty) {
            if (kDebugMode) AppLogger.d('[CollectionService] Found ${widgets.length} widgets');
            // Return the data, _extractTracksFromPayload will handle it
            return ApiResult.success(data);
          }
        }
      } catch (e) {
        if (kDebugMode) AppLogger.d('[CollectionService] Error on $endpoint: $e');
        continue;
      }
    }
    
    return ApiResult.failure(const ApiError(code: 'no_related', message: 'No related tracks found'));
  }
}
