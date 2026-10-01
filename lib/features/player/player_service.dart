import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../core/audio/audio_enhancer.dart';
import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/storage/song_cache.dart';
import '../../core/ads/ad_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../downloads/download_service.dart';
import '../home/recommendations_service.dart';
import '../browse/browse_feed_service.dart';
import 'models/track.dart';

enum AudioQuality {
  auto,
  kbps128,
  kbps320,
  kbps960, // Spotify-like high quality
  kbps1411, // Spotify-like very high quality
  kbps1600; // Maximum quality

  String get label {
    switch (this) {
      case AudioQuality.auto:
        return 'Auto';
      case AudioQuality.kbps128:
        return '128 kbps';
      case AudioQuality.kbps320:
        return '320 kbps';
      case AudioQuality.kbps960:
        return '960 kbps';
      case AudioQuality.kbps1411:
        return '1411 kbps';
      case AudioQuality.kbps1600:
        return '1600 kbps';
    }
  }
}

/// Video quality preference for the video surface. `auto` adapts to the
/// connection — WiFi allows up to 4K, mobile data caps at 480p to save
/// metered data. Manual tiers override the cap outright.
enum VideoQuality {
  auto,
  p480,
  p720,
  p1080,
  p2160;

  String get label {
    switch (this) {
      case VideoQuality.auto:
        return 'Auto (data saver)';
      case VideoQuality.p480:
        return '480p';
      case VideoQuality.p720:
        return '720p HD';
      case VideoQuality.p1080:
        return '1080p Full HD';
      case VideoQuality.p2160:
        return '4K';
    }
  }

  /// Pixel cap this tier enforces. `auto` resolves per-connection.
  int get pixels {
    switch (this) {
      case VideoQuality.auto:
        return 0;
      case VideoQuality.p480:
        return 480;
      case VideoQuality.p720:
        return 720;
      case VideoQuality.p1080:
        return 1080;
      case VideoQuality.p2160:
        return 2160;
    }
  }
}

/// A resolvable video stream candidate: [q] is the pixel height (0 when the
/// backend didn't report one).
typedef VideoStreamPick = ({int q, String url});

class PlayerService {
  PlayerService._();

  static final PlayerService instance = PlayerService._();

  // Prevent spamming backend for locked tracks.
  static const Duration _noAccessCooldown = Duration(seconds: 60);
  final Map<String, DateTime> _noAccessUntil = {};

  /// Dedicated video-stream URL per track id — video tracks resolve an
  /// audio-only stream for just_audio AND a muxed stream for the video
  /// surface. Two players on one URL starve each other and double-decode.
  final Map<String, String> _videoUrlByTrackId = {};

  /// All video stream candidates per track id — lets the quality picker
  /// re-select a different rendition without re-resolving the track.
  final Map<String, List<VideoStreamPick>> _videoCandidatesByTrackId = {};

  /// Video stream URL for the surface, or null when the audio URL itself
  /// is the video stream (backend direct sources, clips).
  String? videoUrlFor(String trackId) => _videoUrlByTrackId[trackId];

  /// Video candidates (quality + url) resolved for this track, if any.
  List<VideoStreamPick> videoCandidatesFor(String trackId) =>
      _videoCandidatesByTrackId[trackId] ?? const [];

  /// Overrides the video surface URL — used by the manual quality picker.
  void overrideVideoUrl(String trackId, String url) {
    _videoUrlByTrackId[trackId] = url;
  }

  VideoQuality _videoQuality = VideoQuality.auto;

  VideoQuality get videoQuality => _videoQuality;

  Future<void> setVideoQuality(VideoQuality q) async {
    _videoQuality = q;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player_video_quality', q.name);
  }

  /// Pixel-height cap for the video surface under the current preference.
  int get _videoCapPx {
    if (_videoQuality != VideoQuality.auto) return _videoQuality.pixels;
    // Auto: WiFi can afford 4K, mobile data caps at 480p to save data.
    return ConnectivityService.instance.isWifi ? 2160 : 480;
  }

  /// Pick the best candidate at-or-under the cap; when nothing fits the cap
  /// take the smallest stream rather than blowing the data budget.
  String? _pickCappedCandidate(List<VideoStreamPick> cands) {
    if (cands.isEmpty) return null;
    final cap = _videoCapPx;
    VideoStreamPick? best;
    VideoStreamPick? smallest;
    for (final c in cands) {
      if (smallest == null || c.q < smallest.q) smallest = c;
      // q<=0 means "quality unknown" — always selectable.
      final underCap = c.q <= 0 || c.q <= cap;
      if (underCap && (best == null || c.q > best.q)) best = c;
    }
    return (best ?? smallest)!.url;
  }

  /// Best video URL for [trackId] under the current quality preference —
  /// falls back to whatever stream was resolved when no candidate list
  /// was captured (backend single-file sources).
  String? pickVideoUrl(String trackId) {
    final picked = _pickCappedCandidate(_videoCandidatesByTrackId[trackId] ?? const []);
    return picked ?? _videoUrlByTrackId[trackId];
  }

  /// Restores the video stream + its candidate list from a cached
  /// song-url entry.
  void _restoreVideoFromCache(Track t, Map<String, dynamic> cached) {
    final vUrl = cached['videoUrl']?.toString();
    if (vUrl != null && vUrl.isNotEmpty) _videoUrlByTrackId[t.id] = vUrl;
    final cands = cached['videoCandidates'];
    if (cands is List) {
      _videoCandidatesByTrackId[t.id] = [
        for (final c in cands)
          if (c is Map && (c['url'] ?? '').toString().isNotEmpty)
            (
              q: int.tryParse('${c['q'] ?? 0}') ?? 0,
              url: (c['url'] ?? '').toString(),
            ),
      ];
    }
  }

  /// extraData for SongCache — persists the picked video URL plus the full
  /// candidate list so quality switching survives cache hits.
  Map<String, dynamic>? _videoCacheExtra(Track t) {
    final vUrl = _videoUrlByTrackId[t.id];
    if (vUrl == null || vUrl.isEmpty) return null;
    return {
      'videoUrl': vUrl,
      if ((_videoCandidatesByTrackId[t.id] ?? const []).isNotEmpty)
        'videoCandidates': [
          for (final c in _videoCandidatesByTrackId[t.id]!)
            {'q': c.q, 'url': c.url},
        ],
    };
  }

  /// The cached URL for this track just failed to load (dead link, expired
  /// googlevideo signature) — drop it so the next tap resolves fresh
  /// instead of replaying the same corpse from cache.
  void _evictCachedUrl(Track t) {
    final hash = t.objectHash;
    if (hash == null || hash.isEmpty) return;
    unawaited(SongCacheService.instance.clearSong(
      hash,
      (t.objectType == null || t.objectType!.isEmpty)
          ? 'm_track'
          : t.objectType!,
    ));
  }

  final AudioEnhancerService _enhancer = AudioEnhancerService.instance;

  // Direct YouTube stream extraction — public piped instances are mostly
  // dead on-device (DNS failures), so we resolve from YouTube itself first.
  YoutubeExplode? _ytExplode;
  YoutubeExplode get _ytClient => _ytExplode ??= YoutubeExplode();

  /// Extracts playable stream URLs straight from YouTube. Returns audio
  /// for music playback. For video tracks it returns an audio-only stream
  /// in [url] (for just_audio) plus the muxed stream in [videoUrl] (for the
  /// video surface) — two players on ONE muxed URL starve each other and
  /// double-decode the same bytes.
  Future<({String url, bool isVideo, String? videoUrl, List<VideoStreamPick> videoCandidates})?> _explodeYoutube(
    String youtubeId, {
    bool preferAudio = false,
  }) async {
    try {
      // The default android client's stream URLs get 403'd without a
      // poToken now — iOS/tv/VR clients still serve directly playable
      // googlevideo links.
      final manifest = await _ytClient.videos.streams
          .getManifest(youtubeId, ytClients: [
            YoutubeApiClient.ios,
            YoutubeApiClient.tv,
            YoutubeApiClient.androidVr,
            YoutubeApiClient.mweb,
          ])
          .timeout(const Duration(seconds: 5));
      final audioOnly = manifest.audioOnly.toList()
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      // Prefer mp4/m4a containers — just_audio decodes them everywhere.
      final mp4Audio =
          audioOnly.where((s) => s.container.name == 'mp4').toList();
      ({String url, bool isVideo, String? videoUrl, List<VideoStreamPick> videoCandidates})? audioPick() =>
          audioOnly.isEmpty
              ? null
              : (
                  url: (mp4Audio.isNotEmpty ? mp4Audio.first : audioOnly.first)
                      .url
                      .toString(),
                  isVideo: false,
                  videoUrl: null,
                  videoCandidates: const [],
                );
      if (preferAudio) return audioPick();
      final muxed = manifest.muxed.toList()
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      if (muxed.isNotEmpty) {
        // Keep every rendition so the quality picker can switch without
        // re-resolving; quality names look like "medium360"/"high720".
        final cands = <VideoStreamPick>[
          for (final s in muxed)
            (
              q: int.tryParse(s.videoQuality.name
                      .replaceAll(RegExp(r'[^0-9]'), '')) ??
                  0,
              url: s.url.toString(),
            ),
        ];
        final vUrl = _pickCappedCandidate(cands) ?? muxed.first.url.toString();
        final a = audioPick();
        return (
          url: a?.url ?? vUrl,
          isVideo: true,
          videoUrl: vUrl,
          videoCandidates: cands,
        );
      }
      return audioPick();
    } catch (e) {
      AppLogger.d('[PlayerService] explode failed for $youtubeId: $e');
      return null;
    }
  }
  late final AudioPlayer _player = AudioPlayer(
    audioPipeline: _enhancer.buildPipeline(),
  );
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);

  bool _isResolving = false;
  final _resolvingController = StreamController<bool>.broadcast();
  Stream<bool> get resolvingStream => _resolvingController.stream;
  bool get isResolving => _isResolving;

  void _setResolving(bool v) {
    if (_isResolving == v) return;
    _isResolving = v;
    _resolvingController.add(v);
  }

  String? _lastError;
  final _errorController = StreamController<String?>.broadcast();
  Stream<String?> get errorStream => _errorController.stream;
  String? get lastError => _lastError;

  void _setError(String? msg) {
    _lastError = msg;
    _errorController.add(msg);
  }

  StreamSubscription<PlayerState>? _playerStateSub;
  bool _skipOnErrorBusy = false;
  DateTime? _lastSkipOnErrorAt;
  int _skipOnErrorCount = 0;

  Track? _current;
  List<Track> _queue = const [];
  int _index = 0;
  String? _lastStartedTrackId;
  int _queueGeneration = 0;

  // The full list the user tapped on (before sibling resolution finishes).
  // Lets next/prev/skip work while the tapped track is still resolving.
  List<Track> _intendedTracks = const [];
  int _intendedIndex = 0;

  // Generation of the queue-fill currently running (-1 = none). Scoped to
  // the generation so a stale fill can't suppress a newer queue's fill.
  int _fillGeneration = -1;
  bool get _fillInProgress => _fillGeneration == _queueGeneration;

  StreamSubscription<int?>? _currentIndexSub;

  final ApiService _api = ApiService.instance;
  AudioQuality _quality = AudioQuality.auto;
  bool _qualityLoaded = false;

  final StreamController<Track?> _currentTrackController = StreamController<Track?>.broadcast();

  final StreamController<Set<String>> _likedController = StreamController<Set<String>>.broadcast();
  Set<String> _liked = <String>{};
  bool _likedLoaded = false;

  final StreamController<List<String>> _recentlyPlayedController = StreamController<List<String>>.broadcast();
  List<String> _recentlyPlayed = <String>[];
  bool _recentlyPlayedLoaded = false;
  static const int _maxRecentlyPlayed = 50;

  // Video player support
  final StreamController<String?> _sourceTypeController = StreamController<String?>.broadcast();
  String? _currentSourceType;
  Stream<String?> get sourceTypeStream => _sourceTypeController.stream;
  String? get currentSourceType => _currentSourceType;

  // Ad state tracking
  bool _adShowing = false;
  bool get isAdShowing => _adShowing;

  Timer? _museRecordDebounce;
  String? _lastMuseRecordHash;

  // --- Sleep timer ---
  Timer? _sleepTimer;
  Timer? _sleepTicker;
  DateTime? _sleepAt;
  bool _stopAfterTrack = false;
  final _sleepTimerController = StreamController<Duration?>.broadcast();
  Stream<Duration?> get sleepTimerStream => _sleepTimerController.stream;
  Duration? get sleepTimerRemaining {
    if (_stopAfterTrack) return null;
    final at = _sleepAt;
    if (at == null) return null;
    final left = at.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get isSleepTimerActive => _sleepAt != null || _stopAfterTrack;
  bool get stopAfterCurrentTrack => _stopAfterTrack;

  // --- Queue change broadcast (for queue UI refresh) ---
  final _queueController = StreamController<List<Track>>.broadcast();
  Stream<List<Track>> get queueStream => _queueController.stream;

  // --- Clips: short preview playback (Spotify-style) ---
  // While a clip is the active item, autoplay must not chain full songs on.
  bool _clipMode = false;

  // --- Autoplay: keep appending related tracks so playback never stops ---
  bool _autoplayEnabled = true;
  bool _autoplayLoaded = false;
  Future<void>? _autoplayFuture;
  final _autoplayController = StreamController<bool>.broadcast();

  /// Serializes structural mutations of [_playlist]. just_audio's
  /// ConcatenatingAudioSource deadlocks when clear()/addAll() race while it
  /// is the active source — a hung setAudioSource leaves _isResolving=true
  /// and every playback button goes dead.
  Future<void> _playlistOps = Future.value();

  Future<T> _syncPlaylistOp<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _playlistOps = _playlistOps.then((_) async {
      try {
        completer.complete(await op());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  bool get autoplayEnabled => _autoplayEnabled;
  Stream<bool> get autoplayStream => _autoplayController.stream;

  Future<void> setAutoplay(bool v) async {
    _autoplayEnabled = v;
    _autoplayController.add(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoplay_enabled', v);
  }

  Future<void> _ensureAutoplayLoaded() async {
    if (_autoplayLoaded) return;
    _autoplayLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    _autoplayEnabled = prefs.getBool('autoplay_enabled') ?? true;
    _autoplayController.add(_autoplayEnabled);
  }

  Future<void> _handleTrackStarted(Track t) async {
    await _addToRecentlyPlayed(t.id);
    unawaited(_maybeMuseRecord(t));

    // Track song for ad frequency
    AdService.instance.trackSongPlayed();
  }

  Future<void> _maybeMuseRecord(Track t) async {
    final objectHash = (t.objectHash == null || t.objectHash!.isEmpty) ? null : t.objectHash;
    if (objectHash == null) return;

    final sessKey = await SecureStore.getUserSessKey();
    final sessId = await SecureStore.getUserSessId();
    final loggedIn = (sessKey != null && sessKey.isNotEmpty) && (sessId != null && sessId.isNotEmpty);
    if (!loggedIn) return;

    if (_lastMuseRecordHash == objectHash) return;
    _lastMuseRecordHash = objectHash;

    _museRecordDebounce?.cancel();
    _museRecordDebounce = Timer(const Duration(seconds: 2), () async {
      try {
        await _api.postRaw(
          endpoint: 'muse_record',
          data: {
            'object_type': t.objectType ?? 'm_track',
            'object_hash': objectHash,
          },
        );
      } catch (_) {
        // Ignore tracking failures.
      }
    });
  }

  Track? get currentTrack => _current;
  Stream<Track?> get currentTrackStream => _currentTrackController.stream;

  List<Track> get queue => _queue;
  int get index => _index;

  /// Normalize the cover URL so the player / mini-player always gets a real image.
  Track _trackWithCover(Track t) {
    final cover = CoverImageExtractor.extract(t.coverUrl);
    if (cover == t.coverUrl) return t;
    return Track(
      id: t.id,
      title: t.title,
      url: t.url,
      subtitle: t.subtitle,
      coverUrl: cover,
      artistSlug: t.artistSlug,
      artistLink: t.artistLink,
      objectType: t.objectType,
      objectHash: t.objectHash,
      sourceType: t.sourceType,
      aiPct: t.aiPct,
    );
  }

  AudioPlayer get audioPlayer => _player;

  AudioQuality get quality => _quality;
  Stream<AudioQuality> get qualityStream async* {
    yield _quality;
  }

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  Stream<bool> get shuffleEnabledStream => _player.shuffleModeEnabledStream;
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;

  bool get isShuffleEnabled => _player.shuffleModeEnabled;
  LoopMode get loopMode => _player.loopMode;

  Stream<Set<String>> get likedIdsStream => _likedController.stream;
  Stream<List<String>> get recentlyPlayedIdsStream => _recentlyPlayedController.stream;

  void _setSourceType(String? type) {
    _currentSourceType = type;
    _sourceTypeController.add(type);
  }

  void _ensureIndexSync() {
    if (_currentIndexSub != null) return;
    unawaited(_ensureAutoplayLoaded());
    _currentIndexSub = _player.currentIndexStream.listen((i) {
      if (i == null) return;
      if (_queue.isEmpty) return;
      if (i < 0 || i >= _queue.length) return;
      _index = i;
      _current = _queue[_index];
      _currentTrackController.add(_current);
      _setSourceType(_current?.sourceType);
      // Playlist inserts during background queue-fill shift the index for the
      // SAME track — don't count that as a fresh track start.
      if (_lastStartedTrackId != _current!.id) {
        _lastStartedTrackId = _current!.id;
        _handleTrackStarted(_current!);
      }
      // Autoplay: refill the queue before it runs out so playback is endless.
      if (_autoplayEnabled && _index >= _queue.length - 3) {
        unawaited(_extendQueueWithRelated());
      }
    });

    _playerStateSub ??= _player.playerStateStream.listen((s) {
      if (_queue.isEmpty) return;
      if (s.processingState == ProcessingState.completed) {
        AppLogger.d('[PlayerService] Song completed - queue length: ${_queue.length}, current index: $_index');
        if (_player.loopMode == LoopMode.one) {
          AppLogger.d('[PlayerService] LoopMode.one - restarting current song');
          _player.seek(Duration.zero);
          _player.play();
          return;
        }
        // Sleep timer "end of track" - stop instead of advancing.
        if (_stopAfterTrack) {
          cancelSleepTimer();
          return;
        }

        // LoopMode.all auto-advance - ENABLED for automatic song change
        if (_player.loopMode == LoopMode.all) {
          if (_index >= _queue.length - 1) {
            AppLogger.d('[PlayerService] LoopMode.all - restarting from beginning');
            _player.seek(Duration.zero, index: 0);
            _player.play();
            return;
          }
        }

        // Show interstitial ad between songs (Spotify-like behavior)
        _maybeShowInterstitialAndAdvance();
        return;
      }
      if (s.processingState == ProcessingState.idle && _lastError != null) {
        _maybeSkipOnError();
      }
    });
  }

  Future<void> _maybeSkipOnError() async {
    if (_skipOnErrorBusy) return;
    if (_isResolving) return;
    if (_queue.isEmpty) return;
    if (_index >= _queue.length - 1) return;

    final now = DateTime.now();
    if (_lastSkipOnErrorAt != null && now.difference(_lastSkipOnErrorAt!) < const Duration(seconds: 2)) {
      return;
    }

    // Avoid infinite loops if many consecutive tracks are broken.
    if (_skipOnErrorCount >= 3) return;

    _skipOnErrorBusy = true;
    _lastSkipOnErrorAt = now;
    _skipOnErrorCount += 1;
    // Dead cached URL is the common failure — evict so a later tap
    // re-resolves instead of skipping through an entire broken queue.
    final failing = _current;
    if (failing != null) _evictCachedUrl(failing);
    try {
      // Auto-skip on error - ENABLED for better user experience
      await next();
    } catch (_) {
      // ignore
    } finally {
      _skipOnErrorBusy = false;
    }
  }

  /// Show interstitial ad between songs (Spotify-like behavior)
  /// Then advance to next track
  Future<void> _maybeShowInterstitialAndAdvance() async {
    // Don't show ad if we're at the end of queue — try autoplay first.
    if (_index >= _queue.length - 1) {
      AppLogger.d('[PlayerService] End of queue, extending via autoplay');
      unawaited(_autoplayAdvance());
      return;
    }

    // Check if ad should be shown
    if (AdService.instance.shouldShowInterstitial()) {
      AppLogger.d('[PlayerService] Showing interstitial ad between songs');
      _adShowing = true;

      // Pause briefly before showing ad
      await _player.pause();

      // Show the interstitial ad
      final adShown = await AdService.instance.showInterstitialIfReady();

      _adShowing = false;

      if (adShown) {
        AppLogger.d('[PlayerService] Interstitial ad shown, now advancing to next track');
        // Small delay after ad to ensure smooth transition
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        AppLogger.d('[PlayerService] Interstitial not ready, advancing immediately');
      }
    } else {
      AppLogger.d('[PlayerService] Skipping interstitial, not ready yet');
    }

    // Advance to next track — the playlist can hold fewer items than
    // _queue mid-fill, so seekToNext can throw RangeError on an
    // unawaited future (uncaught zone error).
    AppLogger.d('[PlayerService] Auto-advancing to next track');
    try {
      await _player.seekToNext();
      await _player.play();
    } catch (_) {}
  }

  /// Called when the queue runs out: fetch related tracks, then advance.
  Future<void> _autoplayAdvance() async {
    await _extendQueueWithRelated();
    if (_index < _queue.length - 1) {
      try {
        await _player.seekToNext();
        await _player.play();
      } catch (_) {
        // ignore
      }
    }
  }

  /// Appends related tracks to the end of the queue so playback continues
  /// indefinitely (iTunes/YouTube-Music style autoplay). Concurrent calls
  /// share one in-flight request.
  Future<void> _extendQueueWithRelated() {
    if (!_autoplayEnabled || _queue.isEmpty || _clipMode) return Future.value();
    // Live radio is endless on its own — don't seed music after it.
    final cur = _current;
    if (cur == null || cur.id.startsWith('radio:')) return Future.value();
    return _autoplayFuture ??= _doExtendQueue(cur).whenComplete(() {
      _autoplayFuture = null;
    });
  }

  Future<void> _doExtendQueue(Track seed) async {
    try {
      final existing = _queue.map((t) => t.objectHash ?? t.id).toSet();
      final candidates = <Track>[];

      void collect(List<Map<String, dynamic>>? items) {
        for (final item in items ?? const <Map<String, dynamic>>[]) {
          final t = RecommendationsService.itemToTrack(item);
          if (t == null) continue;
          final key = t.objectHash ?? t.id;
          if (key.isEmpty || !existing.add(key)) continue;
          candidates.add(t);
        }
      }

      // 1) Same/similar artists — search seeded by the current artist name.
      final artistName = (seed.subtitle ?? '').trim();
      if (artistName.isNotEmpty) {
        try {
          collect(await BrowseFeedService.instance.searchGenre([artistName]));
        } catch (_) {}
      }
      // 2) Taste-based: "because you listened" → recommendations → daily mix.
      try {
        collect(await RecommendationsService.instance.fetchBecauseYouListened());
      } catch (_) {}
      if (candidates.length < 6) {
        try {
          collect(await RecommendationsService.instance.fetchRecommendations());
        } catch (_) {}
      }
      if (candidates.length < 6) {
        try {
          collect(await RecommendationsService.instance.fetchDailyMixes());
        } catch (_) {}
      }
      if (candidates.isEmpty) return;

      // Resolve playable URLs in parallel, keep queue/playlist order aligned.
      final batch = candidates.take(8).toList();
      final resolved = List<Track?>.filled(batch.length, null);
      final sources = List<AudioSource?>.filled(batch.length, null);
      await Future.wait(List.generate(batch.length, (i) async {
        final t = _trackWithCover(batch[i]);
        try {
          final r = await _resolvePlayableUrlWithType(t, preferred: _quality).timeout(const Duration(seconds: 15));
          final rt = r.sourceType != null && r.sourceType != t.sourceType
              ? t.copyWith(sourceType: r.sourceType)
              : t;
          resolved[i] = rt;
          sources[i] = _toSource(rt, r.url);
        } catch (_) {
          // Skip unresolvable tracks — autoplay is best-effort.
        }
      }));

      final addTracks = resolved.whereType<Track>().toList();
      final addSources = sources.whereType<AudioSource>().toList();
      if (addTracks.isEmpty) return;

      // A new playTrack/playQueue may have started while resolving — don't
      // touch the playlist mid-reset, and don't append to a stale queue.
      if (_isResolving || _current?.id != seed.id) return;

      await _syncPlaylistOp(() => _playlist.addAll(addSources));
      _queue = [..._queue, ...addTracks];
      _queueController.add(List<Track>.from(_queue));
      AppLogger.d('[PlayerService] Autoplay appended ${addTracks.length} tracks');
    } catch (e) {
      AppLogger.d('[PlayerService] Autoplay extend failed: $e');
    }
  }

  /// Plays only the short preview/clip of a track (artist "Clips" tab).
  /// Resolves the preview source directly — never the full song — and does
  /// not let autoplay chain tracks after the clip ends.
  Future<void> playClip(Track track) async {
    // No _isResolving guard — _queueGeneration supersedes whatever is in
    // flight; returning here silently swallowed taps during resolution.
    _queueGeneration++;
    track = _trackWithCover(track);
    _intendedTracks = [track];
    _intendedIndex = 0;
    _enhancer.bindToPlayer(_player);
    _enhancer.resetTrackGain();
    _ensureIndexSync();
    _setResolving(true);
    try {
      ({String url, String sourceType})? clip;
      final objectHash = track.objectHash;
      final objectType =
          (track.objectType == null || track.objectType!.isEmpty) ? 'm_track' : track.objectType!;
      Map<String, dynamic>? payload;
      if (objectHash != null && objectHash.isNotEmpty) {
        final res = await _api.postRaw(
          endpoint: 'muse_request_source',
          data: {
            'object_type': objectType,
            'object_hash': objectHash,
            'type': 'audio_quality_2',
            'solve': 'false',
          },
        );
        if (res.isSuccess && res.data != null) {
          payload = res.data!;
          clip = _extractClipSource(payload);
        }
      }
      final hasHash = objectHash != null && objectHash.isNotEmpty;
      // When the track's main source is itself a video (or no clip node was
      // found at all), resolve the real video stream — a clip should never
      // degrade to audio-only playback. Pure-audio tracks keep their clip.
      final wantsVideo = payload != null && _mainSourceIsVideo(payload);
      if (hasHash && (wantsVideo || clip == null || clip.url.isEmpty)) {
        final video = await _resolveClipViaYoutube(payload, track, objectType, objectHash);
        if (video != null && video.url.isNotEmpty) {
          clip = video;
        }
      }
      if (clip == null || clip.url.isEmpty) {
        // No clip or video for this track — fall back to normal playback.
        AppLogger.d('[PlayerService] No clip source for ${track.title} — playing normally');
        _setResolving(false);
        await playTrack(track);
        return;
      }

      _clipMode = true;
      // Same sniffing as the main resolver — a clip URL that is really a
      // muxed video must reach the player screen flagged 'video'.
      final clipType = _upgradeSourceType(clip.url, clip.sourceType) ?? 'audio';
      track = track.copyWith(sourceType: clipType);
      final source = _toSource(track, clip.url);
      await _syncPlaylistOp(() async {
        await _playlist.clear();
        await _playlist.add(source);
      });

      _queue = [track];
      _index = 0;
      _current = track;
      _currentTrackController.add(_current);
      _queueController.add(List<Track>.from(_queue));

      await _player.setAudioSource(_playlist, initialIndex: 0)
          .timeout(const Duration(seconds: 20));
      _setSourceType(clipType);
      await _player.play();
      _setError(null);
    } catch (e) {
      _evictCachedUrl(track);
      _setError(e.toString());
    } finally {
      _setResolving(false);
    }
  }

  Future<void> playTrack(Track track) async {
    _clipMode = false;
    final generation = ++_queueGeneration;
    // For single track, play immediately without full queue processing
    track = _trackWithCover(track);
    _intendedTracks = [track];
    _intendedIndex = 0;
    _enhancer.bindToPlayer(_player);
    _enhancer.resetTrackGain();
    // Wire the index/completion listeners — without this a lone track
    // just stops at the end and autoplay never kicks in.
    _ensureIndexSync();

    // Show the track in the UI immediately — the user sees title/artwork
    // while the stream URL resolves (perceived instant play).
    _queue = [track];
    _index = 0;
    _current = track;
    _currentTrackController.add(_current);
    _queueController.add(List<Track>.from(_queue));
    _setSourceType(track.sourceType);

    _setResolving(true);
    try {
      ({String url, String? sourceType}) result;
      try {
        // Increased timeout to 15 seconds to allow youtube_download fallback
        result = await _resolvePlayableUrlWithType(track, preferred: _quality).timeout(const Duration(seconds: 15));
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('no_access') || errStr.contains('locked') || errStr.contains('requires purchase')) {
          _setError('Track locked or requires purchase');
          return;
        }
        if (_quality == AudioQuality.auto || _quality == AudioQuality.kbps320) {
          result = await _resolvePlayableUrlWithType(track, preferred: AudioQuality.kbps128).timeout(const Duration(seconds: 15));
        } else {
          rethrow;
        }
      }
      if (generation != _queueGeneration) return; // superseded by a newer play

      // Carry the resolved sourceType — a video source must reach the player
      // screen flagged as 'video' or it renders as audio-only.
      if (result.sourceType != null && result.sourceType != track.sourceType) {
        track = track.copyWith(sourceType: result.sourceType);
      }
      final source = _toSource(track, result.url);
      await _syncPlaylistOp(() async {
        await _playlist.clear();
        await _playlist.add(source);
      });
      if (generation != _queueGeneration) return;

      _queue = [track];
      _index = 0;
      _current = track;
      _currentTrackController.add(_current);
      _queueController.add(List<Track>.from(_queue));

      await _player.setAudioSource(_playlist, initialIndex: 0)
          .timeout(const Duration(seconds: 20));
      if (generation != _queueGeneration) return;
      _setSourceType(track.sourceType);
      await _player.play();
      _skipOnErrorCount = 0;
      _setError(null);
    } catch (e) {
      if (generation == _queueGeneration) {
        _evictCachedUrl(track);
        _setError(e.toString());
      }
    } finally {
      // A newer playTrack/playQueue may already be resolving — don't clear
      // its flag.
      if (generation == _queueGeneration) _setResolving(false);
    }
  }

  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    _clipMode = false;
    if (tracks.isEmpty) return;
    if (startIndex < 0 || startIndex >= tracks.length) startIndex = 0;

    // Ensure every track has a clean, absolute cover URL.
    tracks = tracks.map(_trackWithCover).toList();

    _enhancer.bindToPlayer(_player);
    _enhancer.resetTrackGain();
    await _ensureQualityLoaded();

    final generation = ++_queueGeneration;

    // Remember the full intended list so next/prev/skip keep working while
    // the tapped track is still resolving.
    _intendedTracks = List<Track>.from(tracks);
    _intendedIndex = startIndex;

    // Show the tapped track immediately — UI updates before the stream URL
    // resolves so the app feels instant.
    final tappedEarly = tracks[startIndex];
    _queue = [tappedEarly];
    _index = 0;
    _current = tappedEarly;
    _currentTrackController.add(_current);
    _queueController.add(List<Track>.from(_queue));
    _setSourceType(tappedEarly.sourceType);

    _setResolving(true);
    try {
      _ensureIndexSync();

      // Fast path — resolve ONLY the tapped track and start playback.
      // Resolving the whole queue up-front added seconds of dead time on
      // every tap; siblings are spliced in afterwards in the background.
      final tapped = tracks[startIndex];
      final result = await _resolveTrackResult(tapped);
      if (generation != _queueGeneration) return; // superseded
      if (result == null) {
        _setError('Unable to play ${tapped.title}');
        return;
      }
      final resolvedTapped =
          result.sourceType != null && result.sourceType != tapped.sourceType
              ? tapped.copyWith(sourceType: result.sourceType)
              : tapped;

      // Avoid just_audio_background shuffleIndices RangeError when resetting sources.
      final wasShuffle = _player.shuffleModeEnabled;
      if (wasShuffle) {
        await _player.setShuffleModeEnabled(false);
      }

      await _syncPlaylistOp(() async {
        await _playlist.clear();
        await _playlist.add(_toSource(resolvedTapped, result.url));
      });
      if (generation != _queueGeneration) return;

      _queue = [resolvedTapped];
      _index = 0;
      _current = resolvedTapped;
      _currentTrackController.add(_current);
      _queueController.add(List<Track>.from(_queue));
      _setSourceType(resolvedTapped.sourceType);

      await _player.setAudioSource(_playlist, initialIndex: 0)
          .timeout(const Duration(seconds: 20));
      if (generation != _queueGeneration) return;

      _skipOnErrorCount = 0;
      _setError(null);

      if (wasShuffle) {
        await _player.setShuffleModeEnabled(true);
      }
      try {
        await _player.play();
      } catch (e) {
        if (generation == _queueGeneration) _setError(e.toString());
      }
    } catch (e) {
      if (generation == _queueGeneration) {
        _evictCachedUrl(tracks[startIndex]);
        _setError(e.toString());
      }
      return;
    } finally {
      if (generation == _queueGeneration) _setResolving(false);
    }

    // Background: resolve the remaining queue tracks and splice them into the
    // playlist/queue around the already-playing item. Resolve ONE AT A TIME
    // so siblings don't fight the active track for bandwidth/log spam.
    if (tracks.length > 1) {
      unawaited(_fillQueueAround(tracks, startIndex, generation));
    }
  }

  /// Resolves a track with the quality fallback ladder used by playQueue.
  Future<({String url, String? sourceType})?> _resolveTrackResult(Track t) async {
    try {
      return await _resolvePlayableUrlWithType(t, preferred: _quality)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('no_access') || errStr.contains('locked') || errStr.contains('requires purchase')) {
        AppLogger.d('[PlayerService] Skipping locked/no_access track: ${t.title}');
        return null;
      }
      if (_quality == AudioQuality.auto || _quality == AudioQuality.kbps320) {
        try {
          return await _resolvePlayableUrlWithType(t, preferred: AudioQuality.kbps128)
              .timeout(const Duration(seconds: 15));
        } catch (_) {
          return null;
        }
      }
      return null;
    }
  }

  /// Background phase of playQueue — resolve siblings and splice each into
  /// the playlist/queue as soon as its URL lands. The track right after the
  /// tapped one resolves FIRST so hitting "next" works almost immediately;
  /// the rest follow one at a time so they don't fight the active stream.
  Future<void> _fillQueueAround(List<Track> tracks, int startIndex, int generation) async {
    if (_fillGeneration == generation) return;
    _fillGeneration = generation;
    try {
      // Resolve order: everything after the tapped track (in order), then
      // everything before it. Each resolved item is inserted immediately —
      // the queue grows live instead of appearing all at once at the end.
      final order = <int>[
        for (int i = startIndex + 1; i < tracks.length; i++) i,
        for (int i = 0; i < startIndex; i++) i,
      ];
      final inserted = <int>{startIndex};

      for (final i in order) {
        if (generation != _queueGeneration) return;
        final r = await _resolveTrackResult(tracks[i]);
        if (generation != _queueGeneration) return;
        if (r == null) continue;
        if (_queue.isEmpty) return;

        final t = tracks[i];
        final resolvedTrack =
            r.sourceType != null && r.sourceType != t.sourceType
                ? t.copyWith(sourceType: r.sourceType)
                : t;
        // Items before the tapped track slot in among themselves in ascending
        // original order; items after append at the end.
        final pos = i < startIndex
            ? inserted.where((j) => j < i).length
            : _queue.length;
        try {
          await _syncPlaylistOp(() => _playlist.insert(
              pos.clamp(0, _playlist.children.length),
              _toSource(resolvedTrack, r.url)));
          // currentIndexStream re-points _index at the playing track when an
          // insert lands before it; the end-of-fill pass re-verifies anyway.
          _queue.insert(pos, resolvedTrack);
          inserted.add(i);
          _queueController.add(List<Track>.from(_queue));
        } catch (e) {
          AppLogger.d('[PlayerService] queue insert failed for ${t.title}: $e');
        }
      }

      if (generation != _queueGeneration) return;

      // Safety net — make _index point at the actually-playing track even if a
      // currentIndex event raced our manual bookkeeping.
      final cur = _current;
      if (cur != null) {
        final real = _queue.indexWhere((q) => q.id == cur.id);
        if (real >= 0) _index = real;
      }
      _queueController.add(List<Track>.from(_queue));
      AppLogger.d('[PlayerService] queue fill done: ${_queue.length} tracks, index=$_index');
    } finally {
      if (_fillGeneration == generation) _fillGeneration = -1;
    }
  }

  /// Current track's position inside [_intendedTracks] (the full list the
  /// user tapped on), used when next/prev fire before the queue finishes
  /// filling.
  int get _intendedCurrentIndex {
    final cur = _current;
    if (cur == null) return _intendedIndex;
    final i = _intendedTracks.indexWhere((t) => t.id == cur.id);
    return i >= 0 ? i : _intendedIndex;
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    final atEnd = _index >= _queue.length - 1;
    // While a resolve/fill is running the playlist only holds a slice of the
    // intended tracks — jump by re-playing the intended queue at the next
    // position instead of seekToNext (which has nothing to seek to).
    if (_isResolving || (_fillInProgress && atEnd)) {
      final ni = _intendedCurrentIndex + 1;
      if (ni < _intendedTracks.length) {
        await playQueue(List<Track>.from(_intendedTracks), startIndex: ni);
      }
      return;
    }
    if (atEnd) {
      // Queue ran out — extend with related tracks, then advance.
      if (_autoplayEnabled) unawaited(_autoplayAdvance());
      return;
    }
    try {
      await _player.seekToNext();
      await _player.play();
    } catch (e) {
      _setError(e.toString());
      _maybeSkipOnError();
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    // Reroute through the intended list only when the previous track isn't
    // actually in the playlist yet (resolve/fill still running).
    if (_isResolving || (_fillInProgress && _index <= 0)) {
      final pi = _intendedCurrentIndex - 1;
      if (pi >= 0 && pi < _intendedTracks.length) {
        await playQueue(List<Track>.from(_intendedTracks), startIndex: pi);
      }
      return;
    }
    if (_index <= 0) return;
    try {
      await _player.seekToPrevious();
      await _player.play();
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> skipToIndex(int index) async {
    if (_queue.isEmpty) return;
    if (_isResolving || _fillInProgress) {
      // _queue only holds a slice right now — map the tapped position back to
      // the intended list so the right song plays.
      var target = index;
      if (index < _queue.length) {
        final ti = _intendedTracks.indexWhere((t) => t.id == _queue[index].id);
        if (ti >= 0) target = ti;
      }
      if (target >= 0 && target < _intendedTracks.length) {
        await playQueue(List<Track>.from(_intendedTracks), startIndex: target);
      }
      return;
    }
    if (index < 0 || index >= _queue.length) return;
    await _player.seek(Duration.zero, index: index);
    try {
      await _player.play();
    } catch (e) {
      _setError(e.toString());
      _maybeSkipOnError();
    }
  }

  Future<void> toggleShuffle() async {
    if (_isResolving) return;
    final enable = !_player.shuffleModeEnabled;
    await _player.setShuffleModeEnabled(enable);
    if (enable) {
      await _player.shuffle();
    }
  }

  Future<void> cycleRepeatMode() async {
    if (_isResolving) return;
    final cur = _player.loopMode;
    LoopMode next;
    switch (cur) {
      case LoopMode.off:
        next = LoopMode.all;
        break;
      case LoopMode.all:
        next = LoopMode.one;
        break;
      case LoopMode.one:
        next = LoopMode.off;
        break;
    }
    await _player.setLoopMode(next);
  }

  // ---------------------------------------------------------------------------
  // Sleep timer
  // ---------------------------------------------------------------------------

  /// Pauses playback after [duration]. Pass "end of track" style via
  /// [setSleepTimerEndOfTrack] instead.
  Future<void> setSleepTimer(Duration duration) async {
    cancelSleepTimer();
    _sleepAt = DateTime.now().add(duration);
    _sleepTimerController.add(duration);
    _sleepTimer = Timer(duration, _onSleepTimerFire);
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _sleepTimerController.add(sleepTimerRemaining);
    });
  }

  /// Stops playback once the currently playing track finishes.
  void setSleepTimerEndOfTrack() {
    cancelSleepTimer();
    _stopAfterTrack = true;
    _sleepTimerController.add(null);
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    _sleepTimer = null;
    _sleepTicker = null;
    _sleepAt = null;
    _stopAfterTrack = false;
    _sleepTimerController.add(null);
  }

  void _onSleepTimerFire() {
    cancelSleepTimer();
    unawaited(_player.pause());
  }

  // ---------------------------------------------------------------------------
  // Playback effects (speed / pitch / silence)
  // ---------------------------------------------------------------------------

  double get speed => _player.speed;
  Stream<double> get speedStream => _player.speedStream;
  Future<void> setSpeed(double v) => _player.setSpeed(v);

  double get pitch => _player.pitch;
  Stream<double> get pitchStream => _player.pitchStream;
  Future<void> setPitch(double v) => _player.setPitch(v);

  bool get skipSilenceEnabled => _player.skipSilenceEnabled;
  Stream<bool> get skipSilenceEnabledStream => _player.skipSilenceEnabledStream;
  Future<void> setSkipSilence(bool v) => _player.setSkipSilenceEnabled(v);

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  /// Resolves the playable URL for [t] (used by downloads and queue ops).
  /// Throws when the source is an HLS stream (not downloadable).
  Future<String> resolveUrlFor(Track t, {AudioQuality? quality}) async {
    final result = await _resolvePlayableUrlWithType(t, preferred: quality ?? _quality);
    return result.url;
  }

  /// Builds a clipped inline source for the Clips feed — reuses the same
  /// resolution + header/caching pipeline as the main queue so signed and
  /// CDN-gated URLs (googlevideo etc.) play correctly on a standalone
  /// AudioPlayer.
  Future<AudioSource?> clipSourceFor(
    Track t, {
    required int startSec,
    required int durationSec,
  }) async {
    try {
      final url = await _resolvePlayableUrl(t, preferred: _quality)
          .timeout(const Duration(seconds: 15));
      final uri = Uri.parse(url);
      // Plain UriAudioSource — LockCachingAudioSource is a StreamAudioSource
      // and cannot be wrapped by ClippingAudioSource.
      final base = AudioSource.uri(uri, headers: _sourceHeaders(uri));
      // HLS playlists can't be windowed by ClippingAudioSource.
      if (url.contains('.m3u8')) return base;
      return ClippingAudioSource(
        child: base,
        start: Duration(seconds: startSec),
        end: Duration(seconds: startSec + durationSec),
      );
    } catch (e) {
      _setError(e.toString());
      return null;
    }
  }

  /// Appends [track] to the end of the queue. Returns false when the source
  /// could not be resolved so callers can surface a message.
  Future<bool> addToQueue(Track track) async {
    if (_queue.isEmpty) {
      await playTrack(track);
      return _lastError == null;
    }
    track = _trackWithCover(track);
    try {
      final url = await _resolvePlayableUrl(track, preferred: _quality).timeout(const Duration(seconds: 15));
      _queue = [..._queue, track];
      await _syncPlaylistOp(() => _playlist.add(_toSource(track, url)));
      _queueController.add(List<Track>.from(_queue));
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    }
  }

  /// Inserts [track] right after the current track.
  Future<bool> playNext(Track track) async {
    if (_queue.isEmpty) {
      await playTrack(track);
      return _lastError == null;
    }
    track = _trackWithCover(track);
    try {
      final url = await _resolvePlayableUrl(track, preferred: _quality).timeout(const Duration(seconds: 15));
      final insertAt = (_index + 1).clamp(0, _queue.length);
      final list = List<Track>.from(_queue)..insert(insertAt, track);
      _queue = list;
      await _syncPlaylistOp(() => _playlist.insert(
          insertAt.clamp(0, _playlist.children.length),
          _toSource(track, url)));
      _queueController.add(List<Track>.from(_queue));
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    }
  }

  /// Removes the queue item at [index]. The currently playing item cannot be
  /// removed - it is skipped instead.
  Future<void> removeFromQueueAt(int index) async {
    if (_queue.isEmpty) return;
    if (index < 0 || index >= _queue.length) return;
    if (index == _index) {
      await next();
      return;
    }
    try {
      await _syncPlaylistOp(() => _playlist.removeAt(index));
      final list = List<Track>.from(_queue)..removeAt(index);
      _queue = list;
      if (index < _index) _index -= 1;
      _queueController.add(List<Track>.from(_queue));
    } catch (e) {
      _setError(e.toString());
    }
  }

  /// Moves a queue item (drag & drop reorder).
  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    if (_queue.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    if (oldIndex == newIndex) return;
    try {
      await _syncPlaylistOp(() => _playlist.move(oldIndex, newIndex));
      final list = List<Track>.from(_queue);
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
      _queue = list;
      if (_index == oldIndex) {
        _index = newIndex;
      } else if (oldIndex < _index && newIndex >= _index) {
        _index -= 1;
      } else if (oldIndex > _index && newIndex <= _index) {
        _index += 1;
      }
      _queueController.add(List<Track>.from(_queue));
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> _ensureLikedLoaded() async {
    if (_likedLoaded) return;
    _likedLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('liked_track_ids') ?? const <String>[];
    _liked = raw.where((e) => e.trim().isNotEmpty).toSet();
    _likedController.add(Set<String>.from(_liked));
  }

  Future<bool> isLiked(Track t) async {
    await _ensureLikedLoaded();
    return _liked.contains(t.id);
  }

  Future<void> _ensureRecentlyPlayedLoaded() async {
    if (_recentlyPlayedLoaded) return;
    _recentlyPlayedLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('recently_played_track_ids') ?? const <String>[];
    _recentlyPlayed = raw.where((e) => e.trim().isNotEmpty).toList(growable: true);
    _recentlyPlayedController.add(List<String>.from(_recentlyPlayed));
  }

  Future<List<String>> getRecentlyPlayedIds() async {
    await _ensureRecentlyPlayedLoaded();
    return List<String>.from(_recentlyPlayed);
  }

  Future<void> _addToRecentlyPlayed(String trackId) async {
    await _ensureRecentlyPlayedLoaded();
    _recentlyPlayed.remove(trackId); // Move to front if already present
    _recentlyPlayed.insert(0, trackId);
    if (_recentlyPlayed.length > _maxRecentlyPlayed) {
      _recentlyPlayed = _recentlyPlayed.sublist(0, _maxRecentlyPlayed);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recently_played_track_ids', _recentlyPlayed);
    _recentlyPlayedController.add(List<String>.from(_recentlyPlayed));
  }

  Future<List<Track>> getLikedTracks() async {
    await _ensureLikedLoaded();
    // Note: This would need a way to resolve Track objects from IDs, but for now return empty.
    // In real implementation, you'd fetch Track data from backend or cache.
    return [];
  }

  Future<List<Track>> getRecentlyPlayedTracks() async {
    // final ids = await getRecentlyPlayedIds(); // TODO: Use to resolve Track objects
    // Similarly, resolve Track objects from IDs.
    // For now, return empty list.
    return [];
  }

  Future<void> toggleLike(Track t) async {
    await _ensureLikedLoaded();

    final objectType = (t.objectType == null || t.objectType!.isEmpty) ? 'm_track' : t.objectType!;
    final objectHash = (t.objectHash == null || t.objectHash!.isEmpty) ? null : t.objectHash;

    final currentlyLiked = _liked.contains(t.id);
    final nextLiked = !currentlyLiked;

    // Optimistic local update.
    if (nextLiked) {
      _liked.add(t.id);
    } else {
      _liked.remove(t.id);
    }
    _likedController.add(Set<String>.from(_liked));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('liked_track_ids', _liked.toList(growable: false));

    // Server sync (preferred) when object hash is available.
    if (objectHash == null) return;
    
    // Show feedback for no_access if error occurs
    _api.postRaw(
      endpoint: nextLiked ? 'like' : 'unlike',
      data: {
        'object_type': objectType,
        'object': objectHash,
      },
    ).then((res) async {
      if (!res.isSuccess) {
        // Roll back optimistic update on failure.
        if (nextLiked) {
          _liked.remove(t.id);
        } else {
          _liked.add(t.id);
        }
        _likedController.add(Set<String>.from(_liked));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('liked_track_ids', _liked.toList(growable: false));
        
        final msg = res.error?.message ?? 'Failed to sync like';
        _setError(msg);
      }
    });
  }

  Future<void> setQuality(AudioQuality q) async {
    _quality = q;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player_audio_quality', q.name);

    // If something is playing, rebuild the current item's source at the new
    // quality IN-PLACE — setUrl() would wipe the whole ConcatenatingAudioSource
    // queue and leave only this one track.
    if (_queue.isEmpty || _current == null) return;
    // _index can briefly exceed _queue while a fill/reset is in flight.
    if (_index < 0 || _index >= _queue.length) return;
    final current = _queue[_index];
    final url = await _resolvePlayableUrl(current, preferred: _quality);
    final pos = _player.position;
    await _syncPlaylistOp(() async {
      if (_index < _playlist.children.length) {
        await _playlist.removeAt(_index);
      }
      await _playlist.insert(
          _index.clamp(0, _playlist.children.length),
          _toSource(current, url));
    });
    await _player.setAudioSource(_playlist,
        initialIndex: _index, initialPosition: pos);
    await _player.play();
  }

  Future<void> togglePlayPause() async {
    // No _isResolving guard: pause must stay responsive while the next
    // track resolves (the previous source may still be playing), and
    // play() during a load just starts playback once buffering finishes.
    try {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (_) {
      // No source loaded yet — ignore.
    }
  }

  Future<void> stop() async {
    await _player.stop();
  }

  /// googlevideo rejects ExoPlayer's default UA with 403 — send the same
  /// YouTube-app headers the manifest was fetched with.
  Map<String, String>? _sourceHeaders(Uri uri) {
    final host = uri.host;
    return (host.contains('googlevideo') ||
            host.endsWith('youtube.com') ||
            host.endsWith('youtu.be'))
        ? const {
            'User-Agent':
                'com.google.android.youtube/19.09.37 (Linux; U; Android 14) gzip',
            'Referer': 'https://www.youtube.com/',
          }
        : null;
  }

  AudioSource _toSource(Track t, String resolvedUrl) {
    // ignore: avoid_print
    AppLogger.d('[PlayerService] _toSource: track=${t.title} url=$resolvedUrl');
    // ignore: avoid_print
    AppLogger.d('[PlayerService] _toSource: isHLS=${resolvedUrl.contains('.m3u8') || resolvedUrl.contains('.ts') || resolvedUrl.contains('HLS')}');
    final cover = t.coverUrl;
    final uri = Uri.parse(resolvedUrl);
    final headers = _sourceHeaders(uri);
    final tag = MediaItem(
      id: t.id,
      title: t.title,
      artist: t.subtitle,
      // Only absolute http(s) covers — a relative/HTML value makes the
      // notification artwork loader spam 404s.
      artUri: (cover != null &&
              cover.isNotEmpty &&
              (cover.startsWith('http://') || cover.startsWith('https://')))
          ? Uri.parse(cover)
          : null,
    );
    // Cache audio bytes on disk — replaying a track serves from the cache
    // instead of re-downloading the whole stream. HLS playlists and local
    // files are excluded (LockCaching can't segment-cache m3u8, and local
    // files need no caching).
    if ((uri.isScheme('http') || uri.isScheme('https')) &&
        !resolvedUrl.contains('.m3u8')) {
      // ignore: experimental_member_use
      return LockCachingAudioSource(uri, headers: headers, tag: tag);
    }
    return AudioSource.uri(uri, headers: headers, tag: tag);
  }

  Future<void> _ensureQualityLoaded() async {
    if (_qualityLoaded) return;
    _qualityLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('player_audio_quality');
    if (raw != null && raw.isNotEmpty) {
      _quality = AudioQuality.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => AudioQuality.auto,
      );
    }
    final vRaw = prefs.getString('player_video_quality');
    if (vRaw != null && vRaw.isNotEmpty) {
      _videoQuality = VideoQuality.values.firstWhere(
        (e) => e.name == vRaw,
        orElse: () => VideoQuality.auto,
      );
    }
  }

  /// Legacy wrapper - returns just the URL for backward compatibility
  Future<String> _resolvePlayableUrl(Track t, {required AudioQuality preferred}) async {
    final result = await _resolvePlayableUrlWithType(t, preferred: preferred);
    return result.url;
  }

  // Keys whose values may hold short preview/clip media — never used as the
  // main playback source (that's how 30s previews hijacked full songs).
  static const _clipOnlyKeys = {'preview', 'clip', 'trailer', 'teaser'};

  /// Finds a stream 'address' anywhere in a backend node, skipping
  /// preview/clip keys so the 30s preview is never picked as the main source.
  String? _findStreamAddress(Object? node) {
    if (node == null) return null;
    if (node is Map) {
      if (node['address'] != null) {
        final a = node['address'].toString();
        if (a.isNotEmpty) return a;
      }
      if (node['1'] is Map) {
        final nested = node['1'] as Map;
        if (nested['address'] != null) {
          final a = nested['address'].toString();
          if (a.isNotEmpty) return a;
        }
      }
      for (final e in node.entries) {
        if (_clipOnlyKeys.contains(e.key.toString().toLowerCase())) continue;
        final found = _findStreamAddress(e.value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final v in node) {
        final found = _findStreamAddress(v);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Finds the declared source kind ('audio'/'video') in a backend node.
  String? _findStreamSourceType(Object? node) {
    if (node == null) return null;
    if (node is Map) {
      final typeVal = node['type'];
      if (typeVal is List && typeVal.isNotEmpty) {
        final firstType = typeVal[0]?.toString().toLowerCase();
        if (firstType == 'audio' || firstType == 'video') {
          return firstType;
        }
        if (firstType == 'youtube') {
          return 'video';
        }
      }
      for (final e in node.entries) {
        if (_clipOnlyKeys.contains(e.key.toString().toLowerCase())) continue;
        final found = _findStreamSourceType(e.value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final v in node) {
        final found = _findStreamSourceType(v);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// True when a sources[] entry is flagged as a preview
  /// (opts.preview=true or a '*_preview' hook like itunes_preview).
  bool _isPreviewSourceEntry(Object? node) {
    if (node is Map) {
      final p = node['preview'];
      if (p == true || p == 1 || p == '1' || (p is String && p.toLowerCase() == 'true')) {
        return true;
      }
      final hook = node['hook']?.toString().toLowerCase();
      if (hook != null && hook.contains('preview')) return true;
      for (final e in node.entries) {
        if (_clipOnlyKeys.contains(e.key.toString().toLowerCase())) continue;
        if (_isPreviewSourceEntry(e.value)) return true;
      }
    } else if (node is List) {
      for (final v in node) {
        if (_isPreviewSourceEntry(v)) return true;
      }
    }
    return false;
  }

  /// iTunes/hosted 30-second preview URLs.
  bool _isPreviewUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('itunes.apple.com') ||
        u.contains('audio-ssl.itunes') ||
        u.contains('mzstatic') ||
        u.contains('audiopreview');
  }

  /// Extracts the best playback candidate: non-preview sources win; a
  /// preview source is returned only flagged so the caller can try harder.
  ({String? url, String? sourceType, bool isPreview}) _extractUrlAndType(Map<String, dynamic> payload) {
    final sources = payload['sources'];
    if (sources is! List || sources.isEmpty) return (url: null, sourceType: null, isPreview: false);

    String? previewUrl;
    String? previewType;
    for (final s in sources) {
      if (s is! Map) continue;
      final src = s['source'];
      final url = _findStreamAddress(src) ?? _findStreamAddress(s);
      if (url == null) continue;
      final sourceType = _findStreamSourceType(src) ?? _findStreamSourceType(s);
      final isPreview = _isPreviewSourceEntry(s) || _isPreviewUrl(url);
      if (!isPreview) {
        return (url: url, sourceType: sourceType ?? 'audio', isPreview: false);
      }
      previewUrl ??= url;
      previewType ??= sourceType;
    }

    if (previewUrl != null) {
      return (url: previewUrl, sourceType: previewType ?? 'audio', isPreview: true);
    }

    // Alternative payloads with no proper sources[] — preview keys skipped.
    final url = _findStreamAddress(payload);
    if (url != null) {
      final sourceType = _findStreamSourceType(payload);
      return (url: url, sourceType: sourceType ?? 'audio', isPreview: _isPreviewUrl(url));
    }
    return (url: null, sourceType: null, isPreview: false);
  }

  /// Pulls a playable address out of a `preview`/`clip` node (video clips
  /// carry type:'video' + address/url; image previews are skipped).
  ({String url, String sourceType})? _clipFromNode(Object? node) {
    if (node is! Map) return null;
    final type = node['type']?.toString().toLowerCase();
    for (final k in ['address', 'url', 'file', 'video', 'src', 'mp4', 'm3u8']) {
      final v = node[k];
      if (v is String && v.startsWith('http')) {
        return (url: _normalizeStreamUrl(v), sourceType: (type == 'audio' ? 'audio' : 'video'));
      }
      if (v is Map) {
        final got = _clipFromNode(v);
        if (got != null) return got;
      }
    }
    return null;
  }

  /// Resolves ONLY the short preview/clip for a track — used by the Clips
  /// tab so tapping a clip never hijacks full-song resolution.
  ({String url, String sourceType})? _extractClipSource(Map<String, dynamic> payload) {
    final sources = payload['sources'];
    if (sources is List) {
      for (final s in sources) {
        if (s is! Map) continue;
        if (_isPreviewSourceEntry(s)) {
          final url = _findStreamAddress(s['source']) ?? _findStreamAddress(s);
          if (url != null) {
            final st = _findStreamSourceType(s['source']) ?? _findStreamSourceType(s) ?? 'audio';
            return (url: _normalizeStreamUrl(url), sourceType: st);
          }
        }
      }
      for (final s in sources) {
        if (s is! Map) continue;
        final data = s['data'];
        final got = _clipFromNode(s['preview']) ??
            (data is Map ? _clipFromNode(data['preview']) : null);
        if (got != null) return got;
      }
    }
    return _clipFromNode(payload['preview']) ?? _clipFromNode(payload['clip']);
  }

  String _normalizeStreamUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    u = u.replaceAll('\\/', '/');
    if (u.startsWith('//')) u = 'https:$u';
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      if (u.startsWith('/')) {
        u = 'https://music.hitune.in$u';
      } else {
        u = 'https://music.hitune.in/$u';
      }
    }
    return u;
  }

  Map<String, dynamic>? _pickFirstSourceEntry(Map<String, dynamic> payload) {
    final sources = payload['sources'];
    if (sources is! List || sources.isEmpty) return null;
    // Prefer a non-preview entry — sources.first is often a 30s clip while
    // the real (raaz/full) source sits later in the list.
    for (final s in sources) {
      if (s is Map && !_isPreviewSourceEntry(s)) {
        return Map<String, dynamic>.from(s);
      }
    }
    final first = sources.first;
    if (first is Map) return Map<String, dynamic>.from(first);
    return null;
  }

  Map<String, dynamic>? _raazParamsFromPayload(
    Map<String, dynamic> payload,
    Track t,
    String objectType,
    String objectHash,
  ) {
    final entry = _pickFirstSourceEntry(payload);
    if (entry == null) return null;

    final data = entry['data'] is Map ? Map<String, dynamic>.from(entry['data'] as Map) : null;
    if (data == null) return null;

    // Try to get source info - may be missing for some track types
    final source = entry['source'] is Map ? Map<String, dynamic>.from(entry['source'] as Map) : null;

    // Extract title and subTitle from data
    var title = (data['title'] ?? '').toString();
    var subTitle = (data['sub_title'] ?? '').toString();
    if (title.isEmpty) title = t.title;
    if (subTitle.isEmpty) subTitle = t.subtitle ?? '';
    final duration = data['duration'];
    if (title.isEmpty || subTitle.isEmpty) return null;

    // Build params
    final params = <String, dynamic>{
      'title': title,
      'sub_title': subTitle,
      'object_type': objectType,
      'object_hash': objectHash,
    };
    if (duration is int) params['duration'] = duration;
    if (duration is String && duration.isNotEmpty) params['duration'] = duration;

    // If source info available, extract raaz flags
    if (source != null) {
      final typeVal = source['type'];
      Map<String, dynamic>? opts;
      if (typeVal is List && typeVal.length >= 2 && typeVal[1] is Map) {
        opts = Map<String, dynamic>.from(typeVal[1] as Map);
      } else if (typeVal is Map) {
        final v = typeVal[1] ?? typeVal['1'];
        if (v is Map) opts = Map<String, dynamic>.from(v);
      }

      if (opts != null) {
        final raazVal = opts['raaz'];
        final isRaaz = (raazVal == true) ||
            (raazVal is String && (raazVal.toLowerCase() == 'true' || raazVal == '1')) ||
            (raazVal is num && raazVal == 1);

        if (!isRaaz) return null;

        // Pass through supported raaz flags.
        for (final key in [
          'youtube_id',
          'title',
          'sub_title',
          'duration',
          'youtube_get',
          'youtube_piped',
          'youtube_piped_instances',
          'soundcloud_get',
        ]) {
          if (opts.containsKey(key)) {
            final v = opts[key];
            if (v == null) continue;
            if (v is String && v.trim().isEmpty) continue;
            if (v is String && v.trim().toLowerCase() == 'null') continue;
            if (v is bool) {
              params[key] = v ? 'true' : 'false';
            } else {
              params[key] = v.toString();
            }
          }
        }
      } else {
        // No opts but has source - check if it's raaz by looking at youtube_id directly in source
        if (source['youtube_id'] != null) {
          params['youtube_id'] = source['youtube_id'].toString();
          params['youtube_piped'] = 'true';
        }
      }
    } else {
      // No source field - this is a raaz track that needs dynamic resolution
      // Check if there's a youtube_id in data or entry first
      final youtubeId = data['youtube_id'] ?? entry['youtube_id'];
      if (youtubeId != null) {
        params['youtube_id'] = youtubeId.toString();
      }
      // ALWAYS set youtube_piped=true when source is missing - this forces raaz resolution
      params['youtube_piped'] = 'true';
      AppLogger.d('[PlayerService] _raazParamsFromPayload: No source field, forcing youtube_piped=true for raaz resolution');
    }

    // Keep it minimal.
    return params;
  }

  Future<({String? id, String? error})> _requestYoutubeId({
    required String title,
    required String subTitle,
    required int? duration,
    required String objectType,
    required String objectHash,
  }) async {
    final form = <String, String>{
      'title': title,
      'sub_title': subTitle,
      'object_type': objectType,
      'object_hash': objectHash,
    };
    if (duration != null) form['duration'] = duration.toString();

    final res = await _api.postRaw(endpoint: 'muse_request_youtube_id', data: form);
    if (!res.isSuccess || res.data == null) {
      return (id: null, error: res.error?.message);
    }

    final data = res.data!;
    final yt = data['youtube_id']?.toString();
    if (yt != null && yt.isNotEmpty) return (id: yt, error: null);

    final msgs = data['messages'];
    if (msgs is List && msgs.isNotEmpty) {
      return (id: null, error: msgs.map((e) => e.toString()).join(' | '));
    }
    return (id: null, error: 'muse_request_youtube_id returned no youtube_id');
  }

  Future<({String url, bool isVideo, String? videoUrl, List<VideoStreamPick> videoCandidates})?> _pipedClientResolve(String youtubeId, {List<String>? customInstances, bool preferAudio = false}) async {
    // Direct YouTube extraction first — public piped instances are mostly
    // unreachable on-device (DNS failures seen in logs); explode talks to
    // YouTube directly and needs no proxy.
    final exploded = await _explodeYoutube(youtubeId, preferAudio: preferAudio);
    if (exploded != null) {
      AppLogger.d('[PlayerService] resolved youtube via explode isVideo=${exploded.isVideo}');
      return exploded;
    }
    // Use backend-provided instances if available, otherwise a short list —
    // public piped instances are mostly DNS-dead on-device, so trying many
    // only spams logs and stalls resolution.
    final instances = customInstances ?? <String>[
      'https://pipedapi.kavin.rocks/',
      'https://pipedapi.leptons.xyz/',
    ];

    for (final base in instances) {
      final baseUri = Uri.parse(base);
      final uri = baseUri.resolve('streams/$youtubeId');
      try {
        final res = await http
            .get(uri, headers: {
          'User-Agent': 'Mozilla/5.0',
          'X-Requested-With': 'XMLHttpRequest',
        })
            .timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) {
          AppLogger.d('[PlayerService] piped $base status=${res.statusCode}');
          continue;
        }
        final ct = res.headers['content-type'] ?? '';
        if (!ct.toLowerCase().contains('application/json')) {
          // Some instances return HTML (WAF/maintenance). Skip.
          AppLogger.d('[PlayerService] piped $base non-json content-type=$ct');
          continue;
        }

        final decoded = jsonDecode(res.body);
        if (decoded is! Map) continue;
        final audioStreams = decoded['audioStreams'];
        final videoStreams = decoded['videoStreams'];

        // Piped qualities look like "720p"/"1080p" — strip non-digits or
        // tryParse returns null and every stream scores 0.
        int qualityOf(Map s) =>
            int.tryParse((s['quality'] ?? '')
                    .toString()
                    .replaceAll(RegExp(r'[^0-9]'), '')) ??
            0;

        // Highest bitrate audio — audio tops out ~160kbps so "best" is cheap.
        String? pickBest(List? list) {
          Map? best;
          var bestScore = -1;
          for (final s in list ?? const []) {
            if (s is! Map) continue;
            final url = (s['url'] ?? '').toString();
            if (url.isEmpty) continue;
            final q = qualityOf(s);
            if (q >= bestScore) {
              bestScore = q;
              best = s;
            }
          }
          final url = (best?['url'] ?? '').toString();
          return url.isEmpty ? null : url;
        }

        List<VideoStreamPick> candidatesOf(List? list) => [
              for (final s in list ?? const [])
                if (s is Map &&
                    ((s['url'] ?? '').toString()).isNotEmpty)
                  (q: qualityOf(s), url: (s['url'] ?? '').toString()),
            ];

        final audioList = audioStreams is List ? audioStreams : null;
        var videoList = videoStreams is List ? videoStreams : null;
        // Piped videoStreams are mostly video-only DASH renditions — muxed
        // (audio+video) entries are the safer default for the surface.
        final muxed =
            videoList?.where((s) => s is Map && s['videoOnly'] != true).toList();
        if (muxed != null && muxed.isNotEmpty) videoList = muxed;
        final videoCands = candidatesOf(videoList);

        if (preferAudio) {
          final a = pickBest(audioList);
          if (a != null) {
            AppLogger.d('[PlayerService] piped success with $base');
            return (url: a, isVideo: false, videoUrl: null, videoCandidates: const <VideoStreamPick>[]);
          }
          final v = _pickCappedCandidate(videoCands);
          if (v != null) {
            AppLogger.d('[PlayerService] piped success with $base');
            return (url: v, isVideo: true, videoUrl: v, videoCandidates: videoCands);
          }
          continue;
        }

        // Video track — audio stream feeds just_audio, video stream feeds
        // the surface. Separate URLs so they never starve each other.
        // Cap the video rendition by network/preference — unlimited "best"
        // pulls 1080p+ and burns ~100MB per song on metered connections.
        final vUrl = _pickCappedCandidate(videoCands);
        final aUrl = pickBest(audioList);
        if (vUrl != null) {
          AppLogger.d('[PlayerService] piped success with $base');
          return (url: aUrl ?? vUrl, isVideo: true, videoUrl: vUrl, videoCandidates: videoCands);
        }
        if (aUrl != null) {
          AppLogger.d('[PlayerService] piped success with $base');
          return (url: aUrl, isVideo: false, videoUrl: null, videoCandidates: const <VideoStreamPick>[]);
        }
      } catch (e) {
        AppLogger.d('[PlayerService] piped $base error=$e');
        continue;
      }
    }
    return null;
  }

  /// Helper to extract source type from backend type string
  String _extractSourceType(String? type) {
    if (type == null) return 'audio';
    final t = type.toLowerCase();
    if (t == 'video' || t == 'youtube') return 'video';
    if (t == 'audio') return 'audio';
    return 'audio'; // Default to audio
  }

  /// Helper to extract piped URLs from backend response
  List<String>? _extractPipedUrls(dynamic urlsData) {
    if (urlsData == null) return null;

    final List<String> urls = [];

    // Handle Map (indexed object like {"0": "url1", "1": "url2"})
    if (urlsData is Map) {
      // Get all numeric keys and sort them
      final keys = urlsData.keys
          .where((k) => int.tryParse(k.toString()) != null)
          .map((k) => int.parse(k.toString()))
          .toList();
      keys.sort();

      for (final key in keys) {
        final url = urlsData[key.toString()]?.toString();
        if (url != null && url.isNotEmpty && url.startsWith('http')) {
          urls.add(url);
        }
      }
    }
    // Handle List
    else if (urlsData is List) {
      for (final item in urlsData) {
        final url = item?.toString();
        if (url != null && url.isNotEmpty && url.startsWith('http')) {
          urls.add(url);
        }
      }
    }
    // Handle single string
    else if (urlsData is String && urlsData.isNotEmpty && urlsData.startsWith('http')) {
      urls.add(urlsData);
    }

    return urls.isNotEmpty ? urls : null;
  }

  /// Clips usually carry no dedicated video endpoint — the `preview` node is
  /// just artwork. Resolve the track's YouTube video (muxed audio+video) so a
  /// clip tap plays real video instead of audio-only.
  Future<({String url, String sourceType})?> _resolveClipViaYoutube(
    Map<String, dynamic>? payload,
    Track track,
    String objectType,
    String objectHash,
  ) async {
    try {
      final raaz = payload == null
          ? null
          : _raazParamsFromPayload(payload, track, objectType, objectHash);
      var yt = raaz?['youtube_id']?.toString();
      if (yt == null || yt.isEmpty) {
        final title = (raaz?['title'] ?? track.title).toString();
        final subTitle = (raaz?['sub_title'] ?? track.subtitle ?? '').toString();
        if (title.isEmpty) return null;
        final r = await _requestYoutubeId(
          title: title,
          subTitle: subTitle,
          duration: int.tryParse('${raaz?['duration'] ?? ''}'),
          objectType: objectType,
          objectHash: objectHash,
        );
        yt = r.id;
      }
      if (yt == null || yt.isEmpty) return null;
      final stream = await _pipedClientResolve(yt, preferAudio: false);
      if (stream == null || stream.url.isEmpty) return null;
      if (stream.isVideo) {
        _videoCandidatesByTrackId[track.id] = stream.videoCandidates;
        _videoUrlByTrackId[track.id] =
            _pickCappedCandidate(stream.videoCandidates) ??
                (stream.videoUrl ?? stream.url);
      }
      return (url: stream.url, sourceType: stream.isVideo ? 'video' : 'audio');
    } catch (e) {
      AppLogger.d('[PlayerService] clip youtube resolve failed: $e');
      return null;
    }
  }

  /// True when the payload's main source is declared a video/youtube stream.
  bool _mainSourceIsVideo(Map<String, dynamic> payload) {
    final entry = _pickFirstSourceEntry(payload);
    final src = entry?['source'];
    if (src is! Map) return false;
    final typeVal = src['type'];
    String? kind;
    if (typeVal is List && typeVal.isNotEmpty) {
      kind = typeVal[0]?.toString();
    } else if (typeVal is Map) {
      kind = (typeVal[0] ?? typeVal['0'])?.toString();
    } else if (typeVal is String) {
      kind = typeVal;
    }
    return kind == 'video' || kind == 'youtube';
  }

  /// Resolves playable URL and returns both URL and source type (audio/video)
  Future<({String url, String? sourceType})> _resolvePlayableUrlWithType(Track t, {required AudioQuality preferred}) async {
    final r = await _resolvePlayableUrlWithTypeRaw(t, preferred: preferred);
    return (url: r.url, sourceType: _upgradeSourceType(r.url, r.sourceType));
  }

  /// Backend/proxy labels can lie — a muxed YouTube URL marked 'audio' plays
  /// its audio fine but never reaches the video surface (decoder just drops
  /// the frames). googlevideo URLs carry mime=/itag params, so upgrade to
  /// 'video' when the stream clearly has a video track. Video-only itags
  /// are excluded — those carry no audio for just_audio.
  String? _upgradeSourceType(String url, String? sourceType) {
    if (sourceType == 'video') return 'video';
    final q = Uri.tryParse(url)?.queryParameters;
    final mime = (q?['mime'] ?? '').toLowerCase();
    final itag = q?['itag'] ?? '';
    const muxedItags = {
      '5', '6', '13', '17', '18', '22', '34', '35', '36', '37', '38',
      '43', '44', '45', '46', '59', '78', '82', '83', '84', '85',
      '91', '92', '93', '94', '95', '96', '132', '151',
    };
    if (mime.startsWith('video') &&
        (itag.isEmpty || muxedItags.contains(itag))) {
      return 'video';
    }
    return sourceType;
  }

  Future<({String url, String? sourceType})> _resolvePlayableUrlWithTypeRaw(Track t, {required AudioQuality preferred}) async {
    // Offline-first: play the downloaded file when it exists on device.
    if (t.objectHash != null && t.objectHash!.isNotEmpty) {
      final local = await DownloadService.instance.localFileUrl(t.objectType ?? 'm_track', t.objectHash!);
      if (local != null) {
        AppLogger.d('[PlayerService] Using downloaded file for ${t.title}');
        return (url: local, sourceType: 'audio');
      }
    }

    // Direct URL track - if objectHash is null/empty, use direct URL
    if (t.objectHash == null || t.objectHash!.isEmpty) {
      return (url: t.url, sourceType: t.sourceType);
    }
    
    // If we have a direct URL and the objectHash looks like it might not be a valid backend hash
    // (e.g., numeric ID, very short, or contains special chars), try direct URL first
    final url = t.url;
    final hash = t.objectHash!;
    final hasDirectUrl = url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'));
    final looksLikeBackendHash = hash.length >= 16 && RegExp(r'^[a-f0-9]+$').hasMatch(hash);
    
    if (kDebugMode) {
      AppLogger.d('[PlayerService] _resolvePlayableUrl: hash=$hash, hasDirectUrl=$hasDirectUrl, looksLikeBackendHash=$looksLikeBackendHash');
    }
    
    // If we have a direct URL but the hash doesn't look like a backend hash, use direct URL
    if (hasDirectUrl && !looksLikeBackendHash) {
      if (kDebugMode) AppLogger.d('[PlayerService] Using direct URL - hash does not look like backend hash');
      return (url: url, sourceType: t.sourceType);
    }

    final objectType = (t.objectType == null || t.objectType!.isEmpty) ? 'm_track' : t.objectType!;
    final objectHash = hash;

    // Check cache first for instant play — exact quality match, then ANY
    // cached quality (playing instantly at 128k beats waiting for hi-res).
    final cached = await SongCacheService.instance.getSongUrl(objectHash, objectType, quality: preferred.name);
    if (cached != null) {
      final url = cached['url']?.toString() ?? '';
      final sourceType = cached['sourceType']?.toString();
      if (url.isNotEmpty) {
        AppLogger.d('[PlayerService] Cache hit for $objectHash - returning cached URL');
        _restoreVideoFromCache(t, cached);
        return (url: url, sourceType: sourceType);
      }
    }
    final anyCached = await SongCacheService.instance.getAnySongUrl(objectHash, objectType);
    if (anyCached != null) {
      final url = anyCached['url']?.toString() ?? '';
      final sourceType = anyCached['sourceType']?.toString();
      if (url.isNotEmpty) {
        AppLogger.d('[PlayerService] Any-quality cache hit for $objectHash');
        _restoreVideoFromCache(t, anyCached);
        return (url: url, sourceType: sourceType);
      }
    }

    final until = _noAccessUntil[objectHash];
    if (until != null && DateTime.now().isBefore(until)) {
      throw Exception('no_access');
    }

    // Map preference to backend hook.
    String requestedType;
    switch (preferred) {
      case AudioQuality.kbps128:
        requestedType = 'audio_quality_2';
        break;
      case AudioQuality.kbps320:
        requestedType = 'audio_quality_5';
        break;
      case AudioQuality.kbps960:
        requestedType = 'audio_quality_6';
        break;
      case AudioQuality.kbps1411:
        requestedType = 'audio_quality_7';
        break;
      case AudioQuality.kbps1600:
        requestedType = 'audio_quality_8';
        break;
      case AudioQuality.auto:
        requestedType = 'audio_quality_8'; // try best, then fallback down
        break;
    }

    Future<ApiResult<Map<String, dynamic>>> call(String type) {
      // ignore: avoid_print
      AppLogger.d('[PlayerService] calling muse_request_source for $objectHash type=$type solve=false');
      return _api.postRaw(
        endpoint: 'muse_request_source',
        data: {
          'object_type': objectType,
          'object_hash': objectHash,
          'type': type,
          'solve': 'false', // Skip raaz resolution for faster response
        },
      ).then((r) {
        if (!r.isSuccess) {
          // ignore: avoid_print
          AppLogger.d('[PlayerService] muse_request_source failed for $objectHash type=$type error=${r.error?.message}');
          return ApiResult.failure(r.error!);
        }
        final data = r.data;
        if (data == null) {
          return ApiResult.failure(const ApiError(code: 'invalid_source', message: 'muse_request_source payload missing'));
        }
        // ignore: avoid_print
        AppLogger.d('[PlayerService] muse_request_source success for $objectHash type=$type');

        // Detect locked/no-access tracks - stop retrying immediately
        if (data['no_access'] == true || data['no_access'] == 'true' || data['no_access'] == 1 || data['no_access'] == '1') {
          _noAccessUntil[objectHash] = DateTime.now().add(_noAccessCooldown);
          return ApiResult.failure(const ApiError(code: 'no_access', message: 'This track is locked. Please purchase or subscribe to access it.'));
        }
        final messages = data['messages'];
        if (messages is List) {
          for (final msg in messages) {
            final s = msg.toString().toLowerCase();
            if (s.contains('no access') || s.contains('locked') || s.contains('purchase required') || s.contains('no_access')) {
              _noAccessUntil[objectHash] = DateTime.now().add(_noAccessCooldown);
              return ApiResult.failure(const ApiError(code: 'no_access', message: 'This track is locked. Please purchase or subscribe to access it.'));
            }
          }
        }

        // Common format: { sources: [...] }
        if (data['sources'] is List) {
          return ApiResult.success(Map<String, dynamic>.from(data));
        }

        // Legacy format: { messages: [ { sources: [...] } ] }
        final msg = data['messages'];
        if (msg is List && msg.isNotEmpty && msg.first is Map) {
          final m0 = Map<String, dynamic>.from(msg.first as Map);
          if (m0['sources'] is List) {
            return ApiResult.success(m0);
          }
        }

        return ApiResult.failure(const ApiError(code: 'invalid_source', message: 'muse_request_source payload missing'));
      });
    }


    String? raazFailure;
    bool raazAttempted = false;

    /// Returns both URL and the actual source type from backend (audio/video)
    Future<({String url, String sourceType})?> _tryYoutubeDownload(Map<String, dynamic> raazParams, String youtubeId) async {
      final form = <String, String>{};
      for (final e in raazParams.entries) {
        final v = e.value;
        if (v == null) continue;
        form[e.key] = v.toString();
      }

      // Force youtube_download to true to get direct URL
      form['youtube_id'] = youtubeId;
      form['youtube_download'] = 'true';
      form.remove('youtube_piped');

      AppLogger.d('[PlayerService] Trying youtube_download for $youtubeId');
      AppLogger.d('[PlayerService] youtube_download form data: $form');

      try {
        final res = await _api.postRaw(
          endpoint: 'muse_solve_raaz', 
          data: form,
        ).timeout(const Duration(seconds: 20)); // backend is the reliable path — explode URLs come back dead (403/404)
        
        if (!res.isSuccess || res.data == null) {
          AppLogger.d('[PlayerService] youtube_download request failed: ${res.error?.message}');
          return null;
        }

        final data = res.data!;
        AppLogger.d('[PlayerService] youtube_download raw response: $data');
        
        final typeVal = data['type'];
        AppLogger.d('[PlayerService] youtube_download typeVal: $typeVal (runtime: ${typeVal?.runtimeType})');
        
        // Extract URL and source type from response
        String? addr;
        String sourceType = 'audio'; // default to audio
        
        if (typeVal is List && typeVal.length >= 2 && typeVal[1] is Map) {
          final m = typeVal[1] as Map;
          addr = m['address']?.toString();
          // Get actual source type from first element (audio/video/youtube)
          final typeStr = typeVal[0]?.toString();
          AppLogger.d('[PlayerService] youtube_download typeStr from List[0]: $typeStr');
          if (typeStr == 'video' || typeStr == 'youtube') {
            sourceType = 'video';
          } else if (typeStr == 'audio') {
            sourceType = 'audio';
          }
        } else if (typeVal is List && typeVal.isNotEmpty && typeVal.length == 1) {
          // Handle single-element type like ["pending"] or ["audio"] without address map
          final typeStr = typeVal[0]?.toString();
          AppLogger.d('[PlayerService] youtube_download single typeStr: $typeStr');
          if (typeStr == 'pending') {
            AppLogger.d('[PlayerService] youtube_download status is pending - video not ready yet');
            return null; // Let the caller try other fallbacks
          }
          // If it's just a single type string like ["audio"] or ["video"], use that as sourceType
          if (typeStr == 'video' || typeStr == 'youtube') {
            sourceType = 'video';
          } else if (typeStr == 'audio') {
            sourceType = 'audio';
          }
          // addr remains null, try to find it elsewhere in response
          if (data['address'] != null) {
            addr = data['address']?.toString();
          }
        } else if (typeVal is Map) {
          final v = typeVal[1] ?? typeVal['1'];
          if (v is Map) {
            addr = v['address']?.toString();
            final typeStr = (typeVal[0] ?? typeVal['0'])?.toString();
            AppLogger.d('[PlayerService] youtube_download typeStr from Map: $typeStr');
            if (typeStr == 'video' || typeStr == 'youtube') {
              sourceType = 'video';
            } else if (typeStr == 'audio') {
              sourceType = 'audio';
            }
          }
        }
        
        // Also check for address in other common locations
        if (addr == null && data['address'] != null) {
          addr = data['address']?.toString();
          AppLogger.d('[PlayerService] youtube_download found addr in root: $addr');
        }
        if (addr == null && data['url'] != null) {
          addr = data['url']?.toString();
          AppLogger.d('[PlayerService] youtube_download found addr in url field: $addr');
        }
        
        AppLogger.d('[PlayerService] youtube_download extracted addr: $addr');
        
        if (addr != null && addr.isNotEmpty) {
          AppLogger.d('[PlayerService] youtube_download success: got URL (type: $sourceType)');
          if (sourceType == 'video') _videoUrlByTrackId[t.id] = addr;
          return (url: addr, sourceType: sourceType);
        }

        AppLogger.d('[PlayerService] youtube_download response had no address');
        return null;
      } on TimeoutException catch (e) {
        AppLogger.d('[PlayerService] youtube_download timeout: $e');
        return null;
      } catch (e) {
        AppLogger.d('[PlayerService] youtube_download error: $e');
        return null;
      }
    }

    Future<({String url, String sourceType})?> _solveRaazIfNeeded(Map<String, dynamic> musePayload) async {
      final raazParams = _raazParamsFromPayload(musePayload, t, objectType, objectHash);
      if (raazParams == null) return null;

      raazAttempted = true;

      // Audio-declared tracks must get an audio-only stream — pulling the
      // muxed video wastes bandwidth and makes playback stutter/crackle.
      final preferAudio = !_mainSourceIsVideo(musePayload);

      // Preferred: if this is a YouTube raaz item, ask backend for youtube_id then resolve via Piped.
      final ytOpt = raazParams['youtube_id']?.toString();
      final title = raazParams['title']?.toString() ?? '';
      final subTitle = raazParams['sub_title']?.toString() ?? '';
      final duration = int.tryParse((raazParams['duration'] ?? '').toString());
      if (title.isNotEmpty && subTitle.isNotEmpty) {
        var yt = (ytOpt != null && ytOpt.isNotEmpty) ? ytOpt : null;
        if (yt == null) {
          final r = await _requestYoutubeId(
            title: title,
            subTitle: subTitle,
            duration: duration,
            objectType: objectType,
            objectHash: objectHash,
          );
          yt = r.id;
          if (r.error != null) raazFailure = r.error;
        }
        if (yt != null && yt.isNotEmpty) {
          // Backend youtube_download proxy and direct extraction run in
          // PARALLEL — whichever returns a usable stream first wins. This
          // halves the worst-case resolve time.
          final fastF = _tryYoutubeDownload(raazParams, yt);
          final directF = _pipedClientResolve(yt, preferAudio: preferAudio);
          final fast = await fastF;

          // Video track — just_audio should still get the audio-only stream
          // when the direct resolve has one: the backend file is muxed and
          // costs ~5-10x the data of an audio stream for the same song.
          // Give the direct resolve a short window before falling back.
          if (!preferAudio) {
            var stream = await directF.timeout(
              const Duration(seconds: 5),
              onTimeout: () => null,
            );
            if (stream != null &&
                stream.url.isNotEmpty &&
                stream.url != stream.videoUrl) {
              _videoCandidatesByTrackId[t.id] = stream.videoCandidates;
              _videoUrlByTrackId[t.id] =
                  _pickCappedCandidate(stream.videoCandidates) ??
                      (stream.videoUrl ?? fast?.url ?? '');
              return (url: stream.url, sourceType: 'video');
            }
            if (fast != null && fast.url.isNotEmpty) {
              _videoUrlByTrackId[t.id] = fast.url;
              return (url: fast.url, sourceType: 'video');
            }
            // Neither a quick audio stream nor the backend file — wait for
            // the slow resolve fully rather than failing the track.
            stream ??= await directF;
            if (stream != null && stream.url.isNotEmpty) {
              _videoCandidatesByTrackId[t.id] = stream.videoCandidates;
              _videoUrlByTrackId[t.id] =
                  _pickCappedCandidate(stream.videoCandidates) ??
                      (stream.videoUrl ?? stream.url);
              return (url: stream.url, sourceType: stream.isVideo ? 'video' : 'audio');
            }
          }

          if (fast != null && fast.url.isNotEmpty) {
            // The backend download URL is reliable — explode/piped
            // googlevideo links often come back dead (403/404).
            if (preferAudio && fast.sourceType == 'audio') {
              directF.ignore();
              return (url: fast.url, sourceType: 'audio');
            }
            // Audio track but backend served video — use it as-is.
            if (fast.sourceType == 'video') {
              directF.ignore();
              _videoUrlByTrackId[t.id] = fast.url;
              return (url: fast.url, sourceType: 'video');
            }
          }

          // Backend proxy did not give the desired kind — fall back to direct.
          if (preferAudio) {
            final stream = await directF;
            if (stream != null && stream.url.isNotEmpty) {
              if (stream.isVideo) {
                _videoCandidatesByTrackId[t.id] = stream.videoCandidates;
                _videoUrlByTrackId[t.id] =
                    _pickCappedCandidate(stream.videoCandidates) ??
                        (stream.videoUrl ?? stream.url);
              }
              return (url: stream.url, sourceType: stream.isVideo ? 'video' : 'audio');
            }
          }

          raazFailure = 'Could not resolve YouTube stream (backend proxy and direct failed)';
        }
      }

      final form = <String, String>{};
      for (final e in raazParams.entries) {
        final v = e.value;
        if (v == null) continue;
        form[e.key] = v.toString();
      }

      // Never trigger server-side yt-dlp from the mobile client.
      // It is unreliable (blocked by YouTube frequently) and not needed for streaming.
      form.remove('youtube_download');
      form['youtube_download'] = 'false';

      final res = await _api.postRaw(endpoint: 'muse_solve_raaz', data: form);
      if (!res.isSuccess || res.data == null) {
        raazFailure = res.error?.message ?? 'muse_solve_raaz failed';
        return null;
      }
      final data = res.data!;
      _enhancer.scanLoudness(data);

      // muse_solve_raaz returns { type: [ <type>, { address: ... } ] }
      final typeVal = data['type'];
      if (typeVal is List && typeVal.length >= 2 && typeVal[1] is Map) {
        final m = typeVal[1] as Map;
        final addr = m['address']?.toString();
        // Get source type from first element of type array (audio/video/youtube)
        final sourceType = _extractSourceType(typeVal[0]?.toString());
        if (addr != null && addr.isNotEmpty) {
          final sType =
              (!preferAudio && sourceType == 'audio') ? 'video' : sourceType;
          if (sType == 'video') _videoUrlByTrackId[t.id] = addr;
          return (url: addr, sourceType: sType);
        }

        // If backend returned a youtube_id only, resolve stream client-side via Piped.
        final yt = m['youtube_id']?.toString();
        final pipedFailed = m['youtube_piped_failed'] == true;
        if (typeVal[0]?.toString() == 'youtube' && yt != null && yt.isNotEmpty) {
          // If backend already tried piped and it failed, skip piped and try youtube_download
          if (pipedFailed) {
            AppLogger.d('[PlayerService] Backend reports piped failed, trying youtube_download');
            final downloadResult = await _tryYoutubeDownload(raazParams, yt);
            if (downloadResult != null && downloadResult.url.isNotEmpty) {
              // Backend 'audio' label on a video track still points at
              // the muxed file — feed it to both players.
              final dType =
                  (!preferAudio && downloadResult.sourceType == 'audio')
                      ? 'video'
                      : downloadResult.sourceType;
              if (dType == 'video') _videoUrlByTrackId[t.id] = downloadResult.url;
              return (url: downloadResult.url, sourceType: dType);
            }
            raazFailure = 'YouTube download fallback also failed';
            return null;
          }
          
          // Check if backend provided piped URLs to use — run direct
          // resolution and the backend download proxy in parallel.
          final pipedUrls = _extractPipedUrls(m['youtube_piped_urls']);
          final streamF = _pipedClientResolve(yt, customInstances: pipedUrls, preferAudio: preferAudio);
          final downloadF = _tryYoutubeDownload(raazParams, yt);
          final stream = await streamF;
          if (stream != null && stream.url.isNotEmpty) {
            downloadF.ignore();
            if (stream.isVideo) {
              _videoCandidatesByTrackId[t.id] = stream.videoCandidates;
              _videoUrlByTrackId[t.id] =
                  _pickCappedCandidate(stream.videoCandidates) ??
                      (stream.videoUrl ?? stream.url);
            }
            return (url: stream.url, sourceType: stream.isVideo ? 'video' : 'audio');
          }

          final downloadResult = await downloadF;
          if (downloadResult != null && downloadResult.url.isNotEmpty) {
            final dType =
                (!preferAudio && downloadResult.sourceType == 'audio')
                    ? 'video'
                    : downloadResult.sourceType;
            if (dType == 'video') _videoUrlByTrackId[t.id] = downloadResult.url;
            return (url: downloadResult.url, sourceType: dType);
          }

          raazFailure = 'Piped could not resolve YouTube stream and download fallback failed';
          return null;
        }
      }
      if (typeVal is Map) {
        final v = typeVal[1] ?? typeVal['1'];
        if (v is Map) {
          final addr = v['address']?.toString();
          final sourceType = _extractSourceType((typeVal[0] ?? typeVal['0'])?.toString());
          if (addr != null && addr.isNotEmpty) {
            final sType =
                (!preferAudio && sourceType == 'audio') ? 'video' : sourceType;
            if (sType == 'video') _videoUrlByTrackId[t.id] = addr;
            return (url: addr, sourceType: sType);
          }

          final yt = v['youtube_id']?.toString();
          final kind = (typeVal[0] ?? typeVal['0'])?.toString();
          final pipedFailedInMap = v['youtube_piped_failed'] == true;
          if (kind == 'youtube' && yt != null && yt.isNotEmpty) {
            // Check if backend provided piped URLs to use
            final pipedUrls = _extractPipedUrls(v['youtube_piped_urls']);
            
            // If backend already tried piped and it failed, skip piped and try youtube_download
            if (pipedFailedInMap) {
              AppLogger.d('[PlayerService] Backend reports piped failed (map), trying youtube_download');
              final downloadResult = await _tryYoutubeDownload(raazParams, yt);
              if (downloadResult != null && downloadResult.url.isNotEmpty) {
                // Backend 'audio' label on a video track still points at
                // the muxed file — feed it to both players.
                final dType =
                    (!preferAudio && downloadResult.sourceType == 'audio')
                        ? 'video'
                        : downloadResult.sourceType;
                if (dType == 'video') _videoUrlByTrackId[t.id] = downloadResult.url;
                return (url: downloadResult.url, sourceType: dType);
              }
              raazFailure = 'YouTube download fallback also failed';
              return null;
            }
            
            final streamF = _pipedClientResolve(yt, customInstances: pipedUrls, preferAudio: preferAudio);
            final downloadF = _tryYoutubeDownload(raazParams, yt);
            final stream = await streamF;
            if (stream != null && stream.url.isNotEmpty) {
              downloadF.ignore();
              if (stream.isVideo) {
                _videoCandidatesByTrackId[t.id] = stream.videoCandidates;
                _videoUrlByTrackId[t.id] =
                    _pickCappedCandidate(stream.videoCandidates) ??
                        (stream.videoUrl ?? stream.url);
              }
              return (url: stream.url, sourceType: stream.isVideo ? 'video' : 'audio');
            }

            final downloadResult = await downloadF;
            if (downloadResult != null && downloadResult.url.isNotEmpty) {
              // Backend 'audio' label on a video track still points at
              // the muxed file — feed it to both players.
              final dType =
                  (!preferAudio && downloadResult.sourceType == 'audio')
                      ? 'video'
                      : downloadResult.sourceType;
              if (dType == 'video') _videoUrlByTrackId[t.id] = downloadResult.url;
              return (url: downloadResult.url, sourceType: dType);
            }

            raazFailure = 'Piped could not resolve YouTube stream and download fallback failed';
          }
        }
      }

      return null;
    }

    /// Resolves the FULL song via YouTube when the backend only offered a
    /// 30-second preview (itunes_preview). Uses the track's metadata to ask
    /// the backend for a youtube_id, then resolves a stream client-side.
    Future<({String url, String sourceType})?> _resolveFullViaYoutube(Map<String, dynamic> musePayload) async {
      final entry = _pickFirstSourceEntry(musePayload);
      Map<String, dynamic>? data;
      if (entry != null && entry['data'] is Map) {
        data = Map<String, dynamic>.from(entry['data'] as Map);
      } else if (musePayload['data'] is Map) {
        data = Map<String, dynamic>.from(musePayload['data'] as Map);
      }
      if (data == null) return null;
      var title = (data['title'] ?? data['_title'] ?? '').toString();
      var subTitle = (data['sub_title'] ?? '').toString();
      if (title.isEmpty) title = t.title;
      if (subTitle.isEmpty) subTitle = t.subtitle ?? '';
      if (title.isEmpty || subTitle.isEmpty) return null;
      final duration = int.tryParse((data['duration'] ?? '').toString());

      // Reuse a youtube_id the backend already attached to a sources[] entry —
      // the dedicated muse_request_youtube_id endpoint is unreliable.
      String? yt;
      final src = entry?['source'];
      Object? opts;
      if (src is Map) {
        final typeVal = src['type'];
        if (typeVal is List && typeVal.length > 1) {
          opts = typeVal[1];
        } else if (typeVal is Map) {
          opts = typeVal[1] ?? typeVal['1'];
        }
      }
      if (opts is Map) yt = opts['youtube_id']?.toString();
      yt ??= (entry?['youtube_id'] ?? data['youtube_id'])?.toString();
      if (yt == null || yt.isEmpty) {
        AppLogger.d('[PlayerService] Preview-only source — resolving full song via YouTube for "$title"');
        final r = await _requestYoutubeId(
          title: title,
          subTitle: subTitle,
          duration: duration,
          objectType: objectType,
          objectHash: objectHash,
        );
        yt = r.id;
        if (r.error != null) raazFailure = r.error;
      }
      if (yt == null || yt.isEmpty) return null;

      // Backend proxy and direct extraction in parallel — first usable
      // stream wins.
      final params = <String, dynamic>{
        'title': title,
        'sub_title': subTitle,
        'object_type': objectType,
        'object_hash': objectHash,
        if (duration != null) 'duration': duration,
      };
      final fastF = _tryYoutubeDownload(params, yt);
      final streamF = _pipedClientResolve(yt, preferAudio: true);
      final fast = await fastF;
      if (fast != null && fast.url.isNotEmpty) {
        streamF.ignore();
        if (fast.sourceType == 'video') _videoUrlByTrackId[t.id] = fast.url;
        return fast;
      }

      final stream = await streamF;
      if (stream != null && stream.url.isNotEmpty) {
        if (stream.isVideo) {
          _videoCandidatesByTrackId[t.id] = stream.videoCandidates;
          _videoUrlByTrackId[t.id] =
              _pickCappedCandidate(stream.videoCandidates) ??
                  (stream.videoUrl ?? stream.url);
        }
        return (url: stream.url, sourceType: stream.isVideo ? 'video' : 'audio');
      }

      return null;
    }

    // First try requested — and fire the low-quality request in PARALLEL so
    // a fast direct URL is already in hand if the hi-res request turns out
    // to be a slow raaz/preview source.
    // ignore: avoid_print
    AppLogger.d('[PlayerService] _resolvePlayableUrl: track=${t.title} objectHash=${t.objectHash} requestedType=$requestedType');
    const lowType = 'audio_quality_2';
    final lowFuture = requestedType == lowType ? null : call(lowType);
    final firstTry = await call(requestedType);
    if (firstTry.isSuccess) {
      _enhancer.scanLoudness(firstTry.data!);
      final result = _extractUrlAndType(firstTry.data!);
      // ignore: avoid_print
      AppLogger.d('[PlayerService] extractUrlAndType result: url=${result.url}, sourceType=${result.sourceType}, isPreview=${result.isPreview}');
      if (result.url != null && result.url!.isNotEmpty && !result.isPreview) {
        final normalized = _normalizeStreamUrl(result.url!);
        // ignore: avoid_print
        AppLogger.d('[PlayerService] resolved url type=$requestedType url=$normalized sourceType=${result.sourceType}');
        if (normalized.contains('.m3u8')) {
          unawaited(debugFetchM3U8(normalized));
        }
        unawaited(SongCacheService.instance.cacheSongUrl(
          objectHash,
          objectType,
          url: normalized,
          sourceType: result.sourceType ?? 'audio',
          quality: preferred.name,
          extraData: _videoCacheExtra(t),
        ));
        return (url: normalized, sourceType: result.sourceType);
      }

      // Auto mode: before burning seconds on the raaz/YouTube chain, check
      // whether the parallel low-quality request already has a direct URL —
      // instant play now beats hi-res in a while.
      if (preferred == AudioQuality.auto && lowFuture != null) {
        final low = await lowFuture;
        if (low.isSuccess) {
          final lr = _extractUrlAndType(low.data!);
          if (lr.url != null && lr.url!.isNotEmpty && !lr.isPreview) {
            final normalized = _normalizeStreamUrl(lr.url!);
            AppLogger.d('[PlayerService] auto fast-path: low-quality direct url=$normalized');
            unawaited(SongCacheService.instance.cacheSongUrl(
              objectHash,
              objectType,
              url: normalized,
              sourceType: lr.sourceType ?? 'audio',
              quality: lowType,
              extraData: _videoCacheExtra(t),
            ));
            return (url: normalized, sourceType: lr.sourceType);
          }
        }
      }

      // Preview-only (e.g. 30s iTunes clip) or empty → resolve the FULL song.
      final solved = await _solveRaazIfNeeded(firstTry.data!);
      if (solved != null) {
        final normalized = _normalizeStreamUrl(solved.url);
        // ignore: avoid_print
        AppLogger.d('[PlayerService] resolved url type=raaz url=$normalized sourceType=${solved.sourceType}');
        if (normalized.contains('.m3u8')) {
          unawaited(debugFetchM3U8(normalized));
        }
        unawaited(SongCacheService.instance.cacheSongUrl(
          objectHash,
          objectType,
          url: normalized,
          sourceType: solved.sourceType,
          quality: preferred.name,
          extraData: _videoCacheExtra(t),
        ));
        return (url: normalized, sourceType: solved.sourceType);
      }

      if (result.isPreview) {
        final yt = await _resolveFullViaYoutube(firstTry.data!);
        if (yt != null && yt.url.isNotEmpty) {
          final normalized = _normalizeStreamUrl(yt.url);
          AppLogger.d('[PlayerService] resolved FULL song via youtube url=$normalized sourceType=${yt.sourceType}');
          unawaited(SongCacheService.instance.cacheSongUrl(
            objectHash,
            objectType,
            url: normalized,
            sourceType: yt.sourceType,
            quality: preferred.name,
            extraData: _videoCacheExtra(t),
          ));
          return (url: normalized, sourceType: yt.sourceType);
        }
        // No full source yet — don't return the preview; let the quality
        // fallback ladder below try other source types first.
        AppLogger.d('[PlayerService] Preview-only source at type=$requestedType — trying fallbacks');
      }

      // If this item is a raaz/dynamic source and resolution failed, don't spam fallbacks.
      if (raazAttempted) {
        throw Exception(raazFailure ?? 'Unable to resolve stream for this track');
      }
    }

    // Fallback ladder — audio_quality_2's request is already in flight from
    // the parallel fire above, so its result is usually free by now.
    final fallbacks = <String>['audio_quality_4', 'audio_quality_2'];
    for (final fb in fallbacks) {
      if (fb == requestedType) continue; // Already tried
      ApiResult<Map<String, dynamic>> res;
      if (fb == 'audio_quality_2' && lowFuture != null) {
        res = await lowFuture;
      } else {
        res = await call(fb);
      }
      if (!res.isSuccess) {
        // ignore: avoid_print
        AppLogger.d('[PlayerService] fallback failed type=$fb error=${res.error?.message}');
        // Stop retrying if track is locked/no access
        if (res.error?.code == 'no_access') {
          throw Exception('Track locked or requires purchase');
        }
        continue;
      }
      // ignore: avoid_print
      AppLogger.d('[PlayerService] fallback attempt type=$fb');
      _enhancer.scanLoudness(res.data!);
      final result = _extractUrlAndType(res.data!);
      if (result.url != null && result.url!.isNotEmpty && !result.isPreview) {
        final normalized = _normalizeStreamUrl(result.url!);
        // ignore: avoid_print
        AppLogger.d('[PlayerService] resolved url fallback type=$fb url=$normalized sourceType=${result.sourceType}');
        if (normalized.contains('.m3u8')) {
          unawaited(debugFetchM3U8(normalized));
        }
        unawaited(SongCacheService.instance.cacheSongUrl(
          objectHash,
          objectType,
          url: normalized,
          sourceType: result.sourceType ?? 'audio',
          quality: preferred.name,
          extraData: _videoCacheExtra(t),
        ));
        return (url: normalized, sourceType: result.sourceType);
      }

      final solved = await _solveRaazIfNeeded(res.data!);
      if (solved != null) {
        final normalized = _normalizeStreamUrl(solved.url);
        // ignore: avoid_print
        AppLogger.d('[PlayerService] resolved url fallback raaz type=$fb url=$normalized sourceType=${solved.sourceType}');
        if (normalized.contains('.m3u8')) {
          unawaited(debugFetchM3U8(normalized));
        }
        unawaited(SongCacheService.instance.cacheSongUrl(
          objectHash,
          objectType,
          url: normalized,
          sourceType: solved.sourceType,
          quality: preferred.name,
          extraData: _videoCacheExtra(t),
        ));
        return (url: normalized, sourceType: solved.sourceType);
      }

      if (result.isPreview && result.url != null) {
        final yt = await _resolveFullViaYoutube(res.data!);
        if (yt != null && yt.url.isNotEmpty) {
          final normalized = _normalizeStreamUrl(yt.url);
          AppLogger.d('[PlayerService] resolved FULL song via youtube (fallback) url=$normalized sourceType=${yt.sourceType}');
          unawaited(SongCacheService.instance.cacheSongUrl(
            objectHash,
            objectType,
            url: normalized,
            sourceType: yt.sourceType,
            quality: preferred.name,
            extraData: _videoCacheExtra(t),
          ));
          return (url: normalized, sourceType: yt.sourceType);
        }
        // Still preview-only at this fallback — keep trying the next
        // quality rather than playing the 30s clip.
        AppLogger.d('[PlayerService] fallback type=$fb is preview-only — trying next');
      }

      // If this item is a raaz/dynamic source and resolution failed, don't spam fallbacks.
      if (raazAttempted) {
        throw Exception(raazFailure ?? 'Unable to resolve stream for this track');
      }
    }

    // No playable address in response.
    throw Exception('No playable address returned by muse_request_source for ${t.objectType}:${t.objectHash}');
  }

  /// Debug helper to fetch and log m3u8 content
  Future<void> debugFetchM3U8(String url) async {
    if (!url.contains('.m3u8')) return;
    try {
      // ignore: avoid_print
      AppLogger.d('[PlayerService] Fetching m3u8: $url');
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0',
      }).timeout(const Duration(seconds: 10));
      // ignore: avoid_print
      AppLogger.d('[PlayerService] m3u8 status: ${res.statusCode}');
      if (res.statusCode == 200) {
        final body = res.body;
        // ignore: avoid_print
        AppLogger.d('[PlayerService] m3u8 content length: ${body.length}');
        // Log first 500 chars
        // ignore: avoid_print
        AppLogger.d('[PlayerService] m3u8 content preview: ${body.substring(0, body.length > 500 ? 500 : body.length)}');
        // Check for segment URLs
        final lines = body.split('\n');
        final segmentLines = lines.where((l) => l.contains('.ts') || l.contains('http')).take(5).toList();
        // ignore: avoid_print
        AppLogger.d('[PlayerService] m3u8 segment URLs (first 5): $segmentLines');
        // Check if segments are relative
        final hasRelative = lines.any((l) => l.trim().startsWith('segment') || l.trim().startsWith('chunk') || (l.contains('.ts') && !l.startsWith('http')));
        // ignore: avoid_print
        AppLogger.d('[PlayerService] m3u8 has relative segments: $hasRelative');
      }
    } catch (e) {
      // ignore: avoid_print
      AppLogger.d('[PlayerService] Failed to fetch m3u8: $e');
    }
  }

  Future<void> dispose() async {
    await _currentIndexSub?.cancel();
    await _playerStateSub?.cancel();
    await _player.dispose();
    await _currentTrackController.close();
    await _resolvingController.close();
    await _errorController.close();
    await _likedController.close();
    await _recentlyPlayedController.close();
    await _sourceTypeController.close();
  }
}
