import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';
import '../config/client_config_service.dart';

class UserEditService {
  final ApiService _api = ApiService.instance;

  // Helper to check for 403 in response messages
  ApiResult<Map<String, dynamic>>? _check403(Map<String, dynamic> data) {
    final messages = data['messages'];
    if (messages is List) {
      for (final msg in messages) {
        if (msg.toString() == '403') {
          return ApiResult.failure(const ApiError(code: '403', message: 'Session expired or unauthorized'));
        }
      }
    }
    return null;
  }

  Future<ApiResult<Map<String, dynamic>>> fetchTab({
    required String tab,
  }) async {
    // Use ClientConfigService startup sequencing to prevent CPU spike
    return ClientConfigService().runInStartupSequence(() async {
      final endpoint = 'user_edit?tab=${Uri.encodeQueryComponent(tab)}';
      final res = await _api.postPayloadRaw(endpoint: endpoint);
      if (!res.isSuccess) return ApiResult.failure(res.error!);

      final data = res.data;
      if (data is! Map<String, dynamic>) {
        return ApiResult.failure(const ApiError(code: 'invalid_user_edit', message: 'user_edit payload is not a JSON object'));
      }

      // Check for 403 in messages array (backend sends 403 as a message, not HTTP status)
      final forbidden = _check403(data);
      if (forbidden != null) return forbidden;

      return ApiResult.success(data);
    }, name: 'user_edit_$tab');
  }

  Future<ApiResult<Map<String, dynamic>>> revokeSession({
    required String sessionId,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'user_edit_single_item_rem',
      data: {
        'type': 'sessions',
        'item': sessionId,
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(res.data ?? <String, dynamic>{});
  }

  Future<ApiResult<Map<String, dynamic>>> submitProfile({
    required String name,
    String? bio,
    String? avatarId,
    String? coverId,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'user_edit?tab=profile&action=submit',
      data: {
        'name': name,
        if (bio != null && bio.isNotEmpty) 'bio': bio,
        if (avatarId != null && avatarId.isNotEmpty) 'avatar_id': avatarId,
        if (coverId != null && coverId.isNotEmpty) 'bg_img_id': coverId,
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(res.data ?? <String, dynamic>{});
  }

  Future<ApiResult<Map<String, dynamic>>> uploadFile({
    required String filePath,
    required String type,
  }) async {
    debugPrint('[UPLOAD] Starting file upload: path=$filePath, type=$type');
    
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[UPLOAD] File does not exist: $filePath');
      return ApiResult.failure(const ApiError(code: 'file_not_found', message: 'File does not exist'));
    }
    
    debugPrint('[UPLOAD] File exists, size: ${await file.length()} bytes');

    try {
      final mp = await http.MultipartFile.fromPath(r'$file', filePath);
      debugPrint('[UPLOAD] Multipart file created, fieldName=${mp.field}, length=${mp.length}');
      
      final res = await _api.postMultipart(
        endpoint: 'upload?type=image&object_type=${Uri.encodeQueryComponent(type)}',
        fields: {},
        files: [mp],
      );
      
      debugPrint('[UPLOAD] postMultipart result: isSuccess=${res.isSuccess}, data=${res.data}, error=${res.error?.message}');
      
      if (!res.isSuccess) return ApiResult.failure(res.error!);
      return ApiResult.success(res.data ?? <String, dynamic>{});
    } catch (e, st) {
      debugPrint('[UPLOAD] Exception during upload: $e');
      debugPrint('[UPLOAD] Stack trace: $st');
      return ApiResult.failure(ApiError(code: 'upload_exception', message: e.toString()));
    }
  }

  Future<ApiResult<String?>> uploadAvatar({
    required String filePath,
  }) async {
    final res = await uploadFile(filePath: filePath, type: 'user_avatar');
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    // Backend returns file ID in response
    final fileId = res.data?['ID']?.toString() ?? res.data?['id']?.toString() ?? res.data?['file_id']?.toString();
    return ApiResult.success(fileId);
  }

  Future<ApiResult<String?>> uploadCover({
    required String filePath,
  }) async {
    final res = await uploadFile(filePath: filePath, type: 'user_bg');
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    final fileId = res.data?['ID']?.toString() ?? res.data?['id']?.toString() ?? res.data?['file_id']?.toString();
    return ApiResult.success(fileId);
  }

  Future<ApiResult<Map<String, dynamic>>> submitSecurity({
    required String oldPassword,
    String? newPassword,
    bool? socialLoginEnabled,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'user_edit?tab=security&action=submit',
      data: {
        'old_password': oldPassword,
        if (newPassword != null && newPassword.isNotEmpty) 'new_password': newPassword,
        if (newPassword != null && newPassword.isNotEmpty) 'new_password_verify': newPassword,
        if (socialLoginEnabled != null) 'social_login': socialLoginEnabled ? '1' : '0',
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(res.data ?? <String, dynamic>{});
  }

  Future<ApiResult<Map<String, dynamic>>> submitLinks({
    required Map<String, String> links,
  }) async {
    debugPrint('[SOCIAL_LINKS] Sending data: $links');
    final res = await _api.postRaw(
      endpoint: 'user_edit?tab=links&action=submit',
      data: links,
    );
    debugPrint('[SOCIAL_LINKS] Response: isSuccess=${res.isSuccess}, error=${res.error?.message}, data=${res.data}');
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(res.data ?? <String, dynamic>{});
  }

  Future<ApiResult<Map<String, dynamic>>> submitNotifications({
    required Map<String, bool> notifications,
    bool? emailNotifications,
  }) async {
    final data = <String, String>{};
    for (final entry in notifications.entries) {
      data[entry.key] = entry.value ? '1' : '0';
    }
    if (emailNotifications != null) {
      data['__email__'] = emailNotifications ? '1' : '0';
    }
    debugPrint('[NOTIFICATIONS] Sending data: $data');
    final res = await _api.postRaw(
      endpoint: 'user_edit?tab=notifications&action=submit',
      data: data,
    );
    debugPrint('[NOTIFICATIONS] Response: isSuccess=${res.isSuccess}, error=${res.error?.message}, data=${res.data}');
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(res.data ?? <String, dynamic>{});
  }

  Future<ApiResult<Map<String, dynamic>>> submitDelete({
    required String password,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'user_edit?tab=delete&action=submit',
      data: {
        'password': password,
        'delete_account': '1',
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(res.data ?? <String, dynamic>{});
  }

  Future<ApiResult<Map<String, dynamic>>> initializePayment() async {
    final res = await _api.postRaw(endpoint: 'user_pay_ini');
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(res.data ?? <String, dynamic>{});
  }

  Future<ApiResult<Map<String, dynamic>>> getPaymentLink({
    required String gateway,
    required double amount,
    Map<String, dynamic>? purchaseData,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'user_pay_get_link',
      data: {
        'gateway': gateway,
        'amount': amount.toString(),
        if (purchaseData != null) 'purchase_data': jsonEncode(purchaseData),
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(res.data ?? <String, dynamic>{});
  }

  /// Deep-scan a payment response for a checkout URL. Different backend
  /// builds return it under different keys (subscribe_link hook, link,
  /// url, redirect, ...) so probe the common spots and any URL-looking
  /// string inside `messages` items.
  static String? extractPaymentUrl(Map<String, dynamic> data) {
    const urlKeys = [
      'link', 'url', 'payment_url', 'redirect', 'redirect_url', 'href',
      'checkout_url', 'invoice_url', 'approval_url', 'subscribe_link',
    ];

    String? pick(Map node) {
      for (final k in urlKeys) {
        final v = node[k];
        if (v is String && v.startsWith('http')) return v;
        // subscribe_link hook may wrap the URL in a map
        if (v is Map) {
          final inner = pick(v);
          if (inner != null) return inner;
        }
      }
      return null;
    }

    final top = pick(data);
    if (top != null) return top;

    final msg = data['message'];
    if (msg is String && msg.startsWith('http')) return msg;
    if (msg is Map) {
      final r = pick(Map<String, dynamic>.from(msg));
      if (r != null) return r;
    }

    final messages = data['messages'];
    if (messages is List) {
      for (final m in messages) {
        if (m is String && m.startsWith('http')) return m;
        if (m is Map) {
          final r = pick(Map<String, dynamic>.from(m));
          if (r != null) return r;
          for (final v in m.values) {
            if (v is String && v.startsWith('http')) return v;
          }
        }
      }
    }

    for (final k in const ['data', 'payload', 'result']) {
      final inner = data[k];
      if (inner is Map) {
        final r = extractPaymentUrl(Map<String, dynamic>.from(inner));
        if (r != null) return r;
      }
    }
    return null;
  }
}
