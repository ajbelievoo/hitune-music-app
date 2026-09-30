import 'package:flutter/material.dart';

import '../../core/cast/cast_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/artist_utils.dart';
import '../artist/artist_screen.dart';
import '../auth/auth_gate.dart';
import '../comments/comments_sheet.dart';
import '../downloads/download_service.dart';
import '../iyol/iyol_deeplink.dart';
import '../iyol/iyol_publish_service.dart';
import '../library/playlist_picker_sheet.dart';
import '../share/share_dialog.dart';
import '../subscription/feature_gate.dart';
import '../subscription/subscription_service.dart';
import '../tipping/tip_sheet.dart';
import 'lyrics_screen.dart';
import 'models/track.dart';
import 'player_service.dart';
import 'queue_sheet.dart';
import 'sleep_timer_sheet.dart';

/// Shared "..." actions for a track: play next, queue, playlist,
/// download, lyrics, comments, cast, share.
class TrackActionsSheet extends StatelessWidget {
  final Track track;
  final PlayerService player;

  /// A context that stays alive after this sheet is popped (e.g. the
  /// screen that opened it). All follow-up dialogs/gates must use this,
  /// never the sheet's own context.
  final BuildContext rootContext;

  const TrackActionsSheet({
    super.key,
    required this.track,
    required this.player,
    required this.rootContext,
  });

  static Future<void> show(BuildContext context, Track track, {PlayerService? player}) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TrackActionsSheet(
        track: track,
        player: player ?? PlayerService.instance,
        rootContext: context,
      ),
    );
  }

  Future<void> _download(BuildContext sheetContext) async {
    final ok = await FeatureGate.require(rootContext, AppFeatures.offlineDownloads, customTitle: 'Offline Downloads');
    if (!ok || !sheetContext.mounted) return;

    final messenger = ScaffoldMessenger.of(rootContext);
    Navigator.of(sheetContext).pop();
    messenger.showSnackBar(const SnackBar(content: Text('Downloading...')));

    try {
      final url = await player.resolveUrlFor(track);
      if (url.contains('.m3u8') || url.contains('.ts')) {
        messenger.showSnackBar(const SnackBar(content: Text('This track cannot be downloaded (stream only)')));
        return;
      }
      await DownloadService.instance.download(track, url);
      messenger.showSnackBar(const SnackBar(content: Text('Downloaded for offline playback')));
    } catch (e) {
      AppLogger.d('[TrackActions] download failed: $e');
      messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(track.subtitle ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: track.isExplicit
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('E', style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w900, fontSize: 11)),
                  )
                : null,
          ),
          Divider(color: theme.dividerColor, height: 8),
          _ActionTile(
            icon: Icons.queue_play_next_rounded,
            label: 'Play Next',
            onTap: () async {
              Navigator.of(context).pop();
              final ok = await AuthGate.ensureLoggedIn(rootContext, reason: 'Login required to manage the queue.');
              if (ok) await player.playNext(track);
            },
          ),
          _ActionTile(
            icon: Icons.queue_music_rounded,
            label: 'Add to Queue',
            onTap: () async {
              Navigator.of(context).pop();
              final ok = await AuthGate.ensureLoggedIn(rootContext, reason: 'Login required to manage the queue.');
              if (ok) await player.addToQueue(track);
            },
          ),
          _ActionTile(
            icon: Icons.playlist_add_rounded,
            label: 'Add to Playlist',
            onTap: () async {
              Navigator.of(context).pop();
              final ok = await AuthGate.ensureLoggedIn(rootContext, reason: 'Login required to use playlists.');
              if (!ok || !rootContext.mounted) return;
              final gated = await FeatureGate.require(rootContext, AppFeatures.playlists, customTitle: 'Playlists');
              if (!gated || !rootContext.mounted) return;
              await PlaylistPickerSheet.show(rootContext, track);
            },
          ),
          _ActionTile(
            icon: Icons.lyrics_rounded,
            label: 'Lyrics',
            onTap: () {
              Navigator.of(context).pop();
              LyricsScreen.open(rootContext, track);
            },
          ),
          _ActionTile(
            icon: Icons.download_rounded,
            label: 'Download',
            onTap: () => _download(context),
          ),
          _ActionTile(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Comments',
            onTap: () async {
              Navigator.of(context).pop();
              final gated = await FeatureGate.require(rootContext, AppFeatures.comments, customTitle: 'Comments');
              if (!gated || !rootContext.mounted) return;
              await CommentsSheet.show(rootContext, track);
            },
          ),
          if (CastService.instance.isAvailable)
            _ActionTile(
              icon: Icons.cast_rounded,
              label: 'Cast',
              onTap: () async {
                Navigator.of(context).pop();
                final gated = await FeatureGate.require(rootContext, AppFeatures.casting, customTitle: 'Chromecast / AirPlay');
                if (!gated) return;
                // Native Cast SDK wiring pending - see docs/BACKEND_REQUIREMENTS.md
              },
            ),
          _ActionTile(
            icon: Icons.share_rounded,
            label: 'Share',
            onTap: () {
              Navigator.of(context).pop();
              showShareEmbedDialog(
                rootContext,
                track: track,
                objectType: track.objectType ?? 'm_track',
                objectHash: track.objectHash ?? track.id,
              );
            },
          ),
          _ActionTile(
            icon: Icons.movie_creation_outlined,
            label: 'Create Reel on IyolMe',
            onTap: () async {
              Navigator.of(context).pop();
              final ok = await IyolDeepLink.openReelCreate(track);
              if (!ok && rootContext.mounted) {
                ScaffoldMessenger.of(rootContext).showSnackBar(const SnackBar(
                    content: Text('Install IyolMe to create reels with this song')));
              }
            },
          ),
          _ActionTile(
            icon: Icons.video_call_rounded,
            label: 'Publish as Reel on IyolMe',
            onTap: () async {
              Navigator.of(context).pop();
              final ok = await AuthGate.ensureLoggedIn(rootContext,
                  reason: 'Login required to publish to IyolMe.');
              if (!ok || !rootContext.mounted) return;
              final messenger = ScaffoldMessenger.of(rootContext);
              messenger.showSnackBar(
                  const SnackBar(content: Text('Rendering clip for IyolMe...')));
              final res = await IyolPublishService.instance.publishTrack(track);
              if (!rootContext.mounted) return;
              messenger.showSnackBar(SnackBar(
                content: Text(res.success
                    ? 'Published as reel on IyolMe'
                    : 'Publish failed: ${res.error}'),
              ));
            },
          ),
          _ActionTile(
            icon: Icons.volunteer_activism_rounded,
            label: 'Tip Artist',
            onTap: () async {
              Navigator.of(context).pop();
              final ok = await AuthGate.ensureLoggedIn(rootContext,
                  reason: 'Login required to tip artists.');
              if (!ok || !rootContext.mounted) return;
              await TipSheet.show(rootContext, track);
            },
          ),
          _ActionTile(
            icon: Icons.queue_music_outlined,
            label: 'View Queue',
            onTap: () {
              Navigator.of(context).pop();
              QueueSheet.show(rootContext, player);
            },
          ),
          _ActionTile(
            icon: Icons.person_rounded,
            label: 'Go to Artist',
            onTap: () {
              Navigator.of(context).pop();
              final slug = ArtistUtils.slugFromTrack(track);
              if (slug == null || slug.isEmpty) {
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  const SnackBar(content: Text('Artist page not available for this track')),
                );
                return;
              }
              Navigator.of(rootContext).push(
                MaterialPageRoute<void>(builder: (_) => ArtistScreen(artistSlug: slug)),
              );
            },
          ),
          _ActionTile(
            icon: Icons.bedtime_outlined,
            label: 'Sleep Timer',
            onTap: () {
              Navigator.of(context).pop();
              SleepTimerSheet.show(rootContext, player);
            },
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final void Function()? onTap;

  const _ActionTile({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon, color: theme.iconTheme.color?.withValues(alpha: 0.75)),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}
