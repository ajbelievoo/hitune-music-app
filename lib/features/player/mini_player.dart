import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../auth/auth_gate.dart';
import '../artist/artist_screen.dart';
import '../../core/ui/cover_image.dart';
import '../../core/utils/artist_utils.dart';
import '../../core/utils/cover_image_extractor.dart';
import 'models/track.dart';
import 'player_screen.dart';
import 'player_service.dart';

/// Fixed bottom mini-player bar.
///
/// Tapping the bar opens the full player. Play/pause and skip controls are
/// always visible. The bar is hidden when no track is loaded.
class MiniPlayer extends StatelessWidget {
  final PlayerService player;

  const MiniPlayer({super.key, required this.player});

  String? _extractImageUrl(dynamic input) {
    return CoverImageExtractor.extract(input);
  }

  bool _isValidHttpUrl(String url) {
    final u = url.trim().replaceAll('\\/', '/');
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    try {
      final uri = Uri.parse(u);
      final host = uri.host.trim().toLowerCase();
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

  String? _artistSlugFromTrack(Track t) => ArtistUtils.slugFromTrack(t);

  void _openArtist(BuildContext context, Track t) {
    final slug = _artistSlugFromTrack(t);
    if (slug == null || slug.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ArtistScreen(artistSlug: slug)),
    );
  }

  Future<void> _openFullPlayer(BuildContext context) async {
    final ok = await AuthGate.ensureLoggedIn(
      context,
      reason: 'Login required to view the full player.',
    );
    if (!ok) return;
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PlayerScreen(player: player)),
      );
    }
  }

  Widget _buildCover(BuildContext context, Track track) {
    final extracted = _extractImageUrl(track.coverUrl);
    final cover = _normalizeCoverUrl(extracted);
    final hasValid = cover != null && cover.trim().isNotEmpty && _isValidHttpUrl(cover);

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 48,
        height: 48,
        child: CoverImage(
          imageUrl: hasValid ? cover : null,
          lookupTitle: track.title,
          lookupSubtitle: track.subtitle,
          placeholder: _placeholder(context, track),
        ),
      ),
    );
  }

  String? _normalizeCoverUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    var trimmed = url.trim().replaceAll('\\/', '/');

    // Convert WebP to JPEG for Android compatibility
    final webpRegex = RegExp(r'\.webp([?#]|$)', caseSensitive: false);
    if (webpRegex.hasMatch(trimmed)) {
      trimmed = trimmed.replaceAll(webpRegex, '.jpg\$1');
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    if (trimmed.startsWith('/')) return 'https://music.hitune.in$trimmed';
    return 'https://music.hitune.in/$trimmed';
  }

  Widget _placeholder(BuildContext context, Track track) {
    final theme = Theme.of(context);
    final initial = track.title.isNotEmpty ? track.title[0].toUpperCase() : '♪';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.25),
            theme.colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<Track?>(
      stream: player.currentTrackStream,
      initialData: player.currentTrack,
      builder: (context, snap) {
        final track = snap.data;
        if (track == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => _openFullPlayer(context),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress indicator
                  StreamBuilder<Duration>(
                    stream: player.positionStream,
                    initialData: Duration.zero,
                    builder: (context, posSnap) {
                      return StreamBuilder<Duration?>(
                        stream: player.durationStream,
                        builder: (context, durSnap) {
                          final duration = durSnap.data ?? Duration.zero;
                          final totalMs = duration.inMilliseconds;
                          final value = (totalMs <= 0)
                              ? 0.0
                              : (posSnap.data!.inMilliseconds / totalMs).clamp(0.0, 1.0);
                          return LinearProgressIndicator(
                            minHeight: 2,
                            value: value,
                            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                          );
                        },
                      );
                    },
                  ),
                  // Controls row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        _buildCover(context, track),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                              if (track.subtitle?.isNotEmpty == true)
                                GestureDetector(
                                  onTap: () => _openArtist(context, track),
                                  child: Text(
                                    track.subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            await player.audioPlayer.seekToPrevious();
                            if (!player.audioPlayer.playing) await player.audioPlayer.play();
                          },
                          icon: Icon(Icons.skip_previous_rounded, color: theme.iconTheme.color),
                        ),
                        StreamBuilder<PlayerState>(
                          stream: player.playerStateStream,
                          builder: (context, stateSnap) {
                            final state = stateSnap.data;
                            final isPlaying = state?.playing ?? player.audioPlayer.playing;
                            final processing = state?.processingState;

                            if (processing == ProcessingState.loading ||
                                processing == ProcessingState.buffering) {
                              return const SizedBox(
                                width: 44,
                                height: 44,
                                child: Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              );
                            }

                            return IconButton(
                              onPressed: () async {
                                if (player.audioPlayer.playing) {
                                  await player.audioPlayer.pause();
                                } else {
                                  await player.audioPlayer.play();
                                }
                              },
                              icon: Icon(
                                isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                                color: theme.colorScheme.primary,
                                size: 40,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          onPressed: () async {
                            await player.audioPlayer.seekToNext();
                            if (!player.audioPlayer.playing) await player.audioPlayer.play();
                          },
                          icon: Icon(Icons.skip_next_rounded, color: theme.iconTheme.color),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
