import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';

class ClientConfigAdminService {
  final ApiService _api = ApiService.instance;

  Future<ApiResult<Map<String, dynamic>>> getClientConfig() async {
    final res = await _api.postPayloadRaw(endpoint: 'be/client_config', isAdmin: true);
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final payload = res.data;
    if (payload == null) {
      return ApiResult.failure(const ApiError(code: 'invalid_admin_client_config', message: 'Admin client_config response did not contain expected payload'));
    }

    return ApiResult.success(payload);
  }

  Future<ApiResult<void>> updateClientConfig(Map<String, String> updates) async {
    final res = await _api.postRaw(endpoint: 'be/client_config_update', data: updates, isAdmin: true);
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final json = res.data;
    if (json != null) {
      final msgs = json['messages'];
      if (msgs is List && msgs.isNotEmpty) {
        final joined = msgs.map((e) => e.toString()).join(' | ').trim();
        if (joined == '403') {
          return ApiResult.failure(const ApiError(code: 'forbidden', message: 'Forbidden'));
        }
        if (joined == '401') {
          return ApiResult.failure(const ApiError(code: 'unauthorized', message: 'Unauthorized'));
        }
      }
    }

    return ApiResult.success(null);
  }
}
