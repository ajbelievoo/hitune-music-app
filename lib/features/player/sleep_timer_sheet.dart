import 'package:flutter/material.dart';

import '../subscription/feature_gate.dart';
import '../subscription/subscription_service.dart';
import 'player_service.dart';

/// Bottom sheet for the sleep timer (minutes or end-of-track).
class SleepTimerSheet extends StatelessWidget {
  final PlayerService player;

  const SleepTimerSheet({super.key, required this.player});

  static Future<void> show(BuildContext context, PlayerService player) async {
    final ok = await FeatureGate.require(context, AppFeatures.sleepTimer, customTitle: 'Sleep Timer');
    if (!ok || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SleepTimerSheet(player: player),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const options = [5, 10, 15, 20, 30, 45, 60];

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.bedtime_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sleep Timer',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<Duration?>(
            stream: player.sleepTimerStream,
            builder: (context, snap) {
              final remaining = player.sleepTimerRemaining;
              final active = player.isSleepTimerActive;
              if (!active) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  player.stopAfterCurrentTrack
                      ? 'Stops after the current track'
                      : 'Stops in ${_fmt(remaining ?? Duration.zero)}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final m in options)
                _TimerChip(
                  label: '$m min',
                  onTap: () {
                    player.setSleepTimer(Duration(minutes: m));
                    Navigator.of(context).pop();
                  },
                ),
              _TimerChip(
                label: 'End of track',
                icon: Icons.music_note_rounded,
                onTap: () {
                  player.setSleepTimerEndOfTrack();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (player.isSleepTimerActive)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  player.cancelSleepTimer();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.timer_off_rounded),
                label: const Text('Cancel timer'),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimerChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _TimerChip({required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: icon != null ? Icon(icon, size: 18, color: theme.colorScheme.primary) : null,
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
  }
}
