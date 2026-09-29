import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/audio/audio_enhancer.dart';
import '../player_service.dart';

/// Spotify-style audio enhancement controls: presets, loudness, bass,
/// stereo widening, a real dynamic compressor, and a band equalizer.
Future<void> showAudioEnhanceSheet(BuildContext context, PlayerService player) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.70),
    builder: (ctx) => AudioEnhanceSheet(player: player),
  );
}

class AudioEnhanceSheet extends StatelessWidget {
  final PlayerService player;

  const AudioEnhanceSheet({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enhancer = AudioEnhancerService.instance;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            top: false,
            child: ValueListenableBuilder<EnhanceState>(
              valueListenable: enhancer.state,
              builder: (context, s, _) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(Icons.graphic_eq_rounded, color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Audio Enhance',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Compressor, EQ, bass & surround',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: s.enabled,
                            onChanged: enhancer.setEnabled,
                            activeColor: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                      if (!enhancer.isSupported) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Audio enhancement is currently available on Android only.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _PresetRow(state: s, enhancer: enhancer, theme: theme),
                      const SizedBox(height: 10),
                      Opacity(
                        opacity: s.enabled ? 1.0 : 0.45,
                        child: IgnorePointer(
                          ignoring: !s.enabled,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FxSlider(
                                icon: Icons.surround_sound_rounded,
                                label: 'Loudness',
                                valueLabel: '+${s.loudnessDb.toStringAsFixed(1)} dB',
                                value: s.loudnessDb,
                                min: 0,
                                max: 10,
                                onChanged: enhancer.setLoudnessDb,
                                theme: theme,
                              ),
                              _FxSlider(
                                icon: Icons.speaker_rounded,
                                label: 'Bass Boost',
                                valueLabel: '${(s.bass * 100).round()}%',
                                value: s.bass,
                                onChanged: enhancer.setBass,
                                theme: theme,
                              ),
                              _FxSlider(
                                icon: Icons.weekend_rounded,
                                label: 'Stereo Widening',
                                valueLabel: '${(s.surround * 100).round()}%',
                                value: s.surround,
                                onChanged: enhancer.setSurround,
                                theme: theme,
                              ),
                              _FxSlider(
                                icon: Icons.compress_rounded,
                                label: 'Dynamic Compressor',
                                valueLabel: '${(s.compressor * 100).round()}%',
                                value: s.compressor,
                                onChanged: enhancer.setCompressor,
                                theme: theme,
                              ),
                              const SizedBox(height: 8),
                              _EqBands(enhancer: enhancer, state: s, theme: theme),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetRow extends StatelessWidget {
  final EnhanceState state;
  final AudioEnhancerService enhancer;
  final ThemeData theme;

  const _PresetRow({required this.state, required this.enhancer, required this.theme});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: EnhancePreset.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = EnhancePreset.values[i];
          final selected = state.preset == p;
          return ChoiceChip(
            label: Text(p.label),
            selected: selected,
            onSelected: (_) => enhancer.setPreset(p),
            labelStyle: TextStyle(
              color: selected ? Colors.black : Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            selectedColor: theme.colorScheme.primary,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
            side: BorderSide(
              color: selected ? theme.colorScheme.primary : Colors.white.withValues(alpha: 0.12),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }
}

class _FxSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ThemeData theme;

  const _FxSlider({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.onChanged,
    required this.theme,
    this.min = 0,
    this.max = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.75)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    valueLabel,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EqBands extends StatelessWidget {
  final AudioEnhancerService enhancer;
  final EnhanceState state;
  final ThemeData theme;

  const _EqBands({required this.enhancer, required this.state, required this.theme});

  String _freqLabel(double hz) {
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k';
    return hz.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({double minDb, double maxDb, List<double> centers})?>(
      future: enhancer.equalizerInfo(),
      builder: (context, snap) {
        final info = snap.data;
        if (info == null || info.centers.isEmpty) {
          return const SizedBox.shrink();
        }
        final gains = state.bandGains;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 20, color: Colors.white.withValues(alpha: 0.75)),
                const SizedBox(width: 10),
                Text(
                  'Equalizer',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 150,
              child: Row(
                children: [
                  for (var i = 0; i < info.centers.length; i++)
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                  activeTrackColor: theme.colorScheme.primary,
                                  inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                                  thumbColor: Colors.white,
                                ),
                                child: Slider(
                                  value: (i < gains.length ? gains[i] : 0.0).clamp(info.minDb, info.maxDb),
                                  min: info.minDb,
                                  max: info.maxDb,
                                  onChanged: (v) => enhancer.setBandGain(i, v),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _freqLabel(info.centers[i]),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
