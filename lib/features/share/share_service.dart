import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';

class ShareService {
  ShareService._();
  static final ShareService instance = ShareService._();

  final ApiService _api = ApiService.instance;

  /// Fetch share data for a track/object
  /// Returns: { item: {...}, embedable: [...] }
  Future<ApiResult<Map<String, dynamic>>> fetchShareData({
    required String objectType,
    required String objectHash,
  }) async {
    return _api.postRaw(
      endpoint: 'share',
      data: {
        'object_type': objectType,
        'object_hash': objectHash,
      },
    );
  }

  /// Build embed URL for a track
  String buildEmbedUrl({
    required String objectType,
    required String objectHash,
    bool darkMode = true,
    String? accentColor, // hex without #
  }) {
    final baseUrl = 'https://music.hitune.in/muse_embed/$objectType/$objectHash/';
    final params = <String, String>{};
    
    if (darkMode) {
      params['_dark'] = '1';
    }
    if (accentColor != null && accentColor.isNotEmpty) {
      params['_m_color'] = accentColor.replaceAll('#', '');
    }
    
    if (params.isEmpty) {
      return baseUrl;
    }
    
    final queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$baseUrl?$queryString';
  }

  /// Build share URL (web link) using BOF framework format
  String buildShareUrl({
    required String objectType,
    required String objectHash,
    String? slug,
  }) {
    // BOF framework single_url_prefix format:
    // m_track -> music/track/{hash}/
    // m_album -> music/album/{hash}/
    // m_artist -> music/artist/{hash}/ or music/artist/{slug}/
    
    String urlPath;
    switch (objectType) {
      case 'm_track':
        urlPath = 'music/track';
        break;
      case 'm_album':
        urlPath = 'music/album';
        break;
      case 'm_artist':
        urlPath = 'music/artist';
        break;
      default:
        urlPath = 'music/$objectType';
    }
    
    if (slug != null && slug.isNotEmpty) {
      // Use slug if available (for SEO-friendly URLs)
      return 'https://music.hitune.in/$urlPath/$slug/';
    }
    
    // Fallback to hash-based URL
    return 'https://music.hitune.in/$urlPath/$objectHash/';
  }
}
