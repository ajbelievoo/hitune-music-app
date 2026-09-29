import 'package:flutter/material.dart';

import '../../core/network/api_service.dart';
import '../subscription/feature_gate.dart';
import '../subscription/subscription_service.dart';
import 'models/track.dart';

/// Full-screen lyrics view. Uses [Track.lyrics] when present, otherwise tries
/// the backend `track_lyrics` endpoint (see docs/BACKEND_REQUIREMENTS.md).
class LyricsScreen extends StatefulWidget {
  final Track track;

  const LyricsScreen({super.key, required this.track});

  static Future<void> open(BuildContext context, Track track) async {
    final ok = await FeatureGate.require(context, AppFeatures.lyrics, customTitle: 'Lyrics');
    if (!ok || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LyricsScreen(track: track)),
    );
  }

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  late Future<String?> _lyricsFuture;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = _loadLyrics();
  }

  Future<String?> _loadLyrics() async {
    final embedded = widget.track.lyrics;
    if (embedded != null && embedded.trim().isNotEmpty) {
      return _stripLrc(embedded);
    }

    final objectHash = widget.track.objectHash;
    if (objectHash == null || objectHash.isEmpty) return null;

    final res = await ApiService.instance.postPayloadRaw(
      endpoint: 'track_lyrics',
      data: {
        'object_type': widget.track.objectType ?? 'm_track',
        'object_hash': objectHash,
      },
    );
    if (!res.isSuccess || res.data == null) return null;

    final data = res.data!;
    final raw = (data['lyrics'] ?? data['text'] ?? data['lrc'])?.toString();
    if (raw == null || raw.trim().isEmpty) return null;
    return _stripLrc(raw);
  }

  /// Convert LRC-tagged lyrics into plain text for now.
  /// (Time-synced highlighting can be layered on top of the same data.)
  String _stripLrc(String input) {
    final lines = input.split(RegExp(r'\r?\n'));
    final out = <String>[];
    final lrcTag = RegExp(r'^\[\d{1,2}:\d{2}(\.\d{1,3})?\]\s*');
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) {
        out.add('');
        continue;
      }
      // Skip LRC metadata tags like [ti:], [ar:], [al:]
      if (RegExp(r'^\[[a-zA-Z]+:').hasMatch(line)) continue;
      out.add(line.replaceAll(lrcTag, ''));
    }
    return out.join('\n').trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = widget.track;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Lyrics'),
            if (track.subtitle != null && track.subtitle!.isNotEmpty)
              Text(
                track.subtitle!,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      body: FutureBuilder<String?>(
        future: _lyricsFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final lyrics = snap.data;
          if (lyrics == null || lyrics.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lyrics_outlined, size: 56, color: theme.iconTheme.color?.withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    Text(
                      'No lyrics available for this track yet',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
            child: Text(
              lyrics,
              style: theme.textTheme.titleLarge?.copyWith(height: 1.7, fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    );
  }
}
