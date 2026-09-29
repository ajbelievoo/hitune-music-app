import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';
import '../../core/storage/secure_storage.dart';

class ManagedArtist {
  final String id;
  final String name;
  final String slug;

  const ManagedArtist({required this.id, required this.name, required this.slug});

  static ManagedArtist? fromBofClientItem(dynamic item) {
    if (item is! Map) return null;
    final m = Map<String, dynamic>.from(item);
    final id = (m['id'] ?? m['ID'] ?? '').toString();
    final title = (m['title'] ?? m['name'] ?? '').toString();
    final slug = (m['slug'] ?? m['hash'] ?? '').toString();
    if (slug.isEmpty) return null;
    return ManagedArtist(id: id, name: title.isEmpty ? slug : title, slug: slug);
  }
}

class AnalyticsService {
  final ApiService _api = ApiService.instance;

  /// Fetch artist details including stats using BOF client object single endpoint.
  /// Backend pattern: POST /bofClient/single/m_artist/?slug=<slug>
  Future<ApiResult<Map<String, dynamic>>> fetchArtistAnalytics({required String artistSlug}) async {
    final endpoint = 'bofClient/single/m_artist/?slug=${Uri.encodeQueryComponent(artistSlug)}';
    final res = await _api.postPayloadRaw(endpoint: endpoint);
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final payload = res.data!;
    final data = payload['data'];
    if (data is Map) {
      return ApiResult.success(Map<String, dynamic>.from(data));
    }

    return ApiResult.failure(
      const ApiError(code: 'invalid_artist_analytics', message: 'Artist analytics response did not contain expected payload'),
    );
  }

  /// Managed artists are those with m_artist.manager_id = current user ID.
  /// Backend filter is available as bofClient browse filter: col_manager
  Future<ApiResult<List<ManagedArtist>>> fetchManagedArtists() async {
    final userId = await SecureStore.getUserId();
    if (userId == null || userId.isEmpty) {
      return ApiResult.failure(const ApiError(code: 'missing_user_id', message: 'User ID not available. Sync client_config first.'));
    }

    final endpoint = 'bofClient/browse/m_artist/?col_manager=${Uri.encodeQueryComponent(userId)}';
    final res = await _api.postPayloadRaw(endpoint: endpoint);
    if (!res.isSuccess) return ApiResult.failure(res.error!);

    final payload = res.data!;
    final widgets = payload['widgets'];
    if (widgets is List && widgets.isNotEmpty) {
      final widget0 = widgets.first;
      if (widget0 is Map && widget0['items'] is List) {
        final items = widget0['items'] as List;
        final out = <ManagedArtist>[];
        for (final it in items) {
          final a = ManagedArtist.fromBofClientItem(it);
          if (a != null) out.add(a);
        }
        return ApiResult.success(out);
      }
    }

    return ApiResult.failure(const ApiError(code: 'invalid_managed_artists', message: 'Managed artists response did not contain expected payload'));
  }
}
