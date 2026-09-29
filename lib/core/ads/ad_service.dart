import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/utils/app_logger.dart';

class AdService {
  AdService._();

  static final AdService instance = AdService._();

  // Test Ad Unit IDs - Replace with your actual AdMob Ad Unit IDs from https://admob.google.com/
  // Android Test IDs
  static const String _androidBannerTestId = 'ca-app-pub-3940256099942544/6300978111';
  static const String _androidInterstitialTestId = 'ca-app-pub-3940256099942544/1033173712';

  // iOS Test IDs
  static const String _iosBannerTestId = 'ca-app-pub-3940256099942544/2934735716';
  static const String _iosInterstitialTestId = 'ca-app-pub-3940256099942544/4411468910';

  // Rewarded Ad Test IDs
  static const String _androidRewardedTestId = 'ca-app-pub-3940256099942544/5224354917';
  static const String _iosRewardedTestId = 'ca-app-pub-3940256099942544/1712485313';

  // Production Ad Unit IDs - override via --dart-define or .env
  // Test IDs are used as fallback until you set real AdMob IDs.
  static const String _androidBannerId = String.fromEnvironment(
    'HITUNE_ADMOB_ANDROID_BANNER_ID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const String _androidInterstitialId = String.fromEnvironment(
    'HITUNE_ADMOB_ANDROID_INTERSTITIAL_ID',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );
  static const String _iosBannerId = String.fromEnvironment(
    'HITUNE_ADMOB_IOS_BANNER_ID',
    defaultValue: 'ca-app-pub-3940256099942544/2934735716',
  );
  static const String _iosInterstitialId = String.fromEnvironment(
    'HITUNE_ADMOB_IOS_INTERSTITIAL_ID',
    defaultValue: 'ca-app-pub-3940256099942544/4411468910',
  );

  // Set to true to use test ads, false for production
  bool _isTestMode = true;

  // Banner Ad
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;
  bool get isBannerLoaded => _isBannerLoaded;

  // Interstitial Ad
  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoading = false;

  // Rewarded Ad
  RewardedAd? _rewardedAd;
  bool _isRewardedLoading = false;
  Function()? _onRewardedAdClosed;

  // Song counter for interstitial frequency
  int _songPlayCount = 0;
  int _songsSinceLastAd = 0;

  // Config: Show interstitial every N songs (Spotify-like behavior)
  // Default: Show ad every 3-5 songs
  int _interstitialFrequency = 4;
  int get interstitialFrequency => _interstitialFrequency;

  // Minimum seconds between ads (to avoid annoying users)
  DateTime? _lastInterstitialShown;
  static const Duration _minAdInterval = Duration(seconds: 120);

  // Streams
  final StreamController<bool> _bannerAdController = StreamController<bool>.broadcast();
  Stream<bool> get bannerAdStream => _bannerAdController.stream;

  /// Initialize AdMob SDK.
  /// Pass [testMode: true] during development to use Google's test ad units.
  Future<void> initialize({bool testMode = true}) async {
    _isTestMode = testMode;

    await MobileAds.instance.initialize();
    AppLogger.d('[AdService] AdMob initialized. Test mode: $_isTestMode');

    // Preload interstitial ad
    _loadInterstitialAd();
  }

  /// Get the appropriate ad unit ID based on platform and mode.
  /// When [testMode] is true, Google's test ad units are always used.
  String _getAdUnitId({required bool isBanner, required bool isInterstitial}) {
    if (Platform.isAndroid) {
      if (isBanner) {
        return _isTestMode ? _androidBannerTestId : _androidBannerId;
      } else if (isInterstitial) {
        return _isTestMode ? _androidInterstitialTestId : _androidInterstitialId;
      }
    } else if (Platform.isIOS) {
      if (isBanner) {
        return _isTestMode ? _iosBannerTestId : _iosBannerId;
      } else if (isInterstitial) {
        return _isTestMode ? _iosInterstitialTestId : _iosInterstitialId;
      }
    }
    // Default to Android test ID if platform unknown
    return isBanner ? _androidBannerTestId : _androidInterstitialTestId;
  }

  /// Load and return a banner ad widget
  Widget getBannerAdWidget({double width = 320}) {
    if (_bannerAd == null || !_isBannerLoaded) {
      _loadBannerAd(width: width);
    }

    if (_bannerAd != null && _isBannerLoaded) {
      return SizedBox(
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    }

    // Return placeholder while loading
    return const SizedBox(
      width: 320,
      height: 50,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  /// Load banner ad
  void _loadBannerAd({double width = 320}) {
    if (_bannerAd != null) {
      _bannerAd!.dispose();
      _bannerAd = null;
    }

    final AdSize size = AdSize.banner;

    _bannerAd = BannerAd(
      adUnitId: _getAdUnitId(isBanner: true, isInterstitial: false),
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          AppLogger.d('[AdService] Banner ad loaded');
          _isBannerLoaded = true;
          _bannerAdController.add(true);
        },
        onAdFailedToLoad: (ad, error) {
          AppLogger.d('[AdService] Banner ad failed to load: $error');
          _isBannerLoaded = false;
          _bannerAd = null;
          ad.dispose();
        },
        onAdOpened: (ad) => AppLogger.d('[AdService] Banner ad opened'),
        onAdClosed: (ad) => AppLogger.d('[AdService] Banner ad closed'),
      ),
    );

    _bannerAd!.load();
  }

  /// Load interstitial ad
  void _loadInterstitialAd() {
    if (_isInterstitialLoading) return;
    if (_interstitialAd != null) return;

    _isInterstitialLoading = true;

    InterstitialAd.load(
      adUnitId: _getAdUnitId(isBanner: false, isInterstitial: true),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          AppLogger.d('[AdService] Interstitial ad loaded');
          _interstitialAd = ad;
          _isInterstitialLoading = false;

          // Set up ad callbacks
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (ad) {
              AppLogger.d('[AdService] Interstitial ad showed');
              _lastInterstitialShown = DateTime.now();
            },
            onAdDismissedFullScreenContent: (ad) {
              AppLogger.d('[AdService] Interstitial ad dismissed');
              ad.dispose();
              _interstitialAd = null;
              // Preload next ad
              _loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              AppLogger.d('[AdService] Interstitial ad failed to show: $error');
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialLoading = false;
            },
            onAdImpression: (ad) => AppLogger.d('[AdService] Interstitial ad impression recorded'),
          );
        },
        onAdFailedToLoad: (error) {
          AppLogger.d('[AdService] Interstitial ad failed to load: $error');
          _interstitialAd = null;
          _isInterstitialLoading = false;
          // Retry after delay
          Future.delayed(const Duration(seconds: 30), () {
            AppLogger.d('[AdService] Retrying interstitial load...');
            _loadInterstitialAd();
          });
        },
      ),
    );
  }

  /// Check if interstitial ad should be shown based on song frequency
  bool shouldShowInterstitial() {
    // Check minimum interval between ads
    if (_lastInterstitialShown != null) {
      final timeSinceLastAd = DateTime.now().difference(_lastInterstitialShown!);
      if (timeSinceLastAd < _minAdInterval) {
        AppLogger.d('[AdService] Too soon for another ad. Time since last: ${timeSinceLastAd.inSeconds}s');
        return false;
      }
    }

    // Check song frequency
    AppLogger.d('[AdService] Songs since last ad: $_songsSinceLastAd / $_interstitialFrequency');

    if (_songsSinceLastAd >= _interstitialFrequency) {
      return true;
    }

    return false;
  }

  /// Show interstitial ad if ready
  /// Returns true if ad was shown, false otherwise
  Future<bool> showInterstitialIfReady() async {
    if (!shouldShowInterstitial()) {
      return false;
    }

    if (_interstitialAd == null) {
      AppLogger.d('[AdService] Interstitial not ready, loading...');
      _loadInterstitialAd();
      return false;
    }

    try {
      await _interstitialAd!.show();
      _songsSinceLastAd = 0; // Reset counter
      return true;
    } catch (e) {
      AppLogger.d('[AdService] Failed to show interstitial: $e');
      _interstitialAd = null;
      _loadInterstitialAd();
      return false;
    }
  }

  /// Force show interstitial ad (for manual ad triggers)
  Future<bool> showInterstitial() async {
    if (_interstitialAd == null) {
      AppLogger.d('[AdService] Interstitial not ready, loading...');
      _loadInterstitialAd();
      // Wait a bit and try again
      await Future.delayed(const Duration(seconds: 2));
      if (_interstitialAd == null) {
        return false;
      }
    }

    try {
      await _interstitialAd!.show();
      _songsSinceLastAd = 0;
      return true;
    } catch (e) {
      AppLogger.d('[AdService] Failed to show interstitial: $e');
      return false;
    }
  }

  /// Set test mode
  void setTestMode(bool testMode) {
    _isTestMode = testMode;
    AppLogger.d('[AdService] Test mode set to: $_isTestMode');
  }
  void setInterstitialFrequency(int frequency) {
    if (frequency < 1) return;
    _interstitialFrequency = frequency;
    AppLogger.d('[AdService] Interstitial frequency set to: $frequency songs');
  }

  /// Track song played (called when a song starts playing)
  void trackSongPlayed() {
    _songPlayCount++;
    _songsSinceLastAd++;
    AppLogger.d('[AdService] Song play count: $_songPlayCount, Songs since last ad: $_songsSinceLastAd');
  }

  /// Get ad statistics
  Map<String, dynamic> getAdStats() {
    return {
      'songPlayCount': _songPlayCount,
      'songsSinceLastAd': _songsSinceLastAd,
      'interstitialFrequency': _interstitialFrequency,
      'interstitialReady': _interstitialAd != null,
      'bannerLoaded': _isBannerLoaded,
      'lastInterstitialShown': _lastInterstitialShown?.toIso8601String(),
      'isTestMode': _isTestMode,
    };
  }

  /// Dispose banner ad
  void disposeBannerAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isBannerLoaded = false;
  }

  /// Load rewarded ad
  Future<void> loadRewardedAd() async {
    if (_isRewardedLoading) return;
    if (_rewardedAd != null) return;

    _isRewardedLoading = true;

    final adUnitId = Platform.isAndroid
        ? (_isTestMode ? _androidRewardedTestId : _androidRewardedTestId) // Use test ID for now
        : (_isTestMode ? _iosRewardedTestId : _iosRewardedTestId);

    await RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          AppLogger.d('[AdService] Rewarded ad loaded');
          _rewardedAd = ad;
          _isRewardedLoading = false;

          // Set up ad callbacks
          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (ad) {
              AppLogger.d('[AdService] Rewarded ad showed');
            },
            onAdDismissedFullScreenContent: (ad) {
              AppLogger.d('[AdService] Rewarded ad dismissed');
              _onRewardedAdClosed?.call();
              _onRewardedAdClosed = null;
              ad.dispose();
              _rewardedAd = null;
              // Preload next ad
              loadRewardedAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              AppLogger.d('[AdService] Rewarded ad failed to show: $error');
              _onRewardedAdClosed?.call();
              _onRewardedAdClosed = null;
              ad.dispose();
              _rewardedAd = null;
              _isRewardedLoading = false;
            },
            onAdImpression: (ad) => AppLogger.d('[AdService] Rewarded ad impression recorded'),
          );
        },
        onAdFailedToLoad: (error) {
          AppLogger.d('[AdService] Rewarded ad failed to load: $error');
          _rewardedAd = null;
          _isRewardedLoading = false;
          // Retry after delay
          Future.delayed(const Duration(seconds: 30), () {
            AppLogger.d('[AdService] Retrying rewarded ad load...');
            loadRewardedAd();
          });
        },
      ),
    );
  }

  /// Show rewarded ad and return true if user earned reward
  Future<bool> showRewardedAd({required VoidCallback onRewardEarned}) async {
    if (_rewardedAd == null) {
      AppLogger.d('[AdService] Rewarded ad not ready, loading...');
      await loadRewardedAd();
      await Future.delayed(const Duration(seconds: 2));
      if (_rewardedAd == null) {
        return false;
      }
    }

    try {
      // Set up reward callback
      _rewardedAd!.onUserEarnedRewardCallback = (ad, reward) {
        AppLogger.d('[AdService] User earned reward: ${reward.amount} ${reward.type}');
        onRewardEarned();
      };

      // Set up close callback
      _onRewardedAdClosed = () {
        AppLogger.d('[AdService] Rewarded ad closed');
      };

      await _rewardedAd!.show(onUserEarnedReward: (ad, reward) {
        AppLogger.d('[AdService] Reward earned in show callback');
      });

      return true;
    } catch (e) {
      AppLogger.d('[AdService] Failed to show rewarded ad: $e');
      return false;
    }
  }

  /// Dispose all ads
  void dispose() {
    disposeBannerAd();
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _bannerAdController.close();
  }
}
