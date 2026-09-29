import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';
import '../config/client_config_service.dart';
import '../profile/user_edit_service.dart';

/// Talks to the backend `developer_*` endpoints that power the public
/// Developer API portal (third-party apps embedding/playing HiTune catalog).
///
/// Contract lives in `docs/BACKEND_REQUIREMENTS.md` section 15 and
/// `docs/DEVELOPER_API.md`. The whole feature is gated on
/// `client_config.setting.developer_portal` — until the backend ships it,
/// [isPortalEnabled] is false and the UI stays hidden.
class DeveloperService {
  DeveloperService._();
  static final DeveloperService instance = DeveloperService._();

  final ApiService _api = ApiService.instance;

  /// True when the backend advertises the developer portal via
  /// `client_config` (`developer_portal` at top level or under `setting`,
  /// bool/int/string/`{"enabled": true}` all accepted).
  bool get isPortalEnabled {
    final cfg = ClientConfigService().config;
    if (cfg == null) return false;
    dynamic v = cfg['developer_portal'];
    final setting = cfg['setting'];
    if (v == null && setting is Map) v = setting['developer_portal'];
    if (v is Map) v = v['enabled'];
    return v == true || v == 1 || v == '1' || v == 'true';
  }

  Future<ApiResult<JsonMap>> fetchPlans() =>
      _api.postPayloadRaw(endpoint: 'developer_plans');

  Future<ApiResult<JsonMap>> fetchApps() =>
      _api.postPayloadRaw(endpoint: 'developer_apps');

  Future<ApiResult<JsonMap>> createApp({
    required String name,
    String website = '',
    String platform = 'web',
  }) =>
      _api.postPayloadRaw(endpoint: 'developer_app_create', data: {
        'name': name,
        'website': website,
        'platform': platform,
      });

  Future<ApiResult<JsonMap>> updateApp({
    required String hash,
    String? name,
    String? website,
  }) =>
      _api.postPayloadRaw(endpoint: 'developer_app_update', data: {
        'hash': hash,
        if (name != null) 'name': name,
        if (website != null) 'website': website,
      });

  Future<ApiResult<JsonMap>> deleteApp(String hash) =>
      _api.postPayloadRaw(endpoint: 'developer_app_delete', data: {'hash': hash});

  /// `which` is `secret` or `publishable`. The regenerated `client_secret`
  /// is only present in this single response.
  Future<ApiResult<JsonMap>> regenerateKey({
    required String hash,
    required String which,
  }) =>
      _api.postPayloadRaw(
          endpoint: 'developer_key_regenerate',
          data: {'hash': hash, 'which': which});

  Future<ApiResult<JsonMap>> fetchUsage(String hash, {String period = '30d'}) =>
      _api.postPayloadRaw(
          endpoint: 'developer_usage', data: {'hash': hash, 'period': period});

  /// Starts a paid developer-plan subscription; backend returns a payment
  /// link (same shape as `purchase_subs_plan`).
  Future<ApiResult<JsonMap>> subscribe({
    required String planHash,
    String? appHash,
  }) =>
      _api.postPayloadRaw(endpoint: 'developer_subscribe', data: {
        'plan_hash': planHash,
        if (appHash != null && appHash.isNotEmpty) 'app_hash': appHash,
      });

  /// Extracts a checkout URL from a subscribe response — preferred
  /// `subscribe_link` hook first, then the broad URL scan shared with the
  /// subscription flow.
  static String? extractPaymentLink(JsonMap data) {
    final link = data['link'] ?? data['url'] ?? data['payment_url'];
    if (link != null && link.toString().isNotEmpty) return link.toString();
    final messages = data['messages'];
    if (messages is List) {
      for (final m in messages) {
        if (m is Map && m['hook'] == 'subscribe_link' && m['link'] != null) {
          return m['link'].toString();
        }
      }
    }
    return UserEditService.extractPaymentUrl(data);
  }

  /// Normalizes `plans`/`apps`/`items` payload fields that may arrive as a
  /// JSON object keyed by hash (PHP assoc arrays) or a plain list.
  static List<JsonMap> mapList(JsonMap? payload, List<String> keys) {
    if (payload == null) return const [];
    for (final k in keys) {
      final v = payload[k];
      if (v is Map) {
        return v.values
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (v is List) {
        return v
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return const [];
  }

  static String strOf(JsonMap map, List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final v = map[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return fallback;
  }
}
