import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/network/api_service.dart';
import '../../core/ui/ai_badge.dart';
import '../../core/ui/cover_image.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../iyol/iyol_publish_service.dart';
import '../player/models/track.dart';
import '../player/player_service.dart';

/// Vertical short-clips discovery feed (strategy doc §4).
///
/// Serves `/api/htx/clips` items — trending tracks each carrying a
/// 15-30s `clip` window ({start, duration}). Swiping vertically plays the
/// clip window of the visible card; "Open full song" hands the track to the
/// main player, and "Publish as Reel on IyolMe" renders a vertical video
/// (ai_studio clip_video job) and pushes it through /api/iyol_publish.
class ClipsScreen extends StatefulWidget {
  const ClipsScreen({super.key});

  @override
  State<ClipsScreen> createState() => _ClipsScreenState();
}

class _ClipsScreenState extends State<ClipsScreen> {
  final _api = ApiService.instance;
  final _pageCtrl = PageController();
  final List<_ClipItem> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  String? _error;
  int _current = 0;

  /// Dedicated inline player — clips must NOT go through the shared
  /// [PlayerService] queue (that would surface them in the mini/full MP3
  /// player). Resolved via PlayerService.resolveUrlFor, played clipped.
  final AudioPlayer _clipPlayer = AudioPlayer();
  int _playGen = 0;
  bool _clipLoading = false;
  StreamSubscription<PlayerState>? _stateSub;

  /// Inline video surface — when the resolver finds a real video rendition
  /// for the clip's track the card plays it reels-style (window-looped),
  /// otherwise the card falls back to cover art + clipped audio.
  VideoPlayerController? _clipVideo;
  bool _clipVideoReady = false;
  int _videoWinStart = 0;
  int _videoWinEnd = 0;

  @override
  void initState() {
    super.initState();
    _clipPlayer.setLoopMode(LoopMode.one);
    // Rebuild the card's play/pause icon as the clip player state changes.
    _stateSub = _clipPlayer.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _clipVideo?.dispose();
    _clipPlayer.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _disposeClipVideo() async {
    _clipVideoReady = false;
    final vc = _clipVideo;
    _clipVideo = null;
    if (vc != null) await vc.dispose();
  }

  /// Same headers the main player sends — googlevideo 403s the default UA.
  Map<String, String> _clipVideoHeaders(Uri uri) {
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

  /// Tries to play the clip as a windowed video. Returns true when a real
  /// video stream initialized; false means "use the audio-only fallback".
  Future<bool> _startClipVideo(String url, _ClipItem item, int gen) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final vc = VideoPlayerController.networkUrl(uri,
        httpHeaders: _clipVideoHeaders(uri));
    try {
      await vc.initialize().timeout(const Duration(seconds: 15));
      if (!mounted || gen != _playGen) {
        await vc.dispose();
        return false;
      }
      // Audio-only streams (saavn mp4 / audio itag) init fine but render
      // black — reject them so the cover fallback kicks in.
      if (vc.value.size.width <= 0 || vc.value.size.height <= 0) {
        await vc.dispose();
        return false;
      }
      _videoWinStart = item.start;
      _videoWinEnd = item.start + item.duration;
      var wasPlaying = vc.value.isPlaying;
      // Loop the clip window: when playback passes the end, jump back.
      vc.addListener(() {
        if (!vc.value.isInitialized) return;
        final pos = vc.value.position.inMilliseconds;
        if (_videoWinEnd > 0 && pos >= _videoWinEnd * 1000) {
          vc.seekTo(Duration(seconds: _videoWinStart));
        }
        // Rebuild only on play-state flips — position ticks are too hot.
        if (vc.value.isPlaying != wasPlaying) {
          wasPlaying = vc.value.isPlaying;
          if (mounted) setState(() {});
        }
      });
      // just_audio is the audio clock — mute the surface so a muxed
      // stream's own track never double-plays. Seek video to the window
      // start + however far the clipped audio already got (late init).
      await vc.setVolume(0);
      await vc.seekTo(Duration(seconds: _videoWinStart) +
          _clipPlayer.position);
      if (_clipPlayer.playing) await vc.play();
      _clipVideo = vc;
      _clipVideoReady = true;
      if (mounted) setState(() {});
      return true;
    } catch (_) {
      try {
        await vc.dispose();
      } catch (_) {}
      return false;
    }
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.postPayloadRaw(
      endpoint: 'htx/clips',
      data: {'limit': '20', 'page': '$_page'},
    );
    if (!mounted) return;
    if (!res.isSuccess || res.data == null) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Could not load clips';
      });
      return;
    }
    final raw = res.data!['items'];
    final list = raw is List ? raw : const [];
    final fresh = <_ClipItem>[];
    for (final it in list) {
      if (it is! Map) continue;
      final item = _ClipItem.fromJson(Map<String, dynamic>.from(it));
      if (item != null) fresh.add(item);
    }
    setState(() {
      _items.addAll(fresh);
      _loading = false;
      if (fresh.length < 20) _done = true;
      _page++;
    });
    if (_items.isNotEmpty && _current == 0) _playAt(0);
  }

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    final gen = ++_playGen;
    // Pause whatever the main player is doing so streams never overlap.
    try {
      await PlayerService.instance.audioPlayer.pause();
    } catch (_) {}
    if (mounted) setState(() => _clipLoading = true);
    await _disposeClipVideo();
    if (!mounted || gen != _playGen) return;
    try {
      // clipSourceFor reuses the main resolver — signed/CDN URLs get the
      // required headers, nothing is guessed.
      final source = await PlayerService.instance.clipSourceFor(
        item.track,
        startSec: item.start,
        durationSec: item.duration,
      );
      if (!mounted || gen != _playGen) return;
      if (source == null) {
        throw StateError(PlayerService.instance.lastError ?? 'no source');
      }
      await _clipPlayer.setAudioSource(source);
      if (!mounted || gen != _playGen) return;
      await _clipPlayer.play();
      // Resolution populated video candidates for YouTube/video tracks —
      // attach one as a muted visual over the clipped audio (same pattern
      // as the Now Playing video mode; just_audio stays the audio clock).
      final vUrl = PlayerService.instance.pickVideoUrl(item.track.id);
      if (vUrl != null && vUrl.isNotEmpty) {
        await _startClipVideo(vUrl, item, gen);
      }
    } catch (e) {
      if (mounted && gen == _playGen) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Clip could not be played: $e')));
      }
    } finally {
      if (mounted && gen == _playGen) setState(() => _clipLoading = false);
    }
  }

  Future<void> _publishReel(_ClipItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('Rendering reel, then publishing to your IyolMe account...')));
    final res = await IyolPublishService.instance.publishTrack(
      item.track,
      start: item.start,
      duration: item.duration,
    );
    if (!mounted) return;
    if (res.success) {
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(res.reelUrl != null && res.reelUrl!.isNotEmpty
            ? 'Reel live on IyolMe${res.username != null ? ' as @${res.username}' : ''}: ${res.reelUrl}'
            : 'Published as a reel on your IyolMe account'),
        action: (res.reelUrl != null && res.reelUrl!.isNotEmpty)
            ? SnackBarAction(
                label: 'Open',
                onPressed: () =>
                    launchUrl(Uri.parse(res.reelUrl!),
                        mode: LaunchMode.externalApplication),
              )
            : null,
      ));
    } else {
      messenger.showSnackBar(
          SnackBar(content: Text('Publish failed: ${res.error}')));
    }
  }

  void _openFull(_ClipItem item) {
    _playGen++;
    _disposeClipVideo();
    _clipPlayer.stop();
    PlayerService.instance.playTrack(item.track);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: const Text('Clips'),
      ),
      body: _error != null && _items.isEmpty
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
          : _items.isEmpty && _loading
              ? const Center(child: CircularProgressIndicator())
              : PageView.builder(
                  controller: _pageCtrl,
                  scrollDirection: Axis.vertical,
                  itemCount: _items.length + (_loading ? 1 : 0),
                  onPageChanged: (i) {
                    setState(() => _current = i);
                    if (i >= _items.length - 3) _load();
                    if (i < _items.length) _playAt(i);
                  },
                  itemBuilder: (context, i) {
                    if (i >= _items.length) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final item = _items[i];
                    final isCurrent = i == _current;
                    return _ClipCard(
                      item: item,
                      active: isCurrent,
                      videoController:
                          isCurrent && _clipVideoReady ? _clipVideo : null,
                      clipPlaying: isCurrent &&
                          !_clipLoading &&
                          (_clipVideoReady
                              ? (_clipVideo?.value.isPlaying ?? false)
                              : _clipPlayer.playing),
                      clipLoading: isCurrent && _clipLoading,
                      onPlayClip: () {
                        if (isCurrent && _clipVideoReady && _clipVideo != null) {
                          _clipVideo!.value.isPlaying
                              ? _clipVideo!.pause()
                              : _clipVideo!.play();
                        } else if (isCurrent && _clipPlayer.playing) {
                          _clipPlayer.pause();
                        } else if (isCurrent &&
                            _clipPlayer.audioSource != null &&
                            _clipPlayer.processingState ==
                                ProcessingState.ready) {
                          _clipPlayer.play();
                        } else {
                          _playAt(i);
                        }
                        setState(() {});
                      },
                      onOpenFull: () => _openFull(item),
                      onPublishReel: () => _publishReel(item),
                    );
                  },
                ),
    );
  }
}

class _ClipItem {
  final Track track;
  final int start;
  final int duration;

  _ClipItem({
    required this.track,
    required this.start,
    required this.duration,
  });

  static _ClipItem? fromJson(Map<String, dynamic> item) {
    final id = (item['ID'] ?? item['id'] ?? item['hash'] ?? item['object_hash'])?.toString();
    if (id == null || id.isEmpty) return null;
    final clip = item['clip'] is Map ? Map<String, dynamic>.from(item['clip']) : const {};
    final track = Track(
      id: id,
      title: (item['title'] ?? 'Unknown').toString(),
      subtitle: (item['sub_title'] ?? item['sub_data'] ?? '').toString(),
      url: (item['url'] ?? '').toString(),
      coverUrl: CoverImageExtractor.extract(item),
      objectType: (item['object_type'] ?? item['ot'] ?? 'm_track').toString(),
      objectHash: (item['hash'] ?? item['object_hash'] ?? id).toString(),
      aiPct: Track.aiPctFromJson(item),
    );
    return _ClipItem(
      track: track,
      start: (clip['start'] is num) ? clip['start'].toInt() : 30,
      duration: (clip['duration'] is num) ? clip['duration'].toInt() : 30,
    );
  }
}

class _ClipCard extends StatelessWidget {
  final _ClipItem item;
  final bool active;
  final bool clipPlaying;
  final bool clipLoading;
  final VideoPlayerController? videoController;
  final VoidCallback onOpenFull;
  final VoidCallback onPublishReel;
  final VoidCallback onPlayClip;

  const _ClipCard({
    required this.item,
    required this.active,
    required this.clipPlaying,
    required this.clipLoading,
    required this.videoController,
    required this.onOpenFull,
    required this.onPublishReel,
    required this.onPlayClip,
  });

  @override
  Widget build(BuildContext context) {
    final t = item.track;
    final vc = videoController;
    final hasVideo =
        vc != null && vc.value.isInitialized && vc.value.size.width > 0;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasVideo)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: vc.value.size.width,
              height: vc.value.size.height,
              child: VideoPlayer(vc),
            ),
          )
        else
          CoverImage(
          imageUrl: t.coverUrl,
          lookupTitle: t.title,
          lookupSubtitle: t.subtitle,
          fit: BoxFit.cover,
          placeholder: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1B1B2E), Color(0xFF0A0A14)],
              ),
            ),
            child: const Center(
              child: Icon(Icons.music_note_rounded,
                  color: Colors.white24, size: 96),
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.center,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 80,
          bottom: 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                AiBadge(aiPct: t.aiPct, compact: false),
              ]),
              if (t.subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(t.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70)),
                ),
              const SizedBox(height: 12),
              Text('${item.duration}s clip',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
        Positioned(
          right: 12,
          bottom: 48,
          child: Column(
            children: [
              IconButton(
                icon: clipLoading
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(
                        clipPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        color: Colors.white,
                        size: 34),
                tooltip: clipPlaying ? 'Pause clip' : 'Play clip',
                onPressed: onPlayClip,
              ),
              const SizedBox(height: 8),
              IconButton(
                icon: const Icon(Icons.open_in_full, color: Colors.white, size: 26),
                tooltip: 'Open full song',
                onPressed: onOpenFull,
              ),
              const SizedBox(height: 8),
              IconButton(
                icon: const Icon(Icons.video_call, color: Color(0xFF00B7FF), size: 30),
                tooltip: 'Publish as Reel on IyolMe',
                onPressed: onPublishReel,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
