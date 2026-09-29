import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../security/signature.dart';
import '../storage/secure_storage.dart';
import 'api_result.dart';
import 'device_headers.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonParser<T> = T Function(JsonMap json);

class ApiService {
  ApiService._(this._http);

  static final ApiService instance = ApiService._(http.Client());

  final http.Client _http;

  Map<String, String>? _deviceHeaders;

  void _log(String message) {
    if (!AppConfig.enableApiLogs) return;
    debugPrint(message);
  }

  String _extractMessageText(JsonMap decoded) {
    final msgs = decoded['messages'];
    if (msgs is List && msgs.isNotEmpty) {
      return msgs.map((e) => e.toString()).join(' | ');
    }

    final message = decoded['message'];
    if (message == null) return 'Request failed';
    if (message is String) return message;
    if (message is Map) {
      final m = Map<String, dynamic>.from(message);
      final t = m['message']?.toString();
      if (t != null && t.isNotEmpty) return t;
      return m.toString();
    }

    return message.toString();
  }

  String _extractErrorCode(JsonMap decoded, {required int httpStatus}) {
    final err = decoded['error']?.toString();
    if (err != null && err.isNotEmpty) return err;
    final code = decoded['code']?.toString();
    if (code != null && code.isNotEmpty) return code;
    return 'http_$httpStatus';
  }

  /// Extracts a JSON object embedded in a noisy body. Some PHP code paths
  /// print notices ("Warning: ... <br/>") before the real JSON — grab the
  /// outermost {...} span and parse that instead of failing outright.
  static JsonMap? _salvageJson(String body) {
    final start = body.indexOf('{');
    final end = body.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final obj = json.decode(body.substring(start, end + 1));
      if (obj is Map<String, dynamic>) return obj;
    } catch (_) {}
    return null;
  }

  JsonMap? _tryUnwrapBofPayload(JsonMap decoded) {
    // Many endpoints wrap the real payload inside:
    // - { messages: [ { ...payload... } ] }
    // - { message: { ...payload... } }
    // Keep this conservative: only unwrap when the wrapper is clearly present.
    final msg = decoded['messages'];
    if (msg is List && msg.isNotEmpty && msg.first is Map) {
      return Map<String, dynamic>.from(msg.first as Map);
    }

    final message = decoded['message'];
    if (message is Map) {
      return Map<String, dynamic>.from(message);
    }

    return null;
  }

  Future<Map<String, String>> _getDeviceHeaders() async {
    final cached = _deviceHeaders;
    if (cached != null) return cached;

    final headers = await DeviceHeaders.build();
    _deviceHeaders = headers;
    return headers;
  }

  Future<Map<String, String>> _buildHeaders({required bool isAdmin}) async {
    final device = await _getDeviceHeaders();

    // Backend client loader forces supported_platforms to ['web'].
    // Sending anything else fails comparator_platform and returns 403.
    const devicePlatform = 'web';

    final headers = <String, String>{
      // Send both canonical and lowercase variants; HTTP header names are
      // case-insensitive, but some proxy stacks can be quirky.
      'X-Bof-Request-Code': AppConfig.requestCode,
      'x-bof-request-code': AppConfig.requestCode,
      // Backend validates this against supported_platforms.
      'X-Bof-Platform': devicePlatform,
      'x-bof-platform': devicePlatform,
      'X-Bof-Version': AppConfig.bofVersion.toString(),
      'x-bof-version': AppConfig.bofVersion.toString(),
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
      ...device,
    };

    final sessKey = isAdmin ? await SecureStore.getAdminSessKey() : await SecureStore.getUserSessKey();
    if (sessKey != null && sessKey.isNotEmpty) {
      headers['x-bof-sess-key'] = sessKey;
      headers['X-Bof-Sess-Key'] = sessKey;
    }

    final sessId = isAdmin ? await SecureStore.getAdminSessId() : await SecureStore.getUserSessId();
    if (sessId != null && sessId.isNotEmpty) {
      headers['Cookie'] = 'PHPSESSID=$sessId';
    }

    final token = isAdmin ? await SecureStore.getAdminToken() : await SecureStore.getUserToken();
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }

    return headers;
  }

  Future<ApiResult<T>> postForm<T>({
    required String endpoint,
    required Map<String, String> data,
    required JsonParser<T> parse,
    bool isAdmin = false,
  }) async {
    Map<String, String> _sortedByKey(Map<String, String> input) {
      final keys = input.keys.toList()..sort();
      final out = <String, String>{};
      for (final k in keys) {
        final v = input[k];
        if (v != null) out[k] = v;
      }
      return out;
    }

    final signKey = isAdmin ? AppConfig.adminSignKey : AppConfig.signKey;
    if (signKey.isEmpty) {
      return ApiResult.failure(const ApiError(
        code: 'missing_sign_key',
        message: 'API sign key is not configured',
      ));
    }

    // Build the POST payload exactly like PHP:
    // - ksort() equivalent: sort fields A-Z by key
    // - signature is computed over the sorted fields EXCLUDING bof_signature
    // - send all fields + bof_signature as x-www-form-urlencoded with spaces as '+'
    final cleanData = <String, String>{...data}..remove('bof_signature');

    // Some BOF deployments read the client session from POST fields (sess_id/sess_key)
    // instead of headers/cookies for API requests. Add them as a fallback for user
    // endpoints (non-admin) when present.
    if (!isAdmin) {
      final userSessId = await SecureStore.getUserSessId();
      final userSessKey = await SecureStore.getUserSessKey();
      if (userSessId != null && userSessId.isNotEmpty) {
        cleanData.putIfAbsent('sess_id', () => userSessId);
      }
      if (userSessKey != null && userSessKey.isNotEmpty) {
        cleanData.putIfAbsent('sess_key', () => userSessKey);
      }
    }
    // Backend comparator unsets bof_signature and then expects remaining $_POST
    // to be non-empty to compute http_build_query(...) and validate the signature.
    // For endpoints with no parameters (e.g. client_config), ensure at least one
    // stable field is present so the signature is not computed over an empty payload.
    if (cleanData.isEmpty) {
      cleanData['bof_ping'] = '1';
    }
    final sortedData = _sortedByKey(cleanData);
    final signature = Signature.compute(formData: sortedData, signKey: signKey, spaceAsPlus: true);
    final payloadWithSig = <String, String>{...sortedData, 'bof_signature': signature};
    final bodyStringToSend = Signature.buildPhpQueryString(payloadWithSig, spaceAsPlus: true);

    final headers = await _buildHeaders(isAdmin: isAdmin);
    headers['X-Bof-Signature'] = signature;

    final url = Uri.parse('${AppConfig.apiBaseUrl}$endpoint');

    try {
      _log('[API] POST $endpoint');
      final res = await _http.post(
        url,
        headers: headers,
        body: bodyStringToSend,
      );

      final bodyString = res.body;
      JsonMap decoded;
      try {
        final obj = json.decode(bodyString);
        decoded = (obj is Map<String, dynamic>) ? obj : <String, dynamic>{'raw': obj};
      } catch (e) {
        // PHP backends sometimes print notices/warnings before the JSON
        // body on authenticated code paths — salvage the embedded object
        // before declaring the response unparseable.
        final salvaged = _salvageJson(bodyString);
        if (salvaged == null) {
          _log('[API] $endpoint -> ${res.statusCode} invalid_json');
          return ApiResult.failure(ApiError(
            code: 'invalid_json',
            message: 'Invalid JSON response',
            httpStatus: res.statusCode,
            cause: e,
          ));
        }
        decoded = salvaged;
      }

      final succ = decoded['success'];
      _log('[API] $endpoint -> ${res.statusCode} success=$succ');

      if (res.statusCode != 200) {
        return ApiResult.failure(ApiError(
          code: _extractErrorCode(decoded, httpStatus: res.statusCode),
          message: _extractMessageText(decoded),
          httpStatus: res.statusCode,
        ));
      }

      if (succ is bool && succ == false) {
        return ApiResult.failure(ApiError(
          code: decoded['error']?.toString() ?? 'api_error',
          message: _extractMessageText(decoded),
          httpStatus: res.statusCode,
        ));
      }

      final status = decoded['status']?.toString();
      if (status != null && status.toLowerCase() != 'ok') {
        _log('[API] $endpoint non_ok status=$status');
        return ApiResult.failure(ApiError(
          code: decoded['error']?.toString() ?? 'api_error',
          message: _extractMessageText(decoded),
          httpStatus: res.statusCode,
        ));
      }

      return ApiResult.success(parse(decoded));
    } on SocketException catch (e) {
      return ApiResult.failure(ApiError(
        code: 'network_socket',
        message: 'Network unavailable',
        cause: e,
      ));
    } on HttpException catch (e) {
      return ApiResult.failure(ApiError(
        code: 'network_http',
        message: 'HTTP error',
        cause: e,
      ));
    } on FormatException catch (e) {
      return ApiResult.failure(ApiError(
        code: 'invalid_format',
        message: 'Invalid response format',
        cause: e,
      ));
    } catch (e) {
      return ApiResult.failure(ApiError(
        code: 'network_error',
        message: 'Network request failed',
        cause: e,
      ));
    }
  }

  Future<ApiResult<JsonMap>> postRaw({
    required String endpoint,
    Map<String, String> data = const {},
    bool isAdmin = false,
  }) {
    return postForm<JsonMap>(
      endpoint: endpoint,
      data: data,
      isAdmin: isAdmin,
      parse: (json) => json,
    );
  }

  /// Like [postRaw] but tries to unwrap common BOF wrappers.
  ///
  /// This keeps existing call sites stable while allowing new or migrated
  /// features to depend on a consistent payload shape.
  Future<ApiResult<JsonMap>> postPayloadRaw({
    required String endpoint,
    Map<String, String> data = const {},
    bool isAdmin = false,
  }) async {
    final res = await postRaw(endpoint: endpoint, data: data, isAdmin: isAdmin);
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final decoded = res.data;
    if (decoded == null) {
      return ApiResult.failure(const ApiError(code: 'invalid_payload', message: 'Response payload missing'));
    }

    final unwrapped = _tryUnwrapBofPayload(decoded);
    return ApiResult.success(unwrapped ?? decoded);
  }

  Future<ApiResult<JsonMap>> postMultipart({
    required String endpoint,
    required Map<String, String> fields,
    required List<http.MultipartFile> files,
    bool isAdmin = false,
  }) async {
    Map<String, String> _sortedByKey(Map<String, String> input) {
      final keys = input.keys.toList()..sort();
      final out = <String, String>{};
      for (final k in keys) {
        final v = input[k];
        if (v != null) out[k] = v;
      }
      return out;
    }

    final signKey = isAdmin ? AppConfig.adminSignKey : AppConfig.signKey;
    if (signKey.isEmpty) {
      return ApiResult.failure(const ApiError(code: 'missing_sign_key', message: 'API sign key is not configured'));
    }

    final cleanFields = <String, String>{...fields}..remove('bof_signature');

    // Add session keys for user endpoints (same as postForm)
    if (!isAdmin) {
      final userSessId = await SecureStore.getUserSessId();
      final userSessKey = await SecureStore.getUserSessKey();
      if (userSessId != null && userSessId.isNotEmpty) {
        cleanFields.putIfAbsent('sess_id', () => userSessId);
      }
      if (userSessKey != null && userSessKey.isNotEmpty) {
        cleanFields.putIfAbsent('sess_key', () => userSessKey);
      }
    }

    if (cleanFields.isEmpty) {
      cleanFields['bof_ping'] = '1';
    }
    final sortedFields = _sortedByKey(cleanFields);
    final signature = Signature.compute(formData: sortedFields, signKey: signKey, spaceAsPlus: true);

    final headers = await _buildHeaders(isAdmin: isAdmin);
    headers['X-Bof-Signature'] = signature;

    final url = Uri.parse('${AppConfig.apiBaseUrl}$endpoint');
    final req = http.MultipartRequest('POST', url);
    req.headers.addAll(headers);
    req.fields.addAll({...sortedFields, 'bof_signature': signature});
    req.files.addAll(files);

    try {
      _log('[API] POST(MULTIPART) $endpoint');

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);

      JsonMap decoded;
      try {
        final obj = json.decode(res.body);
        decoded = (obj is Map<String, dynamic>) ? obj : <String, dynamic>{'raw': obj};
      } catch (e) {
        final salvaged = _salvageJson(res.body);
        if (salvaged == null) {
          return ApiResult.failure(ApiError(
            code: 'invalid_json',
            message: 'Invalid JSON response',
            httpStatus: res.statusCode,
            cause: e,
          ));
        }
        decoded = salvaged;
      }

      final succ = decoded['success'];
      _log('[API] $endpoint -> ${res.statusCode} success=$succ');

      if (res.statusCode != 200) {
        return ApiResult.failure(ApiError(
          code: _extractErrorCode(decoded, httpStatus: res.statusCode),
          message: _extractMessageText(decoded),
          httpStatus: res.statusCode,
        ));
      }

      if (succ is bool && succ == false) {
        return ApiResult.failure(ApiError(
          code: decoded['error']?.toString() ?? 'api_error',
          message: _extractMessageText(decoded),
          httpStatus: res.statusCode,
        ));
      }

      final status = decoded['status']?.toString();
      if (status != null && status.toLowerCase() != 'ok') {
        return ApiResult.failure(ApiError(
          code: decoded['error']?.toString() ?? 'api_error',
          message: _extractMessageText(decoded),
          httpStatus: res.statusCode,
        ));
      }

      return ApiResult.success(decoded);
    } on SocketException catch (e) {
      return ApiResult.failure(ApiError(code: 'network_socket', message: 'Network unavailable', cause: e));
    } on HttpException catch (e) {
      return ApiResult.failure(ApiError(code: 'network_http', message: 'HTTP error', cause: e));
    } catch (e) {
      return ApiResult.failure(ApiError(code: 'network_error', message: 'Network request failed', cause: e));
    }
  }
}
