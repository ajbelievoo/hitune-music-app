import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';

/// In-app purchase facade.
///
/// Full store billing requires:
/// - `in_app_purchase` package configured with Play Console / App Store Connect
/// - backend endpoint `verify_purchase` that validates the receipt and grants
///   the plan (documented in docs/BACKEND_REQUIREMENTS.md)
///
/// Until the store products exist this service reports unavailability so the
/// UI falls back to the external `UpgradePlansScreen` flow.
class PurchaseService {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  bool _checked = false;
  bool _storeAvailable = false;

  bool get isAvailable => _checked && _storeAvailable;

  Future<void> initialize() async {
    if (_checked) return;
    _checked = true;
    // Store billing is enabled only when the backend advertises it via
    // client_config -> setting.iap_enabled == true AND the native billing
    // client reports available. Kept false until store products are created.
    _storeAvailable = false;
  }

  /// Backend verification hook. Call this from the IAP stream when a purchase
  /// completes; the backend must set the user's plan server-side.
  Future<ApiResult<void>> verifyReceipt({
    required String productId,
    required String purchaseToken,
    required String platform,
  }) async {
    final res = await ApiService.instance.postRaw(
      endpoint: 'verify_purchase',
      data: {
        'product_id': productId,
        'purchase_token': purchaseToken,
        'platform': platform,
      },
    );
    if (!res.isSuccess) return ApiResult.failure(res.error!);
    return ApiResult.success(null);
  }
}
