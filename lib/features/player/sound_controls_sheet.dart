import 'package:flutter/material.dart';

import '../subscription/feature_gate.dart';
import '../subscription/subscription_service.dart';
import 'player_service.dart';

/// Sound controls sheet: playback speed, pitch and silence skipping.
/// (A full band equalizer requires a native EQ engine - see backend doc.)
class SoundControlsSheet extends StatelessWidget {
  final PlayerService player;

  const SoundControlsSheet({super.key, required this.player});

  static Future<void> show(BuildContext context, PlayerService player) async {
    final ok = await FeatureGate.require(context, AppFeatures.soundControls, customTitle: 'Sound Controls');
    if (!ok || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SoundControlsSheet(player: player),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.tune_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Sound Controls',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 20),
          StreamBuilder<double>(
            stream: player.speedStream,
            initialData: player.speed,
            builder: (context, snap) {
              final speed = snap.data ?? 1.0;
              return _SliderRow(
                title: 'Speed',
                value: speed,
                min: 0.5,
                max: 2.0,
                divisions: 30,
                label: '${speed.toStringAsFixed(2)}x',
                onChanged: player.setSpeed,
                onReset: () => player.setSpeed(1.0),
              );
            },
          ),
          const SizedBox(height: 8),
          StreamBuilder<double>(
            stream: player.pitchStream,
            initialData: player.pitch,
            builder: (context, snap) {
              final pitch = snap.data ?? 1.0;
              return _SliderRow(
                title: 'Pitch',
                value: pitch,
                min: 0.5,
                max: 2.0,
                divisions: 30,
                label: '${pitch.toStringAsFixed(2)}x',
                onChanged: player.setPitch,
                onReset: () => player.setPitch(1.0),
              );
            },
          ),
          const SizedBox(height: 8),
          StreamBuilder<bool>(
            stream: player.skipSilenceEnabledStream,
            initialData: player.skipSilenceEnabled,
            builder: (context, snap) {
              final enabled = snap.data ?? false;
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Skip silence'),
                subtitle: const Text('Automatically skip silent sections'),
                value: enabled,
                onChanged: (v) => player.setSkipSilence(v),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  const _SliderRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = value.clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
            IconButton(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt_rounded, size: 20),
              tooltip: 'Reset',
            ),
          ],
        ),
        Slider(
          value: clamped,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
