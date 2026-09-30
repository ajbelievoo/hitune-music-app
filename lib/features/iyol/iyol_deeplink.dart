import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/app_logger.dart';
import '../player/models/track.dart';

/// Deep links into the IyolMe app (short-video companion).
///
///   iyolme://reel/create?hitune_track_hash=..&title=..&artist=..&cover=..
///     -> IyolMe resolves/registers the sound and opens the camera with
///        the song attached ("Create Reel" from any track).
///   iyolme://story/<id>
///     -> opens a story in IyolMe (used by the home stories rail).
///
/// When IyolMe isn't installed we fall back to https://iyolme.com which
/// routes to the store listing.
class IyolDeepLink {
  IyolDeepLink._();

  static const _storeUrl =
      'https://play.google.com/store/apps/details?id=com.vidmite.app&hl=en_IN';
  static const _hituneWeb = 'https://music.hitune.in/';

  static Uri createReel(Track track) {
    final params = <String, String>{
      'hitune_track_hash': track.id,
      'title': track.title,
      if ((track.subtitle ?? '').isNotEmpty) 'artist': track.subtitle!,
      if ((track.coverUrl ?? '').isNotEmpty) 'cover': track.coverUrl!,
      if (track.durationSeconds != null && track.durationSeconds! > 0)
        'duration_ms': (track.durationSeconds! * 1000).toString(),
      'hitune_url': '${_hituneWeb}track/${track.id}',
      'attribution_label': 'Original Sound on HiTune Music',
      if (track.aiPct > 0) 'ai_pct': track.aiPct.toString(),
      if (track.aiPct > 0) 'ai_badge': 'AI Original',
    };
    return Uri(scheme: 'iyolme', host: 'reel', path: '/create', queryParameters: params);
  }

  static Uri story(int storyId) =>
      Uri(scheme: 'iyolme', host: 'story', path: '/$storyId');

  /// Open IyolMe to create a reel with [track] attached. Returns true
  /// when the app link was handed off, false when we fell back to web.
  static Future<bool> openReelCreate(Track track) async {
    return _open(createReel(track));
  }

  static Future<bool> openStory(int storyId) async {
    return _open(story(storyId));
  }

  static Future<bool> _open(Uri deepLink) async {
    try {
      final ok = await launchUrl(deepLink, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (e) {
      AppLogger.d('[IyolDeepLink] launch failed: $e');
    }
    try {
      return await launchUrl(Uri.parse(_storeUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.d('[IyolDeepLink] fallback launch failed: $e');
      return false;
    }
  }
}
