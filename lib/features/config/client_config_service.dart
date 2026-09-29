import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';
import '../../core/storage/secure_storage.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';

class ClientConfigService extends ChangeNotifier {
  static final ClientConfigService _instance = ClientConfigService._internal();
  factory ClientConfigService() => _instance;
  ClientConfigService._internal();

  final ApiService _api = ApiService.instance;

  Map<String, dynamic>? _config;
  Map<String, dynamic>? get config => _config;

  Future<ApiResult<Map<String, dynamic>>>? _inflight;
  DateTime? _lastFetchAt;
  static const Duration _minTtl = Duration(seconds: 20);

  // Global startup sequencing - prevents CPU spike from concurrent calls
  static bool _startupSequenceComplete = false;
  static final List<Future<void> Function()> _startupQueue = [];

  /// Ensures startup calls are sequenced to prevent CPU spike
  Future<T> runInStartupSequence<T>(Future<T> Function() task, {String? name}) async {
    if (_startupSequenceComplete) {
      return await task();
    }
    
    final completer = Completer<T>();
    _startupQueue.add(() async {
      try {
        final result = await task();
        completer.complete(result);
      } catch (e) {
        completer.completeError(e);
      }
    });
    
    if (_startupQueue.length == 1) {
      _processStartupQueue();
    }
    
    return completer.future;
  }

  Future<void> _processStartupQueue() async {
    while (_startupQueue.isNotEmpty) {
      final task = _startupQueue.removeAt(0);
      await task();
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _startupSequenceComplete = true;
  }

  Future<ApiResult<Map<String, dynamic>>> fetchClientConfig() async {
    return runInStartupSequence(() => _fetchClientConfigInternal(), name: 'client_config');
  }

  Future<ApiResult<Map<String, dynamic>>> _fetchClientConfigInternal() async {
    final now = DateTime.now();
    if (_inflight != null) return _inflight!;
    if (_config != null && _lastFetchAt != null && now.difference(_lastFetchAt!) < _minTtl) {
      return ApiResult.success(_config!);
    }

    _inflight = (() async {
      final res = await _api.postPayloadRaw(endpoint: 'client_config');
      if (!res.isSuccess) {
        return ApiResult<Map<String, dynamic>>.failure(res.error!);
      }

      final payload = res.data;
      if (payload == null) {
        return ApiResult<Map<String, dynamic>>.failure(
          const ApiError(code: 'invalid_client_config', message: 'client_config response did not contain expected payload'),
        );
      }

      final mapPayload = payload is Map ? Map<String, dynamic>.from(payload as Map) : <String, dynamic>{};
      final same = _config != null && const DeepCollectionEquality().equals(_config, mapPayload);
      _config = mapPayload;
      _lastFetchAt = DateTime.now();
      await _persistRoleFromClientConfig(mapPayload);
      if (!same) notifyListeners();
      return ApiResult.success(mapPayload);
    })();

    try {
      return await _inflight!;
    } finally {
      _inflight = null;
    }
  }

  List<Map<String, dynamic>> _socialProviders = [];
  bool _socialProvidersFetched = false;

  List<Map<String, dynamic>> get socialProviders => _socialProviders;

  Future<void> fetchSocialLogins() async {
    debugPrint('[SOCIAL LOGIN] Fetching social login providers...');
    // CORRECT ENDPOINT: user/login_social_get (backend file: user/endpoint_login_social_get.php)
    final res = await _api.postPayloadRaw(endpoint: 'user/login_social_get');
    debugPrint('[SOCIAL LOGIN] Response: success=${res.isSuccess}, data=${res.data}');
    
    // Check for 403 in response body (session/auth required)
    if (res.data != null) {
      final messages = res.data!['messages'];
      if (messages is List && messages.any((m) => m.toString() == '403')) {
        debugPrint('[SOCIAL LOGIN] 403 detected - user not authenticated, using fallback');
        _useFallbackSocialLogins();
        return;
      }
    }
    
    if (!res.isSuccess || res.data == null) {
      debugPrint('[SOCIAL LOGIN] Failed: ${res.error?.message}, using fallback');
      _useFallbackSocialLogins();
      return;
    }

    final data = res.data!;
    final sls = data['sls'];
    debugPrint('[SOCIAL LOGIN] sls data: $sls');
    if (sls is List && sls.isNotEmpty) {
      // Trust the backend's sls list; do not filter out providers here.
      _socialProviders = sls.whereType<Map>().map((item) {
        return Map<String, dynamic>.from(item);
      }).toList();
      _socialProvidersFetched = true;
      debugPrint('[SOCIAL LOGIN] Loaded ${_socialProviders.length} providers from API');
      notifyListeners();
    } else {
      debugPrint('[SOCIAL LOGIN] No providers from API, using fallback');
      _useFallbackSocialLogins();
    }
  }

  void _useFallbackSocialLogins() {
    // Fallback: Add all popular social providers
    // Backend API se exact list tabhi aa payegi jab wo authentication ke bina public hoga
    if (_config != null) {
      final setting = _config!['setting'];
      if (setting is Map && setting['social_login'] == true) {
        _socialProviders = [
          {'id': 'google', 'title': 'Google', 'icon': 'google'},
          {'id': 'facebook', 'title': 'Facebook', 'icon': 'facebook'},
          {'id': 'spotify', 'title': 'Spotify', 'icon': 'spotify'},
          {'id': 'twitter', 'title': 'X (Twitter)', 'icon': 'twitter'},
          {'id': 'instagram', 'title': 'Instagram', 'icon': 'instagram'},
          {'id': 'apple', 'title': 'Apple', 'icon': 'apple'},
          {'id': 'linkedin', 'title': 'LinkedIn', 'icon': 'linkedin'},
          {'id': 'github', 'title': 'GitHub', 'icon': 'github'},
          {'id': 'dribbble', 'title': 'Dribbble', 'icon': 'dribbble'},
          {'id': 'twitch', 'title': 'Twitch', 'icon': 'twitch'},
          {'id': 'reddit', 'title': 'Reddit', 'icon': 'reddit'},
          {'id': 'discord', 'title': 'Discord', 'icon': 'discord'},
        ];
        _socialProvidersFetched = true;
        debugPrint('[SOCIAL LOGIN] Using fallback with all providers. Active ones will be filtered by isSocialLoginActive');
        notifyListeners();
      }
    }
  }

  bool isSocialLoginActive(String provider) {
    // If we have fetched providers from API, use that
    if (_socialProvidersFetched && _socialProviders.isNotEmpty) {
      return _socialProviders.any((p) {
        final id = p['id']?.toString().toLowerCase() ?? '';
        final title = p['title']?.toString().toLowerCase() ?? '';
        return id == provider.toLowerCase() ||
               title.contains(provider.toLowerCase());
      });
    }
    
    // Fallback to config
    if (_config == null) return false;
    final setting = _config!['setting'];
    if (setting is! Map) return false;
    
    // Check for active_social_logins list first
    final activeLogins = setting['active_social_logins'];
    if (activeLogins is List) {
      return activeLogins.contains(provider);
    }
    
    // Fallback: if social_login is enabled, allow all major providers
    if (setting['social_login'] == true) {
      return [
        'google', 'facebook', 'spotify', 'twitter', 'instagram', 
        'apple', 'linkedin', 'github', 'dribbble', 'twitch', 'reddit', 'discord'
      ].contains(provider.toLowerCase());
    }
    
    return false;
  }

  bool get isSocialLoginEnabled {
    if (_config == null) return false;
    final setting = _config!['setting'];
    if (setting is! Map) return false;
    return setting['social_login'] == true;
  }

  Future<void> _persistRoleFromClientConfig(Map<String, dynamic> payload) async {
    try {
      final user = payload['user'];
      if (user is! Map) return;
      final userMap = Map<String, dynamic>.from(user);

      final userData = userMap['data'];
      if (userData is Map) {
        final id = (userData['ID'] ?? userData['id'] ?? '').toString();
        if (id.isNotEmpty) {
          await SecureStore.setUserId(id);
        }
      }

      final extra = userMap['extra'];
      if (extra is! Map) return;
      final extraMap = Map<String, dynamic>.from(extra);

      final role = (extraMap['role'] ?? '').toString();

      String? roleIds;
      final ids = extraMap['role_ids'];
      if (ids is List) {
        roleIds = ids.map((e) => e.toString()).join(',');
      } else if (ids != null) {
        roleIds = ids.toString();
      }

      String? accessJson;
      final access = extraMap['roles'];
      if (access is Map) {
        accessJson = jsonEncode(Map<String, dynamic>.from(access));
      }

      if (role.isNotEmpty) {
        await SecureStore.setUserRole(role: role, roleIds: roleIds, roleAccessJson: accessJson);
      }
    } catch (_) {
      return;
    }
  }
}
