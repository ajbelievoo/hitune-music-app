import 'dart:ui';

import 'package:flutter/material.dart';

import '../auth/auth_gate.dart';
import 'models/track.dart';
import 'player_service.dart';

/// Full queue management sheet: reorder (drag), remove (swipe), tap to play.
class QueueSheet extends StatelessWidget {
  final PlayerService player;

  const QueueSheet({super.key, required this.player});

  static Future<void> show(BuildContext context, PlayerService player) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.70),
      builder: (ctx) => QueueSheet(player: player),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.72,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Queue',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      StreamBuilder<List<Track>>(
                        stream: player.queueStream,
                        initialData: player.queue,
                        builder: (context, snap) => Text(
                          '${(snap.data ?? const []).length} tracks',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                        ),
                      ),
                      StreamBuilder<bool>(
                        stream: player.autoplayStream,
                        initialData: player.autoplayEnabled,
                        builder: (context, snap) {
                          final on = snap.data ?? true;
                          return IconButton(
                            tooltip: on ? 'Autoplay on — similar songs keep playing' : 'Autoplay off',
                            onPressed: () => player.setAutoplay(!on),
                            icon: Icon(
                              Icons.all_inclusive_rounded,
                              color: on ? theme.colorScheme.primary : Colors.white.withValues(alpha: 0.4),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: StreamBuilder<List<Track>>(
                    stream: player.queueStream,
                    initialData: player.queue,
                    builder: (context, queueSnap) {
                      final queue = queueSnap.data ?? const <Track>[];
                      if (queue.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Queue is empty', style: TextStyle(color: Colors.white70)),
                        );
                      }
                      return StreamBuilder<int?>(
                        stream: player.audioPlayer.currentIndexStream,
                        initialData: player.index,
                        builder: (context, indexSnap) {
                          final currentIndex = indexSnap.data ?? player.index;
                          return ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                            itemCount: queue.length,
                            onReorder: (oldIndex, newIndex) async {
                              final ok = await AuthGate.ensureLoggedIn(
                                context,
                                reason: 'Login required to manage the queue.',
                              );
                              if (!ok) return;
                              var target = newIndex;
                              if (target > oldIndex) target -= 1;
                              await player.moveQueueItem(oldIndex, target);
                            },
                            itemBuilder: (context, i) {
                              final t = queue[i];
                              final active = i == currentIndex;
                              return Dismissible(
                                key: ValueKey('${t.id}_$i'),
                                direction: active
                                    ? DismissDirection.none
                                    : DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  color: Colors.red.withValues(alpha: 0.35),
                                  child: const Icon(Icons.delete_rounded, color: Colors.white),
                                ),
                                onDismissed: (_) => player.removeFromQueueAt(i),
                                child: ListTile(
                                  onTap: () async {
                                    final ok = await AuthGate.ensureLoggedIn(
                                      context,
                                      reason: 'Login required to play from queue.',
                                    );
                                    if (!ok) return;
                                    await player.skipToIndex(i);
                                    if (context.mounted) Navigator.of(context).pop();
                                  },
                                  dense: true,
                                  leading: active
                                      ? Icon(Icons.graphic_eq_rounded, color: theme.colorScheme.primary)
                                      : Text(
                                          '${i + 1}',
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.55),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                  title: Text(
                                    t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: active ? Colors.white : Colors.white.withValues(alpha: 0.85),
                                      fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    t.subtitle ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (active)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(99),
                                            color: theme.colorScheme.primary.withValues(alpha: 0.18),
                                            border: Border.all(
                                              color: theme.colorScheme.primary.withValues(alpha: 0.35),
                                            ),
                                          ),
                                          child: Text(
                                            'Playing',
                                            style: TextStyle(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        )
                                      else
                                        ReorderableDragStartListener(
                                          index: i,
                                          child: Icon(
                                            Icons.drag_handle_rounded,
                                            color: Colors.white.withValues(alpha: 0.4),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
