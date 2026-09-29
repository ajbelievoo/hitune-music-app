import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';

/// Preset identifiers for the audio enhancement engine.
enum EnhancePreset {
  off,
  punch,
  bass,
  vocal,
  night,
  custom;

  String get label {
    switch (this) {
      case EnhancePreset.off:
        return 'Off';
      case EnhancePreset.punch:
        return 'HiTune Punch';
      case EnhancePreset.bass:
        return 'Bass Booster';
      case EnhancePreset.vocal:
        return 'Vocal Clarity';
      case EnhancePreset.night:
        return 'Night Mode';
      case EnhancePreset.custom:
        return 'Custom';
    }
  }
}

/// Immutable snapshot of every user-tunable enhancement parameter.
class EnhanceState {
  const EnhanceState({
    required this.enabled,
    required this.preset,
    required this.loudnessDb,
    required this.bass,
    required this.surround,
    required this.compressor,
    required this.bandGains,
  });

  final bool enabled;
  final EnhancePreset preset;

  /// Loudness enhancer target gain in decibels (0..10).
  final double loudnessDb;

  /// Bass boost amount 0..1.
  final double bass;

  /// Stereo widening / virtualizer amount 0..1.
  final double surround;

  /// Dynamic compressor amount 0..1.
  final double compressor;

  /// Custom EQ band gains in dB (may be empty before parameters resolve).
  final List<double> bandGains;

  EnhanceState copyWith({
    bool? enabled,
    EnhancePreset? preset,
    double? loudnessDb,
    double? bass,
    double? surround,
    double? compressor,
    List<double>? bandGains,
  }) {
    return EnhanceState(
      enabled: enabled ?? this.enabled,
      preset: preset ?? this.preset,
      loudnessDb: loudnessDb ?? this.loudnessDb,
      bass: bass ?? this.bass,
      surround: surround ?? this.surround,
      compressor: compressor ?? this.compressor,
      bandGains: bandGains ?? this.bandGains,
    );
  }

  static const initial = EnhanceState(
    enabled: false,
    preset: EnhancePreset.off,
    loudnessDb: 0,
    bass: 0,
    surround: 0,
    compressor: 0,
    bandGains: <double>[],
  );
}

/// Central audio enhancement engine.
///
/// Uses just_audio's built-in [AudioPipeline] for the equalizer and loudness
/// enhancer, plus a MethodChannel for native Android effects that just_audio
/// does not expose: [BassBoost], [Virtualizer] (stereo widening) and
/// [DynamicsProcessing] (multi-band compressor + limiter).
class AudioEnhancerService {
  AudioEnhancerService._();

  static final AudioEnhancerService instance = AudioEnhancerService._();

  static const _channel = MethodChannel('hitune/audio_fx');

  static const _kEnabled = 'audio_enh_enabled';
  static const _kPreset = 'audio_enh_preset';
  static const _kLoudness = 'audio_enh_loudness';
  static const _kBass = 'audio_enh_bass';
  static const _kSurround = 'audio_enh_surround';
  static const _kCompressor = 'audio_enh_compressor';
  static const _kBandGains = 'audio_enh_band_gains';

  /// just_audio managed effects. Attach these via [buildPipeline] before the
  /// [AudioPlayer] is constructed.
  final AndroidEqualizer equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer loudnessEnhancer = AndroidLoudnessEnhancer();

  final ValueNotifier<EnhanceState> state = ValueNotifier<EnhanceState>(EnhanceState.initial);

  StreamSubscription<int?>? _sessionSub;
  AudioPlayer? _player;
  int? _sessionId;
  bool _loaded = false;
  bool _eqBandApplyQueued = false;

  /// Per-track loudness normalization gain in dB (Spotify-style, -14 LUFS
  /// target). Zero when the backend provides no loudness metadata.
  double _trackGainDb = 0;

  /// Whether the platform supports the enhancement engine at all.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Pipeline to pass into the [AudioPlayer] constructor.
  AudioPipeline buildPipeline() => AudioPipeline(
        androidAudioEffects: [loudnessEnhancer, equalizer],
      );

  /// Wire session tracking and restore persisted settings.
  void bindToPlayer(AudioPlayer player) {
    _player = player;
    _sessionSub ??= player.androidAudioSessionIdStream.listen((id) {
      if (id == null || id == _sessionId) return;
      _sessionId = id;
      AppLogger.d('[AudioEnhancer] audio session changed: $id');
      _attachNative(id);
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final presetName = prefs.getString(_kPreset) ?? EnhancePreset.off.name;
    final preset = EnhancePreset.values.firstWhere(
      (p) => p.name == presetName,
      orElse: () => EnhancePreset.off,
    );
    final rawGains = prefs.getString(_kBandGains) ?? '';
    final gains = rawGains
        .split(',')
        .map((e) => double.tryParse(e.trim()) ?? 0.0)
        .where((e) => e.isFinite)
        .toList();
    state.value = EnhanceState(
      enabled: prefs.getBool(_kEnabled) ?? false,
      preset: preset,
      loudnessDb: prefs.getDouble(_kLoudness) ?? 0,
      bass: prefs.getDouble(_kBass) ?? 0,
      surround: prefs.getDouble(_kSurround) ?? 0,
      compressor: prefs.getDouble(_kCompressor) ?? 0,
      bandGains: gains,
    );
    await _applyAll();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final s = state.value;
    await prefs.setBool(_kEnabled, s.enabled);
    await prefs.setString(_kPreset, s.preset.name);
    await prefs.setDouble(_kLoudness, s.loudnessDb);
    await prefs.setDouble(_kBass, s.bass);
    await prefs.setDouble(_kSurround, s.surround);
    await prefs.setDouble(_kCompressor, s.compressor);
    if (s.bandGains.isNotEmpty) {
      await prefs.setString(_kBandGains, s.bandGains.map((e) => e.toStringAsFixed(2)).join(','));
    }
  }

  // ---------------------------------------------------------------------------
  // Presets
  // ---------------------------------------------------------------------------

  /// Preset band curves expressed as 5 normalized gains
  /// [sub-bass, bass, mid, presence, treble] in dB. Mapped onto however many
  /// bands the device equalizer actually exposes.
  static const Map<EnhancePreset, List<double>> _presetCurves = {
    EnhancePreset.punch: [3.0, 2.0, -0.5, 1.5, 3.0],
    EnhancePreset.bass: [5.0, 4.0, 0.0, 0.0, 1.0],
    EnhancePreset.vocal: [-1.5, -0.5, 2.5, 3.0, 1.0],
    EnhancePreset.night: [1.0, 0.5, 0.5, -0.5, -1.5],
  };

  static const Map<EnhancePreset, ({double bass, double surround, double compressor, double loudness})> _presetFx = {
    EnhancePreset.punch: (bass: 0.35, surround: 0.35, compressor: 0.55, loudness: 3.0),
    EnhancePreset.bass: (bass: 0.75, surround: 0.15, compressor: 0.30, loudness: 2.0),
    EnhancePreset.vocal: (bass: 0.10, surround: 0.25, compressor: 0.40, loudness: 2.0),
    EnhancePreset.night: (bass: 0.10, surround: 0.10, compressor: 0.85, loudness: 0.0),
  };

  Future<void> setPreset(EnhancePreset preset) async {
    if (preset == EnhancePreset.custom) {
      state.value = state.value.copyWith(preset: preset);
      await _save();
      return;
    }
    if (preset == EnhancePreset.off) {
      state.value = EnhanceState.initial.copyWith(bandGains: state.value.bandGains);
      await _applyAll();
      await _save();
      return;
    }
    final fx = _presetFx[preset]!;
    final curve = _presetCurves[preset]!;
    final gains = await _mapCurveToBands(curve);
    state.value = state.value.copyWith(
      enabled: true,
      preset: preset,
      loudnessDb: fx.loudness,
      bass: fx.bass,
      surround: fx.surround,
      compressor: fx.compressor,
      bandGains: gains,
    );
    await _applyAll();
    await _save();
  }

  /// Map a 5-point normalized curve onto the device's actual EQ bands.
  /// Falls back to the raw curve when the player has not activated the
  /// equalizer yet (parameters resolve only once playback starts).
  Future<List<double>> _mapCurveToBands(List<double> curve) async {
    try {
      final params = await equalizer.parameters.timeout(const Duration(seconds: 2));
      final bands = params.bands;
      if (bands.isEmpty) return const [];
      final count = bands.length;
      final gains = List<double>.filled(count, 0);
      for (var i = 0; i < count; i++) {
        // Interpolate the normalized curve at the band's fractional position.
        final pos = count == 1 ? 0.5 : i / (count - 1) * (curve.length - 1);
        final lo = pos.floor().clamp(0, curve.length - 1);
        final hi = (lo + 1).clamp(0, curve.length - 1);
        final t = pos - lo;
        var gain = curve[lo] + (curve[hi] - curve[lo]) * t;
        gain = gain.clamp(params.minDecibels, params.maxDecibels);
        gains[i] = gain;
      }
      return gains;
    } catch (e) {
      // Player not active yet — keep the normalized curve as-is; it maps
      // reasonably onto the common 5-band equalizers.
      return List<double>.from(curve);
    }
  }

  // ---------------------------------------------------------------------------
  // Individual setters (switch to custom preset on manual tweak)
  // ---------------------------------------------------------------------------

  Future<void> setEnabled(bool enabled) async {
    if (enabled && state.value.preset == EnhancePreset.off) {
      await setPreset(EnhancePreset.punch);
      return;
    }
    state.value = state.value.copyWith(enabled: enabled);
    await _applyAll();
    await _save();
  }

  Future<void> setLoudnessDb(double db) async {
    state.value = state.value.copyWith(loudnessDb: db, preset: EnhancePreset.custom);
    await _applyLoudness();
    await _save();
  }

  Future<void> setBass(double v) async {
    state.value = state.value.copyWith(bass: v, preset: EnhancePreset.custom);
    await _applyBass();
    await _save();
  }

  Future<void> setSurround(double v) async {
    state.value = state.value.copyWith(surround: v, preset: EnhancePreset.custom);
    await _applySurround();
    await _save();
  }

  Future<void> setCompressor(double v) async {
    state.value = state.value.copyWith(compressor: v, preset: EnhancePreset.custom);
    await _applyCompressor();
    await _save();
  }

  Future<void> setBandGain(int index, double gain) async {
    final gains = List<double>.from(state.value.bandGains);
    if (index < 0 || index >= gains.length) return;
    gains[index] = gain;
    state.value = state.value.copyWith(bandGains: gains, preset: EnhancePreset.custom);
    try {
      final params = await equalizer.parameters.timeout(const Duration(seconds: 2));
      if (index < params.bands.length) {
        await params.bands[index].setGain(gain);
      }
    } catch (_) {
      // Params not ready yet (player not active) — queue a deferred apply.
      unawaited(_applyBandGainsWhenReady());
    }
    await _save();
  }

  /// Live EQ band descriptors for the UI (center frequencies + range).
  Future<({double minDb, double maxDb, List<double> centers})?> equalizerInfo() async {
    try {
      final params = await equalizer.parameters;
      return (
        minDb: params.minDecibels,
        maxDb: params.maxDecibels,
        centers: params.bands.map((b) => b.centerFrequency).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Apply
  // ---------------------------------------------------------------------------

  /// Applies stored band gains once the platform equalizer parameters resolve
  /// (they only become available after the player activates the effect).
  /// Reads the latest state after the wait so queued calls pick up the
  /// newest gains.
  Future<void> _applyBandGainsWhenReady() async {
    if (_eqBandApplyQueued) return;
    _eqBandApplyQueued = true;
    try {
      final params = await equalizer.parameters;
      var stored = List<double>.from(state.value.bandGains);
      if (stored.isEmpty) {
        // Populate state with the device's flat band list so custom edits work.
        stored = List<double>.filled(params.bands.length, 0.0);
        state.value = state.value.copyWith(bandGains: stored);
        return;
      }
      // If the stored curve length does not match the real band count,
      // remap it like a normalized preset curve.
      var applied = stored;
      if (stored.length != params.bands.length) {
        applied = await _mapCurveToBands(stored);
        if (applied.isEmpty) return;
        state.value = state.value.copyWith(bandGains: applied);
      }
      for (var i = 0; i < applied.length && i < params.bands.length; i++) {
        try {
          await params.bands[i].setGain(applied[i].clamp(params.minDecibels, params.maxDecibels));
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      _eqBandApplyQueued = false;
    }
  }

  Future<void> _applyAll() async {
    if (!isSupported) return;
    final s = state.value;
    try {
      await loudnessEnhancer.setEnabled(s.enabled && s.loudnessDb > 0);
      await equalizer.setEnabled(s.enabled);
      unawaited(_applyBandGainsWhenReady());
    } catch (e) {
      AppLogger.w('[AudioEnhancer] apply just_audio effects failed', e);
    }
    await _applyLoudness();
    await _applyBass();
    await _applySurround();
    await _applyCompressor();
  }

  Future<void> _applyLoudness() async {
    if (!isSupported) return;
    final s = state.value;
    try {
      final total = s.loudnessDb + _trackGainDb;
      await loudnessEnhancer.setEnabled(s.enabled || _trackGainDb != 0);
      await loudnessEnhancer.setTargetGain(total);
    } catch (e) {
      AppLogger.w('[AudioEnhancer] loudness failed', e);
    }
  }

  Future<void> _applyBass() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('setBass', {
        'enabled': state.value.enabled && state.value.bass > 0,
        'strength': (state.value.bass * 1000).round(),
      });
    } catch (e) {
      AppLogger.w('[AudioEnhancer] bass fx failed', e);
    }
  }

  Future<void> _applySurround() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('setSurround', {
        'enabled': state.value.enabled && state.value.surround > 0,
        'strength': (state.value.surround * 1000).round(),
      });
    } catch (e) {
      AppLogger.w('[AudioEnhancer] surround fx failed', e);
    }
  }

  Future<void> _applyCompressor() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('setCompressor', {
        'enabled': state.value.enabled && state.value.compressor > 0,
        'amount': state.value.compressor,
      });
    } catch (e) {
      AppLogger.w('[AudioEnhancer] compressor fx failed', e);
    }
  }

  // ---------------------------------------------------------------------------
  // Per-track loudness normalization (Spotify-style, works on all platforms)
  // ---------------------------------------------------------------------------

  /// Loudness normalization target, same as Spotify's.
  static const double _targetLufs = -14.0;

  /// Reset normalization when a new track starts resolving.
  void resetTrackGain() {
    if (_trackGainDb == 0) return;
    _trackGainDb = 0;
    unawaited(_applyNormalization());
  }

  /// Scans a `muse_request_source` payload for loudness metadata and applies
  /// the normalization gain. Expected fields (any of):
  /// `loudness: {lufs, peak_db}`, flat `lufs`/`loudness_lufs`, or
  /// `replaygain_db`/`track_gain` (already a gain, used as-is).
  void scanLoudness(Map<String, dynamic> payload) {
    double? lufs;
    double? peakDb;
    double? directGain;

    void scan(Object? node) {
      if (node is Map) {
        for (final e in node.entries) {
          final k = e.key.toString().toLowerCase();
          final v = e.value;
          if (v is num) {
            if (k == 'lufs' || k == 'i_lufs' || k == 'loudness_lufs' || k == 'integrated_loudness') {
              lufs ??= v.toDouble();
            } else if (k == 'peak_db' || k == 'true_peak_db' || k == 'true_peak' || k == 'peak') {
              peakDb ??= v.toDouble();
            } else if (k == 'replaygain_db' || k == 'replay_gain' || k == 'track_gain' || k == 'gain_db') {
              directGain ??= v.toDouble();
            }
          } else if (v is Map || v is List) {
            scan(v);
          }
        }
      } else if (node is List) {
        for (final v in node) {
          scan(v);
        }
      }
    }

    scan(payload);

    final lufsVal = lufs;
    final peakVal = peakDb;
    var gain = directGain ?? (lufsVal != null ? _targetLufs - lufsVal : 0.0);
    if (peakVal != null) {
      // Never let the normalized peak clip above -1 dBTP.
      gain = gain < (-1.0 - peakVal) ? gain : (-1.0 - peakVal);
    }
    gain = gain.clamp(-20.0, 15.0);

    if ((gain - _trackGainDb).abs() < 0.05) return;
    _trackGainDb = gain;
    AppLogger.d('[AudioEnhancer] track loudness: lufs=$lufs peak=$peakDb gain=${gain.toStringAsFixed(2)}dB');
    unawaited(_applyNormalization());
  }

  Future<void> _applyNormalization() async {
    if (isSupported) {
      // Android: fold track gain into the loudness enhancer's target gain so
      // quiet tracks get boosted and loud tracks get attenuated.
      await _applyLoudness();
    } else {
      // iOS/other: volume-only fallback (attenuation only, boost would clip).
      final player = _player;
      if (player == null) return;
      try {
        final v = _trackGainDb >= 0 ? 1.0 : math.pow(10.0, _trackGainDb / 20.0).toDouble();
        await player.setVolume(v.clamp(0.0, 1.0));
      } catch (_) {}
    }
  }

  Future<void> _attachNative(int sessionId) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('attach', {'sessionId': sessionId});
      await _applyBass();
      await _applySurround();
      await _applyCompressor();
    } catch (e) {
      AppLogger.w('[AudioEnhancer] native attach failed', e);
    }
  }

  Future<void> dispose() async {
    await _sessionSub?.cancel();
    try {
      await _channel.invokeMethod('release');
    } catch (_) {}
    state.dispose();
  }
}
