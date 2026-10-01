import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import 'dart:ui';

import '../auth/auth_gate.dart';
import '../artist/artist_screen.dart';
import '../share/share_dialog.dart';
import '../../core/ui/ai_badge.dart';
import 'player_service.dart';
import 'queue_sheet.dart';
import 'sleep_timer_sheet.dart';
import 'track_actions_sheet.dart';
import 'widgets/audio_enhance_sheet.dart';
import 'models/track.dart';
import '../../core/theme/theme_service.dart';
import '../../core/ui/cover_image.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/artist_utils.dart';
import '../../core/utils/cover_image_extractor.dart';

class PlayerScreen extends StatefulWidget {
  final PlayerService player;

  const PlayerScreen({super.key, required this.player});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  String? _videoTrackId;
  Uri? _videoUri;
  int _videoSetupGen = 0;
  bool _videoSetupInFlight = false;
  Timer? _videoSyncTimer;
  final List<StreamSubscription<dynamic>> _subs = [];
  // Video only starts when the user opts in — a video stream downloads
  // ~10x the audio bytes, so the surface never auto-loads on screen open.
  bool _videoWanted = false;

  PlayerService get player => widget.player;

  @override
  void initState() {
    super.initState();
    _initVideoListener();
  }

  void _initVideoListener() {
    // Check initial state — video surface stays OFF until the user picks
    // Video mode; opening the screen must not start a video download.
    _isVideo = player.currentSourceType == 'video';

    _subs.add(player.sourceTypeStream.listen((sourceType) {
      if (mounted) {
        final wasVideo = _isVideo;
        setState(() {
          _isVideo = sourceType == 'video';
        });
        // sourceType re-emits on every index/queue event — while a setup is
        // already running for this track a re-emit would dispose the
        // controller mid-initialize, so only re-setup on a real transition
        // or when nothing is in flight/loaded (retry after a failure).
        if (_videoWanted &&
            (_isVideo != wasVideo ||
                (_isVideo &&
                    _videoController == null &&
                    !_videoSetupInFlight))) {
          _setupVideoPlayer();
        }
      }
    }));

    // A new video track keeps sourceType=='video', so the listener above
    // never re-inits — watch the track itself and swap the controller.
    _subs.add(player.currentTrackStream.listen((track) {
      if (!mounted || track == null) return;
      if (_isVideo && _videoWanted && track.id != _videoTrackId) {
        _setupVideoPlayer();
      }
    }));
    
    // Also listen to player state to sync video play/pause
    _subs.add(player.playerStateStream.listen((state) {
      final vc = _videoController;
      if (vc == null) return;
      try {
        if (!vc.value.isInitialized) return;
        if (state.playing && !vc.value.isPlaying) {
          vc.play();
        } else if (!state.playing && vc.value.isPlaying) {
          vc.pause();
        }
      } catch (_) {
        // Controller was disposed mid-event — safe to ignore.
      }
    }));
  }

  /// True only while the controller is alive and ready — `.value` throws
  /// after dispose, so probe defensively.
  bool get _videoReady {
    final vc = _videoController;
    if (vc == null) return false;
    try {
      return vc.value.isInitialized;
    } catch (_) {
      return false;
    }
  }

  /// Native aspect ratio of the currently loaded video, or 16:9 as a safe fallback.
  double get _videoAspectRatio {
    final vc = _videoController;
    if (vc == null) return 16 / 9;
    try {
      final r = vc.value.aspectRatio;
      return r > 0 ? r : 16 / 9;
    } catch (_) {
      return 16 / 9;
    }
  }

  /// Toggles between the video surface and the album-art (audio-only) view.
  void _toggleAudioVideo() {
    setState(() {
      _videoWanted = !_videoWanted;
    });
    if (_videoWanted && _isVideo) {
      _setupVideoPlayer();
    } else if (!_videoWanted) {
      // Also kills an in-flight setup — otherwise a controller still
      // initializing would attach video after the user picked Song mode.
      _videoSetupGen++;
      _videoSyncTimer?.cancel();
      final vc = _videoController;
      _videoController = null;
      _videoUri = null;
      if (vc != null) {
        setState(() {});
        vc.dispose();
      }
    }
  }

  /// Quality picker shown while Video mode is on — manual tier applies at
  /// resolve time and re-picks the current track's stream immediately.
  Widget _buildVideoQualityMenu(Track track) {
    return PopupMenuButton<VideoQuality>(
      tooltip: 'Video quality',
      padding: EdgeInsets.zero,
      initialValue: player.videoQuality,
      onSelected: (q) async {
        await player.setVideoQuality(q);
        if (!mounted) return;
        setState(() {});
        // Re-pick under the new cap and swap the running surface.
        final picked = player.pickVideoUrl(track.id);
        if (picked != null && picked != player.videoUrlFor(track.id)) {
          player.overrideVideoUrl(track.id, picked);
          _videoUri = null;
          _videoTrackId = null;
          _setupVideoPlayer();
        }
      },
      itemBuilder: (_) => [
        for (final q in VideoQuality.values)
          PopupMenuItem(
            value: q,
            child: Row(
              children: [
                if (q == player.videoQuality)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(q.label),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hd_rounded, color: Colors.white.withValues(alpha: 0.8), size: 15),
            const SizedBox(width: 4),
            Text(
              player.videoQuality == VideoQuality.auto ? 'Auto' : player.videoQuality.label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  void _setupVideoPlayer() async {
    final track = player.currentTrack;
    if (track == null) return;

    // A healthy controller for THIS track is already running — repeat
    // sourceType/track events must not tear it down and rebuild the
    // decoder (each rebuild is a visible hiccup).
    if (_videoTrackId == track.id && _videoReady) return;

    // The track re-emitted with a different id (search object vs resolved
    // object) but points at the same stream — keep the running surface.
    final dedicated = player.pickVideoUrl(track.id);
    final src = player.audioPlayer.sequenceState?.currentSource;
    final candidate = (dedicated != null && dedicated.isNotEmpty)
        ? Uri.tryParse(dedicated)
        : (src is UriAudioSource ? src.uri : null);
    if (candidate != null && candidate == _videoUri && _videoReady) {
      _videoTrackId = track.id;
      return;
    }

    final gen = ++_videoSetupGen;

    // Record the target track + in-flight state BEFORE the first await so
    // repeat sourceType/track events for the same track don't spawn
    // parallel setups that keep disposing each other's controllers.
    _videoTrackId = track.id;
    _videoSetupInFlight = true;
    _videoSyncTimer?.cancel();
    _videoSyncTimer = null;

    try {
      // Detach the old controller BEFORE awaiting dispose — otherwise the
      // state listener / build can touch it mid-dispose.
      final old = _videoController;
      _videoController = null;
      _videoUri = null;
      if (old != null) {
        if (mounted) setState(() {});
        await old.dispose();
      }
      if (gen != _videoSetupGen || !mounted) return;

      if (!_isVideo) return;
      // Wait for audio player to have the source ready
      int attempts = 0;
      Uri? uri;

      // A dedicated video stream was resolved separately from the audio
      // URL — no need to wait for the playlist slot to settle.
      final dedicatedVideo = player.pickVideoUrl(track.id);
      if (dedicatedVideo != null && dedicatedVideo.isNotEmpty) {
        uri = Uri.parse(dedicatedVideo);
      }

      while (attempts < 20 && uri == null) {
        if (gen != _videoSetupGen || !mounted) return;
        final audioSource = player.audioPlayer.sequenceState?.currentSource;
        // Only bind the source once its tag matches this track — during a
        // track change the playlist briefly still holds the old source.
        if (audioSource is UriAudioSource &&
            (audioSource.tag is MediaItem
                ? (audioSource.tag as MediaItem).id == track.id
                : true)) {
          uri = audioSource.uri;
          break;
        }
        // Direct track URL only when it is actually a media stream —
        // track.url often points at the object's web page, which would
        // load HTML into the video player and render a black surface.
        final direct = track.url;
        if (direct.isNotEmpty &&
            (direct.startsWith('http://') || direct.startsWith('https://')) &&
            (direct.contains('.mp4') ||
                direct.contains('.m3u8') ||
                direct.contains('googlevideo') ||
                direct.contains('videoplayback'))) {
          uri = Uri.parse(direct);
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (gen != _videoSetupGen || !mounted) return;

      if (uri == null) {
        AppLogger.d('[PlayerScreen] Could not get video URL after $attempts attempts');
        return;
      }

      // Two candidates: the dedicated video stream (separate download, no
      // bandwidth fight with just_audio) and — as fallback — the URL the
      // audio player already opened. googlevideo video URLs can 403 on
      // exotic devices; the shared URL is proven to play.
      var uriToTry = uri;
      var triedSharedFallback = false;
      while (true) {
        if (gen != _videoSetupGen || !mounted) return;
        AppLogger.d('[PlayerScreen] Initializing video player with URL: $uriToTry');
        final vc = VideoPlayerController.networkUrl(
          uriToTry,
          httpHeaders: _videoHeaders(uriToTry),
        );
        try {
          // A network stall must not wedge the in-flight flag forever.
          await vc.initialize().timeout(const Duration(seconds: 15));
          if (gen != _videoSetupGen || !mounted) {
            await vc.dispose();
            return;
          }
          // Audio comes from just_audio — the video surface is visual-only
          // or the muxed stream's audio double-plays on top of it.
          await vc.setVolume(0);
          _videoController = vc;
          _videoUri = uriToTry;
          AppLogger.d(
              '[PlayerScreen] Video player initialized successfully size=${vc.value.size} dur=${vc.value.duration}');

          // just_audio has been playing since URL resolution finished —
          // jump the video to the audio position or it starts at 0.
          try {
            await vc.seekTo(player.audioPlayer.position);
          } catch (_) {}

          if (player.audioPlayer.playing) {
            await vc.play();
          }

          _startVideoSync();
          if (mounted) setState(() {});
          return;
        } catch (e) {
          AppLogger.d('[PlayerScreen] Video player initialization failed: $e');
          await vc.dispose();
          // Dedicated googlevideo URL rejected (403/expired) — retry once
          // with the URL just_audio is already playing.
          final src = player.audioPlayer.sequenceState?.currentSource;
          if (!triedSharedFallback &&
              src is UriAudioSource &&
              src.uri != uriToTry) {
            triedSharedFallback = true;
            uriToTry = src.uri;
            continue;
          }
          // One delayed retry — a transient network/codec hiccup shouldn't
          // leave the cover art stuck forever.
          if (gen == _videoSetupGen && mounted && _isVideo) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted &&
                  _isVideo &&
                  _videoController == null &&
                  !_videoSetupInFlight &&
                  player.currentTrack?.id == track.id) {
                _setupVideoPlayer();
              }
            });
          }
          return;
        }
      }
    } finally {
      // Only clear when this run is still the latest — a superseding setup
      // owns the flag now.
      if (gen == _videoSetupGen) _videoSetupInFlight = false;
    }
  }

  /// googlevideo video formats reject requests that don't look like the
  /// YouTube app (403). Backend/proxy URLs don't need these.
  Map<String, String> _videoHeaders(Uri uri) {
    final host = uri.host;
    if (host.contains('googlevideo') ||
        host.endsWith('youtube.com') ||
        host.endsWith('youtu.be')) {
      return const {
        'User-Agent':
            'com.google.android.youtube/19.09.37 (Linux; U; Android 14) gzip',
        'Referer': 'https://www.youtube.com/',
      };
    }
    return const {};
  }

  /// Keeps the muted video surface aligned with just_audio.
  /// Self-heals a paused-forever video (missed events, buffering blips) and
  /// corrects real desync — but a CONSTANT offset between the two clocks is
  /// left alone: both players report position differently, and seeking every
  /// second flushes the decode pipeline and stutters the picture.
  void _startVideoSync() {
    _videoSyncTimer?.cancel();
    Duration? lastDrift;
    Duration? lastAudioPos;
    DateTime? lastTickAt;
    DateTime? lastCorrect;
    _videoSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final vc = _videoController;
      if (vc == null || !mounted) return;
      try {
        if (!vc.value.isInitialized) return;
        // Never fight the video while it is fetching data — seeking during
        // a buffer stall just resets the fetch every second.
        if (vc.value.isBuffering) return;
        final audioPlaying = player.audioPlayer.playing;
        final audioPos = player.audioPlayer.position;
        final drift = vc.value.position - audioPos;
        // Audio position jumped beyond what wall-clock explains = a real
        // seekbar/queue seek. Timer ticks can arrive seconds late on a busy
        // isolate — compare against elapsed time, not a fixed 1s.
        final now = DateTime.now();
        final audioSeeked = lastAudioPos != null &&
            lastTickAt != null &&
            ((audioPos - lastAudioPos!) - now.difference(lastTickAt!))
                    .abs() >
                const Duration(seconds: 2);
        lastAudioPos = audioPos;
        lastTickAt = now;
        const tol = Duration(milliseconds: 800);
        if (audioPlaying) {
          if (!vc.value.isPlaying) {
            // Resume once roughly in sync; a paused video that is off by
            // more than the tolerance gets snapped back first so it can
            // never be left frozen on a stale frame.
            if (drift.abs() <= tol) {
              vc.play();
            } else {
              vc.seekTo(audioPos);
            }
          } else if (audioSeeked) {
            vc.seekTo(audioPos);
            lastDrift = null;
            lastCorrect = DateTime.now();
          } else if (drift.abs() > tol) {
            // Correct only when the offset is still GROWING (real desync)
            // and at most once every 4s — a steady offset means the clocks
            // just report differently.
            final grew = lastDrift == null ||
                (drift.abs() - lastDrift!.abs()) >
                    const Duration(milliseconds: 250);
            final now = DateTime.now();
            if (grew &&
                (lastCorrect == null ||
                    now.difference(lastCorrect!) >
                        const Duration(seconds: 4))) {
              lastCorrect = now;
              lastDrift = null;
              vc.seekTo(audioPos);
            } else {
              lastDrift = drift;
            }
          } else {
            lastDrift = drift;
          }
        } else if (vc.value.isPlaying) {
          vc.pause();
        }
      } catch (_) {
        // Controller disposed mid-tick — safe to ignore.
      }
    });
  }

  @override
  void dispose() {
    _videoSetupGen++;
    _videoSyncTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    final vc = _videoController;
    _videoController = null;
    _videoUri = null;
    vc?.dispose();
    super.dispose();
  }

  String? _artistSlugFromTrack(Track t) => ArtistUtils.slugFromTrack(t);

  Future<void> _openArtist(BuildContext context, Track t) async {
    final slug = _artistSlugFromTrack(t);
    if (slug == null || slug.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Artist page not available for this track')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistScreen(artistSlug: slug),
      ),
    );
  }

  Future<void> _openShare(BuildContext context, Track track) async {
    final objectType = track.objectType ?? 'm_track';
    final objectHash = track.objectHash ?? track.id;
    showShareEmbedDialog(
      context,
      track: track,
      objectType: objectType,
      objectHash: objectHash,
    );
  }

  Future<void> _openQueue(BuildContext context) async {
    await QueueSheet.show(context, player);
  }

  Widget _fallbackBackground(ThemeData theme, {Key? key}) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
            theme.colorScheme.surface.withValues(alpha: 0.95),
            Colors.black.withValues(alpha: 0.95),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note,
          size: 120,
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
    );
  }

  /// YouTube Music-style Song/Video toggle pill. Only shown for video tracks.
  Widget _buildVideoModeToggle(Track track) {
    if (!_isVideo) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeChip(
              active: !_videoWanted,
              icon: Icons.headphones_rounded,
              label: 'Song',
              onTap: _toggleAudioVideo,
            ),
            _ModeChip(
              active: _videoWanted,
              icon: Icons.videocam_rounded,
              label: 'Video',
              onTap: _toggleAudioVideo,
            ),
            if (_videoWanted) _buildVideoQualityMenu(track),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverWidget(String? cover, Track track, ThemeData theme, {Key? key}) {
    final placeholder = Container(
      key: key,
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            (_isVideo && _videoWanted) ? Icons.videocam : Icons.music_note,
            color: Colors.white70,
            size: 72,
          ),
          const SizedBox(height: 14),
          Text(
            track.title.isNotEmpty ? track.title[0].toUpperCase() : '♪',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 56,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );

    return ClipRRect(
      key: key,
      borderRadius: BorderRadius.circular(16),
      child: CoverImage(
        imageUrl: cover,
        lookupTitle: track.title,
        lookupSubtitle: track.subtitle,
        placeholder: placeholder,
      ),
    );
  }

  String? _extractImageUrl(dynamic input) {
    return CoverImageExtractor.extract(input);
  }

  bool _isValidHttpUrl(String url) {
    final u = url.trim().replaceAll('\\/', '/');
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    try {
      final uri = Uri.parse(u);
      final host = uri.host.trim();
      if (host.isEmpty) return false;
      if (!host.contains('.')) return false;
      if (host.endsWith('.')) return false;
      if (host.length < 4) return false;
      final parts = host.split('.').where((p) => p.isNotEmpty).toList();
      if (parts.length < 2) return false;
      final tld = parts.last;
      if (tld.length < 2) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Normalize cover URL - convert relative to absolute and WebP to JPEG
  String? _normalizeCoverUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    var trimmed = url.trim();
    
    // Convert WebP to JPEG for Android compatibility
    // Handle URLs with query parameters like .webp?v=123
    final webpRegex = RegExp(r'\.webp([?#]|$)', caseSensitive: false);
    if (webpRegex.hasMatch(trimmed)) {
      trimmed = trimmed.replaceAll(webpRegex, '.jpg\$1');
      AppLogger.d('[PlayerScreen] Converted WebP to JPEG: $trimmed');
    }
    
    // If already absolute URL, return as-is
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      AppLogger.d('[PlayerScreen] Using absolute URL: $trimmed');
      return trimmed;
    }
    
    // If starts with //, add https:
    if (trimmed.startsWith('//')) {
      final result = 'https:$trimmed';
      AppLogger.d('[PlayerScreen] Converted protocol-relative URL: $result');
      return result;
    }
    
    // If starts with /, add domain
    if (trimmed.startsWith('/')) {
      final result = 'https://music.hitune.in$trimmed';
      AppLogger.d('[PlayerScreen] Converted relative URL: $result');
      return result;
    }
    
    // Otherwise, assume relative path
    final result = 'https://music.hitune.in/$trimmed';
    AppLogger.d('[PlayerScreen] Converted relative path: $result');
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = ThemeService.darkTheme;
    return Theme(
      data: darkTheme,
      child: GestureDetector(
        // Swipe down anywhere on the player minimizes it back to the mini bar.
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 400) {
            Navigator.of(context).maybePop();
          }
        },
        child: Scaffold(
        backgroundColor: darkTheme.scaffoldBackgroundColor,
        body: StreamBuilder(
          stream: player.currentTrackStream,
          initialData: player.currentTrack,
          builder: (context, snapshot) {
            final theme = Theme.of(context);
            final track = snapshot.data;
          if (track == null) {
            return const Center(child: Text('Nothing playing', style: TextStyle(color: Colors.white)));
          }

          // Debug logging for cover URL
          AppLogger.d('[PlayerScreen] Track: ${track.title}, coverUrl: ${track.coverUrl}');
          
          // Extract URL from HTML if needed, then normalize
          final extractedCover = _extractImageUrl(track.coverUrl);
          final normalizedCover = _normalizeCoverUrl(extractedCover);
          AppLogger.d('[PlayerScreen] Normalized cover: $normalizedCover');
          
          final cover = (normalizedCover != null && _isValidHttpUrl(normalizedCover)) ? normalizedCover : null;
          AppLogger.d('[PlayerScreen] Final cover URL (valid): $cover');

          return Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 700),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: cover != null
                    ? CachedNetworkImage(
                        key: ValueKey(cover),
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _fallbackBackground(theme),
                        errorWidget: (_, __, ___) => _fallbackBackground(theme),
                      )
                    : _fallbackBackground(theme, key: const ValueKey('fallback')),
                ),
              ),
              if (cover != null)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                    child: Container(color: Colors.black.withValues(alpha: 0.20)),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.05),
                        Colors.black.withValues(alpha: 0.65),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                          ),
                          Expanded(
                            child: Text(
                              'Now Playing',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _openQueue(context),
                            icon: const Icon(Icons.queue_music_rounded, color: Colors.white),
                          ),
                          IconButton(
                            tooltip: 'Audio Enhance',
                            onPressed: () => showAudioEnhanceSheet(context, player),
                            icon: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
                          ),
                          IconButton(
                            tooltip: 'Sleep Timer',
                            onPressed: () => SleepTimerSheet.show(context, player),
                            icon: const Icon(Icons.bedtime_outlined, color: Colors.white),
                          ),
                          IconButton(
                            tooltip: 'More',
                            onPressed: () => TrackActionsSheet.show(context, track, player: player),
                            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                          ),
                          PopupMenuButton<AudioQuality>(
                            initialValue: player.quality,
                            onSelected: (q) {
                              AuthGate.ensureLoggedIn(
                                context,
                                reason: 'Login required to change audio quality.',
                              ).then((ok) {
                                if (!ok) return;
                                player.setQuality(q);
                              });
                            },
                            itemBuilder: (context) {
                              return AudioQuality.values
                                  .map(
                                    (q) => PopupMenuItem<AudioQuality>(
                                      value: q,
                                      child: Text(q.label),
                                    ),
                                  )
                                  .toList(growable: false);
                            },
                            icon: const Icon(Icons.high_quality, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
                        child: Column(
                          children: [
                            _buildVideoModeToggle(track),
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    blurRadius: 70,
                                    spreadRadius: 8,
                                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                                    offset: const Offset(0, 20),
                                  ),
                                  BoxShadow(
                                    blurRadius: 50,
                                    spreadRadius: 4,
                                    color: Colors.black.withValues(alpha: 0.6),
                                    offset: const Offset(0, 24),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: AspectRatio(
                                  aspectRatio: _isVideo && _videoReady && _videoWanted
                                      ? _videoAspectRatio
                                      : 1,
                                  child: _isVideo && _videoReady && _videoWanted
                                      ? Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            VideoPlayer(_videoController!),
                                            // Video indicator badge
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withValues(alpha: 0.6),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.videocam, color: Colors.white, size: 14),
                                                    SizedBox(width: 4),
                                                    Text('VIDEO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      : AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 500),
                                          child: _buildCoverWidget(cover, track, theme, key: ValueKey(cover ?? track.id)),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              track.title,
                              style: theme.textTheme.headlineMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            if (track.isAiGenerated) ...[
                              const SizedBox(height: 8),
                              AiBadge(aiPct: track.aiPct, compact: false),
                            ],
                            const SizedBox(height: 6),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _openArtist(context, track),
                              child: Text(
                                track.subtitle ?? '',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  decoration: TextDecoration.underline,
                                  color: theme.colorScheme.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: FutureBuilder<bool>(
                                    future: player.isLiked(track),
                                    builder: (context, likedSnap) {
                                      final initial = likedSnap.data ?? false;
                                      return StreamBuilder<Set<String>>(
                                        stream: player.likedIdsStream,
                                        initialData: initial ? <String>{track.id} : const <String>{},
                                        builder: (context, idsSnap) {
                                          final liked = (idsSnap.data ?? const <String>{}).contains(track.id);
                                          final c = liked ? Colors.pinkAccent : Colors.white.withValues(alpha: 0.82);
                                          return Align(
                                            alignment: Alignment.centerLeft,
                                            child: IconButton(
                                              onPressed: () async {
                                                final ok = await AuthGate.ensureLoggedIn(
                                                  context,
                                                  reason: 'Login required to like tracks.',
                                                );
                                                if (!ok) return;
                                                await player.toggleLike(track);
                                              },
                                              icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: c),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _openQueue(context),
                                  icon: Icon(Icons.queue_music_rounded, color: Colors.white.withValues(alpha: 0.85), size: 18),
                                  label: Text(
                                    'Queue',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w700),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _openShare(context, track),
                                  icon: Icon(Icons.share_rounded, color: Colors.white.withValues(alpha: 0.85), size: 18),
                                  label: Text(
                                    'Share',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            _SeekBar(player: player),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  StreamBuilder<bool>(
                                    stream: player.shuffleEnabledStream,
                                    initialData: player.isShuffleEnabled,
                                    builder: (context, snap) {
                                      final enabled = snap.data ?? false;
                                      final color = enabled ? theme.colorScheme.primary : Colors.white.withValues(alpha: 0.70);
                                      return IconButton(
                                        onPressed: () async {
                                          final ok = await AuthGate.ensureLoggedIn(
                                            context,
                                            reason: 'Login required to change playback settings.',
                                          );
                                          if (!ok) return;
                                          await player.toggleShuffle();
                                        },
                                        icon: Icon(Icons.shuffle_rounded, color: color),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    onPressed: () async {
                                      final ok = await AuthGate.ensureLoggedIn(
                                        context,
                                        reason: 'Login required to control playback.',
                                      );
                                      if (!ok) return;
                                      await player.previous();
                                    },
                                    icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 40),
                                  ),
                                  StreamBuilder<PlayerState>(
                                    stream: player.playerStateStream,
                                    builder: (context, stateSnap) {
                                      final state = stateSnap.data;
                                      final processing = state?.processingState;
                                      final isPlaying = state?.playing ?? player.audioPlayer.playing;
                                      if (processing == ProcessingState.loading || processing == ProcessingState.buffering) {
                                        return Container(
                                          width: 74,
                                          height: 74,
                                          alignment: Alignment.center,
                                          child: const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        );
                                      }
                                      return Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                          boxShadow: [
                                            BoxShadow(
                                              blurRadius: 32,
                                              color: Colors.black.withValues(alpha: 0.55),
                                              offset: const Offset(0, 16),
                                            ),
                                            BoxShadow(
                                              blurRadius: 36,
                                              color: theme.colorScheme.primary.withValues(alpha: 0.20),
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                        child: IconButton(
                                          onPressed: () async {
                                            final ok = await AuthGate.ensureLoggedIn(
                                              context,
                                              reason: 'Login required to control playback.',
                                            );
                                            if (!ok) return;
                                            await player.togglePlayPause();
                                          },
                                          icon: Icon(
                                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                            color: Colors.black,
                                            size: 42,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    onPressed: () async {
                                      final ok = await AuthGate.ensureLoggedIn(
                                        context,
                                        reason: 'Login required to control playback.',
                                      );
                                      if (!ok) return;
                                      await player.next();
                                    },
                                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 40),
                                  ),
                                  StreamBuilder<LoopMode>(
                                    stream: player.loopModeStream,
                                    initialData: player.loopMode,
                                    builder: (context, snap) {
                                      final mode = snap.data ?? LoopMode.off;
                                      final enabled = mode != LoopMode.off;
                                      final color = enabled ? theme.colorScheme.primary : Colors.white.withValues(alpha: 0.70);
                                      final icon = mode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded;
                                      return IconButton(
                                        onPressed: () async {
                                          final ok = await AuthGate.ensureLoggedIn(
                                            context,
                                            reason: 'Login required to change playback settings.',
                                          );
                                          if (!ok) return;
                                          await player.cycleRepeatMode();
                                        },
                                        icon: Icon(icon, color: color),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            if (_artistSlugFromTrack(track) != null) ...[
                              const SizedBox(height: 22),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _openArtist(context, track),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: theme.colorScheme.primary.withValues(alpha: 0.18),
                                        ),
                                        child: Icon(Icons.person_rounded, color: theme.colorScheme.primary),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'About the artist',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.55),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              track.subtitle ?? 'Artist',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.6)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        ),
        ),
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  final PlayerService player;

  const _SeekBar({required this.player});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: Duration.zero,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: player.durationStream,
          builder: (context, durSnap) {
            final duration = durSnap.data ?? Duration.zero;

            final maxMs = duration.inMilliseconds > 0 ? duration.inMilliseconds : 1;
            final valueMs = position.inMilliseconds.clamp(0, maxMs);

            String fmt(Duration d) {
              final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
              final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
              return '$m:$s';
            }

            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.2,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
                    thumbColor: Colors.white,
                    overlayColor: theme.colorScheme.primary.withValues(alpha: 0.20),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: valueMs.toDouble(),
                    min: 0,
                    max: maxMs.toDouble(),
                    onChanged: (_) {},
                    onChangeEnd: (v) async {
                      final ok = await AuthGate.ensureLoggedIn(
                        context,
                        reason: 'Login required to seek.',
                      );
                      if (!ok) return;
                      await player.seek(Duration(milliseconds: v.round()));
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(fmt(position), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                    Text(fmt(duration), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ModeChip extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ModeChip({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? Colors.black : Colors.white.withValues(alpha: 0.8),
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.black : Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
