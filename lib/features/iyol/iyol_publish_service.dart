import '../../core/network/api_service.dart';
import '../../core/utils/app_logger.dart';
import '../player/models/track.dart';

/// "Publish as Reel on IyolMe" flow (strategy doc §5):
///   ai_studio clip_video job -> vertical mp4 render -> /api/iyol_publish
///   -> IyolMe creates the reel with mandatory audio attribution.
class IyolPublishService {
  IyolPublishService._();
  static final IyolPublishService instance = IyolPublishService._();

  final _api = ApiService.instance;

  /// Renders a vertical clip for [track] (start/duration seconds) and
  /// publishes it to IyolMe. Returns a user-facing status string.
  Future<IyolPublishResult> publishTrack(
    Track track, {
    int start = 0,
    int duration = 30,
    String? caption,
  }) async {
    try {
      final submit = await _api.postPayloadRaw(endpoint: 'ai_studio', data: {
        'action': 'submit',
        'type': 'clip_video',
        'track_hash': track.objectHash ?? track.id,
        'start': '$start',
        'duration': '$duration',
      });
      final job = submit.data?['job'];
      if (!submit.isSuccess || job is! Map) {
        return IyolPublishResult.fail(
            submit.data?['error']?['code']?.toString() ?? submit.error?.message ?? 'render_failed');
      }
      var fileId = job['file_id'];
      var status = '${job['status']}';
      if (status == 'failed') {
        return IyolPublishResult.fail('${job['error'] ?? 'render_failed'}');
      }
      // queued engines (demucs etc.) process async — poll briefly
      for (var i = 0;
          i < 25 && (status == 'pending' || status == 'processing');
          i++) {
        await Future.delayed(const Duration(seconds: 3));
        final s = await _api.postPayloadRaw(
            endpoint: 'ai_studio',
            data: {'action': 'status', 'job_id': '${job['id']}'});
        final sj = s.data?['job'];
        if (sj is Map) {
          status = '${sj['status']}';
          fileId = sj['file_id'];
        }
      }
      if (fileId == null || status != 'done') {
        return IyolPublishResult.fail('render_timeout');
      }

      final pub = await _api.postPayloadRaw(endpoint: 'iyol_publish', data: {
        'file_id': '$fileId',
        'media_type': 'video',
        'track_hash': track.objectHash ?? track.id,
        'caption': caption ?? track.title,
        'duration_ms': '${duration * 1000}',
      });
      if (!pub.isSuccess || pub.data == null) {
        return IyolPublishResult.fail(pub.error?.message ?? 'publish_failed');
      }
      final iyol = pub.data!['iyol'];
      final reelUrl = iyol is Map ? (iyol['reel_url'] ?? iyol['url'])?.toString() : null;
      return IyolPublishResult.ok(reelUrl);
    } catch (e) {
      AppLogger.d('iyol publish failed: $e');
      return IyolPublishResult.fail('exception');
    }
  }
}

class IyolPublishResult {
  final bool success;
  final String? reelUrl;
  final String? error;
  const IyolPublishResult.ok(this.reelUrl)
      : success = true,
        error = null;
  const IyolPublishResult.fail(this.error)
      : success = false,
        reelUrl = null;
}
