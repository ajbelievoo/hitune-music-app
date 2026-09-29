import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';
import '../../core/storage/secure_storage.dart';
import 'models/user_session.dart';

class AuthService {
  final ApiService _api = ApiService.instance;

  Future<ApiResult<UserSession>> login({required String email, required String password}) async {
    final res = await _api.postRaw(
      endpoint: 'user_auth?bof=submit&do=login',
      data: {
        'email': email,
        'password': password,
      },
    );

    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final session = UserSession.fromJson(res.data!);
    if (session.sessId.isEmpty || session.sessKey.isEmpty) {
      return ApiResult.failure(const ApiError(code: 'invalid_session', message: 'Login succeeded but session was not returned'));
    }

    await SecureStore.setUserSession(sessId: session.sessId, sessKey: session.sessKey);
    return ApiResult.success(session);
  }

  Future<ApiResult<UserSession>> signup({
    required String email,
    required String username,
    required String password,
    required String passwordRepeat,
    required bool agree,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'user_auth?bof=submit&do=signup',
      data: {
        'email': email,
        'username': username,
        'password': password,
        'password_repeat': passwordRepeat,
        if (agree) 'agree': 'on',
      },
    );

    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final session = UserSession.fromJson(res.data!);

    if (session.sessId.isNotEmpty && session.sessKey.isNotEmpty) {
      await SecureStore.setUserSession(sessId: session.sessId, sessKey: session.sessKey);
    }

    return ApiResult.success(session);
  }

  Future<void> setSession({required String sessId, required String sessKey}) async {
    await SecureStore.setUserSession(sessId: sessId, sessKey: sessKey);
  }

  Future<ApiResult<void>> forgotPassword({required String email}) async {
    final res = await _api.postRaw(
      endpoint: 'user_auth?bof=submit&do=recover',
      data: {
        'email': email,
      },
    );

    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(null);
  }

  Future<ApiResult<UserSession>> resetPassword({
    required String email,
    required String code,
    required String password,
    required String passwordRepeat,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'user_auth?bof=submit&do=recover_confirm',
      data: {
        'email': email,
        'code': code,
        'password': password,
        'password_repeat': passwordRepeat,
      },
    );

    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final session = UserSession.fromJson(res.data!);
    if (session.sessId.isNotEmpty && session.sessKey.isNotEmpty) {
      await SecureStore.setUserSession(sessId: session.sessId, sessKey: session.sessKey);
    }

    return ApiResult.success(session);
  }
}
