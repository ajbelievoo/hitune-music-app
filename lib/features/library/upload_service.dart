import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';
import '../../core/utils/app_logger.dart';

class UploadService {
  final ApiService _api = ApiService.instance;

  /// Upload a file to the server and return file_id and file_pass
  Future<ApiResult<Map<String, dynamic>>> uploadFile(
    File file, {
    String fileType = 'audio',
    String objectType = 'track',
  }) async {
    // Validate file exists and has content
    if (!await file.exists()) {
      return ApiResult.failure(const ApiError(
        code: 'file_not_found',
        message: 'File does not exist',
      ));
    }

    final fileSize = await file.length();
    if (fileSize == 0) {
      return ApiResult.failure(const ApiError(
        code: 'file_empty',
        message: 'File is empty (0 bytes)',
      ));
    }

    AppLogger.d('[UploadService] Uploading file: ${file.path}');
    AppLogger.d('[UploadService] File size: $fileSize bytes');
    AppLogger.d('[UploadService] File name: ${file.path.split('/').last}');

    final bytes = await file.readAsBytes();
    final multipartFile = http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: file.path.split('/').last,
    );

    final res = await _api.postMultipart(
      endpoint: 'upload',
      fields: {
        'type': fileType,
        'object_type': objectType,
      },
      files: [multipartFile],
    );

    if (!res.isSuccess) {
      AppLogger.d('[UploadService] Upload failed: ${res.error?.code} - ${res.error?.message}');
      return ApiResult.failure(res.error!);
    }

    final data = res.data;
    if (data == null) {
      return ApiResult.failure(const ApiError(code: 'invalid_response', message: 'No response data'));
    }

    // Debug: print full response
    AppLogger.d('[UploadService] API Response: ${jsonEncode(data)}');

    // Extract file info from response - backend returns directly in response
    // Format: {"type": "audio", "file_id": 123, "file_pass": "abc", "file_preview": "..."}
    final fileId = data['file_id'];
    final filePass = data['file_pass'];
    if (fileId == null || filePass == null) {
      return ApiResult.failure(const ApiError(code: 'invalid_response', message: 'Invalid file upload response'));
    }

    final fileData = {
      'ID': fileId,
      'pass': filePass,
      'type': data['type'],
      'preview': data['file_preview'],
    };

    AppLogger.d('[UploadService] File uploaded successfully: ID=$fileId, pass=$filePass');
    return ApiResult.success(fileData);
  }

  Future<ApiResult<Map<String, dynamic>>> getUploadConfig() async {
    final res = await _api.postRaw(endpoint: 'user_upload_config');
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final decoded = res.data;
    if (decoded == null) {
      return ApiResult.failure(const ApiError(code: 'invalid_config', message: 'Upload config payload missing'));
    }

    final msgs = decoded['messages'];
    if (msgs is List && msgs.isNotEmpty && msgs.first.toString() == '403') {
      return ApiResult.failure(const ApiError(code: 'forbidden', message: 'Forbidden. Login required.'));
    }

    final payload = _api.postPayloadRaw(endpoint: 'user_upload_config');
    final unwrapped = await payload;
    if (!unwrapped.isSuccess) return ApiResult.failure(unwrapped.error!);
    final data = unwrapped.data;
    if (data is! Map<String, dynamic>) {
      return ApiResult.failure(const ApiError(code: 'invalid_config', message: 'Upload config payload is not a JSON object'));
    }

    return ApiResult.success(data);
  }

  Future<ApiResult<Map<String, dynamic>>> verifySources({
    required Map<String, dynamic> contentData,
    required Map<String, dynamic> sourceData,
    required Map<String, dynamic> givenData,
  }) async {
    // Backend expects JSON strings in these specific fields
    final data = <String, String>{
      'content_data': jsonEncode(contentData),
      'source_data': jsonEncode(sourceData),
      'given_data': jsonEncode(givenData),
    };

    final res = await _api.postRaw(
      endpoint: 'user_upload_verify_sources',
      data: data,
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final decoded = res.data;
    final msgs = decoded?['messages'];
    if (msgs is List && msgs.isNotEmpty && msgs.first.toString() == '403') {
      return ApiResult.failure(const ApiError(code: 'forbidden', message: 'Forbidden. Login required.'));
    }

    final payload = _api.postPayloadRaw(endpoint: 'user_upload_verify_sources', data: data);
    final unwrapped = await payload;
    if (!unwrapped.isSuccess) return ApiResult.failure(unwrapped.error!);
    final data2 = unwrapped.data;
    if (data2 is! Map<String, dynamic>) {
      return ApiResult.failure(const ApiError(code: 'invalid_response', message: 'Invalid response format'));
    }

    return ApiResult.success(data2);
  }

  Future<ApiResult<Map<String, dynamic>>> verifyGroup({
    required String contentType,
    required String groupHash,
    required int groupNumber,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'user_upload_verify_group',
      data: {
        'content_type': contentType,
        'group_hash': groupHash,
        'group_number': groupNumber.toString(),
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final decoded = res.data;
    final msgs = decoded?['messages'];
    if (msgs is List && msgs.isNotEmpty && msgs.first.toString() == '403') {
      return ApiResult.failure(const ApiError(code: 'forbidden', message: 'Forbidden. Login required.'));
    }

    final payload = _api.postPayloadRaw(
      endpoint: 'user_upload_verify_group',
      data: {
        'content_type': contentType,
        'group_hash': groupHash,
        'group_number': groupNumber.toString(),
      },
    );
    final unwrapped = await payload;
    if (!unwrapped.isSuccess) return ApiResult.failure(unwrapped.error!);
    final data = unwrapped.data;
    if (data is! Map<String, dynamic>) {
      return ApiResult.failure(const ApiError(code: 'invalid_response', message: 'Invalid response format'));
    }

    return ApiResult.success(data);
  }

  Future<ApiResult<Map<String, dynamic>>> submitUpload({
    required String groupHash,
    required List<Map<String, dynamic>> items,
    required String contentType,
    required String sourceType,
    required Map<String, dynamic> verifiedSource,
  }) async {
    final data = <String, String>{
      'content_data': jsonEncode({'ID': contentType}),
      'source_data': jsonEncode({'ID': sourceType}),
      'source_id': groupHash,
      'verified_source': jsonEncode(verifiedSource),
    };

    // Backend expects fields in format: groupHash_field_name
    // e.g., 69c2fc7bc72ee_title, 69c2fc7bc72ee_artist_name
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      // Map our field names to backend expected field names
      // Only send these specific fields, ignore others like file_id, file_pass
      // NOTE: BOF bof_file type expects groupHash_cover = file_id and groupHash_cover_file_pass = file_pass
      // Track stores: cover=URL, cover_file_id=fileID, cover_file_pass=filePass
      final fieldMapping = {
        'title': '${groupHash}_title',
        'artist_name': '${groupHash}_artist_name',  // Track has 'artist_name', backend expects 'artist_name'
        'album_id': '${groupHash}_album_id',
        'release_date': '${groupHash}_release_date',
        'description': '${groupHash}_description',
        'cover_file_id': '${groupHash}_cover',  // cover_file_id -> groupHash_cover (backend expects file_id here)
        'cover_file_pass': '${groupHash}_cover_file_pass',  // file_pass for bof_file
      };

      item.forEach((key, value) {
        if (fieldMapping.containsKey(key)) {
          // Send empty string for null values, but only for fields in our mapping
          final finalValue = (value ?? '').toString();
          data[fieldMapping[key]!] = finalValue;
        }
      });
    }

    AppLogger.d('[UploadService] Submit data: $data');
    AppLogger.d('[DEBUG-BACKEND] ===== FULL submitUpload DATA =====');
    AppLogger.d('[DEBUG-BACKEND] ${jsonEncode(data)}');
    AppLogger.d('[DEBUG-BACKEND] ===== END DATA =====');

    final res = await _api.postRaw(
      endpoint: 'user_upload_submit',
      data: data,
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final decoded = res.data;
    final msgs = decoded?['messages'];
    if (msgs is List && msgs.isNotEmpty && msgs.first.toString() == '403') {
      return ApiResult.failure(const ApiError(code: 'forbidden', message: 'Forbidden. Login required.'));
    }

    final payload = _api.postPayloadRaw(endpoint: 'user_upload_submit', data: data);
    final unwrapped = await payload;
    if (!unwrapped.isSuccess) return ApiResult.failure(unwrapped.error!);
    final data2 = unwrapped.data;
    if (data2 is! Map<String, dynamic>) {
      return ApiResult.failure(const ApiError(code: 'invalid_response', message: 'Invalid response format'));
    }

    return ApiResult.success(data2);
  }

  Future<ApiResult<Map<String, dynamic>>> editSingleItemInit({
    required String itemHash,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'user_edit_single_item_ini',
      data: {'item_hash': itemHash},
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final decoded = res.data;
    final msgs = decoded?['messages'];
    if (msgs is List && msgs.isNotEmpty && msgs.first.toString() == '403') {
      return ApiResult.failure(const ApiError(code: 'forbidden', message: 'Forbidden. Login required.'));
    }

    final payload = _api.postPayloadRaw(
      endpoint: 'user_edit_single_item_ini',
      data: {'item_hash': itemHash},
    );
    final unwrapped = await payload;
    if (!unwrapped.isSuccess) return ApiResult.failure(unwrapped.error!);
    final data = unwrapped.data;
    if (data is! Map<String, dynamic>) {
      return ApiResult.failure(const ApiError(code: 'invalid_response', message: 'Invalid response format'));
    }

    return ApiResult.success(data);
  }

  Future<ApiResult<Map<String, dynamic>>> editSingleItem({
    required String itemHash,
    required Map<String, dynamic> data,
  }) async {
    final formData = <String, String>{
      'item_hash': itemHash,
    };

    data.forEach((key, value) {
      if (value != null) {
        formData[key] = value.toString();
      }
    });

    final res = await _api.postRaw(
      endpoint: 'user_edit_single_item',
      data: formData,
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final decoded = res.data;
    final msgs = decoded?['messages'];
    if (msgs is List && msgs.isNotEmpty && msgs.first.toString() == '403') {
      return ApiResult.failure(const ApiError(code: 'forbidden', message: 'Forbidden. Login required.'));
    }

    final payload = _api.postPayloadRaw(endpoint: 'user_edit_single_item', data: formData);
    final unwrapped = await payload;
    if (!unwrapped.isSuccess) return ApiResult.failure(unwrapped.error!);
    final data2 = unwrapped.data;
    if (data2 is! Map<String, dynamic>) {
      return ApiResult.failure(const ApiError(code: 'invalid_response', message: 'Invalid response format'));
    }

    return ApiResult.success(data2);
  }

  Future<ApiResult<Map<String, dynamic>>> removeSingleItem({
    required String itemHash,
  }) async {
    final res = await _api.postRaw(
      endpoint: 'user_edit_single_item_rem',
      data: {'item_hash': itemHash},
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final decoded = res.data;
    final msgs = decoded?['messages'];
    if (msgs is List && msgs.isNotEmpty && msgs.first.toString() == '403') {
      return ApiResult.failure(const ApiError(code: 'forbidden', message: 'Forbidden. Login required.'));
    }

    final payload = _api.postPayloadRaw(
      endpoint: 'user_edit_single_item_rem',
      data: {'item_hash': itemHash},
    );
    final unwrapped = await payload;
    if (!unwrapped.isSuccess) return ApiResult.failure(unwrapped.error!);
    final data = unwrapped.data;
    if (data is! Map<String, dynamic>) {
      return ApiResult.failure(const ApiError(code: 'invalid_response', message: 'Invalid response format'));
    }

    return ApiResult.success(data);
  }
}
