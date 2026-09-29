import '../../core/network/api_service.dart';
import '../../core/utils/app_logger.dart';

/// Fan-to-artist tipping (strategy doc §4): POST /api/dist/tip sends a
/// wallet tip to the track's uploader/manager. Wallet top-up runs through
/// Razorpay on the backend.
class TipService {
  TipService._();
  static final TipService instance = TipService._();

  final _api = ApiService.instance;

  Future<TipWallet?> wallet() async {
    try {
      final res = await _api.postPayloadRaw(
        endpoint: 'dist/tip',
        data: const {'action': 'wallet'},
      );
      if (!res.isSuccess || res.data == null) return null;
      final w = res.data!['wallet'];
      if (w is! Map) return null;
      return TipWallet(
        balance: (w['balance'] as num?)?.toDouble() ?? 0,
        tipped: (w['tipped'] as num?)?.toDouble() ?? 0,
        earned: (w['earned'] as num?)?.toDouble() ?? 0,
      );
    } catch (e) {
      AppLogger.d('tip wallet fetch failed: $e');
      return null;
    }
  }

  Future<TipResult> sendTip({required String trackHash, required double amount, String? note}) async {
    try {
      final res = await _api.postPayloadRaw(endpoint: 'dist/tip', data: {
        'amount': amount.toStringAsFixed(2),
        'track_hash': trackHash,
        if (note != null && note.isNotEmpty) 'note': note,
      });
      if (!res.isSuccess) {
        return TipResult.fail(res.error?.message ?? 'tip_failed');
      }
      final err = res.data?['error'];
      if (err != null) return TipResult.fail(err is Map ? '${err['code'] ?? err['message'] ?? 'tip_failed'}' : '$err');
      return const TipResult.ok();
    } catch (e) {
      AppLogger.d('tip send failed: $e');
      return TipResult.fail('exception');
    }
  }
}

class TipWallet {
  final double balance, tipped, earned;
  const TipWallet({required this.balance, required this.tipped, required this.earned});
}

class TipResult {
  final bool success;
  final String? error;
  const TipResult.ok()
      : success = true,
        error = null;
  const TipResult.fail(this.error)
      : success = false;
}
