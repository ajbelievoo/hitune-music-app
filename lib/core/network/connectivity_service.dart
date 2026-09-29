import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Lightweight connectivity watcher. Polls a known host so no extra package
/// is required; swap for connectivity_plus later if richer state is needed.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService._() {
    // Singleton service - the periodic timer lives for the app's lifetime.
    Timer.periodic(const Duration(seconds: 8), (_) => _check());
    _check();
    _typeSub = Connectivity().onConnectivityChanged.listen((results) {
      _types = results.toSet();
      notifyListeners();
    });
    Connectivity().checkConnectivity().then((r) => _types = r.toSet());
  }
  static final ConnectivityService instance = ConnectivityService._();

  bool _online = true;
  Set<ConnectivityResult> _types = {};
  StreamSubscription<List<ConnectivityResult>>? _typeSub;

  bool get isOnline => _online;

  /// True when the device is on WiFi/ethernet — i.e. data is effectively
  /// unmetered and high-bitrate streams are safe.
  bool get isWifi =>
      _types.contains(ConnectivityResult.wifi) ||
      _types.contains(ConnectivityResult.ethernet);

  /// True when the active connection is mobile data (metered).
  bool get isMobileData => _types.contains(ConnectivityResult.mobile);

  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onlineStream => _controller.stream;

  Future<void> _check() async {
    var online = true;
    try {
      final res = await InternetAddress.lookup('music.hitune.in').timeout(const Duration(seconds: 4));
      online = res.isNotEmpty && res.first.rawAddress.isNotEmpty;
    } catch (_) {
      online = false;
    }
    if (online != _online) {
      _online = online;
      _controller.add(online);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _typeSub?.cancel();
    _controller.close();
    super.dispose();
  }
}
