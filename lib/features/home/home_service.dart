import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';
import 'package:flutter/foundation.dart';

class HomeService {
  final ApiService _api = ApiService.instance;

  Future<ApiResult<Map<String, dynamic>>> fetchHomePage() async {
    debugPrint('[HOME] Fetching home page...');
    final res = await _api.postPayloadRaw(endpoint: 'bofClient/single/page/?slug=home');
    if (!res.isSuccess) {
      debugPrint('[HOME] Home API failed: ${res.error?.message}');
      return ApiResult.failure(res.error!);
    }

    final data = res.data;
    debugPrint('[HOME] Home API raw response type: ${data.runtimeType}');
    if (data is Map<String, dynamic>) {
      debugPrint('[HOME] Home API response keys: ${data.keys}');
      if (data.containsKey('widgets')) {
        final widgets = data['widgets'];
        debugPrint('[HOME] widgets type: ${widgets.runtimeType}, length: ${widgets is List ? widgets.length : widgets is Map ? widgets.length : 'N/A'}');
      }
      return ApiResult.success(data);
    }

    return ApiResult.failure(const ApiError(code: 'invalid_home', message: 'Home response did not contain expected payload'));
  }
}
