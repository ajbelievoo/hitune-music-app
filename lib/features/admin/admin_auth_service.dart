import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';
import '../../core/storage/secure_storage.dart';

class AdminAuthService {
  final ApiService _api = ApiService.instance;

  Future<ApiResult<void>> login({required String email, required String password}) async {
    final res = await _api.postRaw(
      endpoint: 'be/login',
      data: {
        '__email__': email,
        '__password__': password,
      },
      isAdmin: true,
    );

    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final json = res.data!;
    final msg = (json['messages'] is List && (json['messages'] as List).isNotEmpty)
        ? (json['messages'] as List).first
        : null;

    final sessId = (json['sess_id'] ?? '').toString().isNotEmpty
        ? (json['sess_id']).toString()
        : (msg is Map<String, dynamic> ? (msg['sess_id'] ?? '').toString() : '');
    final sessKey = (json['sess_key'] ?? '').toString().isNotEmpty
        ? (json['sess_key']).toString()
        : (msg is Map<String, dynamic> ? (msg['sess_key'] ?? '').toString() : '');

    if (sessId.isEmpty || sessKey.isEmpty) {
      return ApiResult.failure(const ApiError(code: 'invalid_admin_session', message: 'Admin login succeeded but session was not returned'));
    }

    await SecureStore.setAdminSession(sessId: sessId, sessKey: sessKey);
    return ApiResult.success(null);
  }
}
