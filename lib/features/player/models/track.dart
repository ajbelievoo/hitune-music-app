class Track {
  final String id;
  final String title;
  final String? subtitle;
  final String url;
  final String? coverUrl;

  final String? artistSlug;
  final String? artistLink;

  /// When present, PlayerService will resolve the playable URL via backend.
  /// Endpoint: muse_request_source (POST) with object_type + object_hash.
  final String? objectType;
  final String? objectHash;

  /// Source type from backend: 'audio' or 'video'
  final String? sourceType;

  /// Plain-text or LRC lyrics, when known.
  final String? lyrics;

  /// Duration in seconds when reported by the backend.
  final int? durationSeconds;

  /// Album title when reported by the backend.
  final String? albumTitle;

  /// Whether the track is marked explicit by the backend.
  final bool isExplicit;

  /// Percentage of AI generation declared for this track (0-100).
  /// Backend column `_c_m_tracks.ai_pct`; >0 shows the "AI Original" badge.
  final int aiPct;

  const Track({
    required this.id,
    required this.title,
    required this.url,
    this.subtitle,
    this.coverUrl,
    this.artistSlug,
    this.artistLink,
    this.objectType,
    this.objectHash,
    this.sourceType,
    this.lyrics,
    this.durationSeconds,
    this.albumTitle,
    this.isExplicit = false,
    this.aiPct = 0,
  });

  bool get isAiGenerated => aiPct > 0;

  /// Compact parser for the backend `ai_pct` field (may come as int/string).
  static int aiPctFromJson(Map<String, dynamic> json) {
    final v = json['ai_pct'] ?? json['aiPct'];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? 0}') ?? 0;
  }

  Track copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? url,
    String? coverUrl,
    String? artistSlug,
    String? artistLink,
    String? objectType,
    String? objectHash,
    String? sourceType,
    String? lyrics,
    int? durationSeconds,
    String? albumTitle,
    bool? isExplicit,
    int? aiPct,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      url: url ?? this.url,
      coverUrl: coverUrl ?? this.coverUrl,
      artistSlug: artistSlug ?? this.artistSlug,
      artistLink: artistLink ?? this.artistLink,
      objectType: objectType ?? this.objectType,
      objectHash: objectHash ?? this.objectHash,
      sourceType: sourceType ?? this.sourceType,
      lyrics: lyrics ?? this.lyrics,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      albumTitle: albumTitle ?? this.albumTitle,
      isExplicit: isExplicit ?? this.isExplicit,
      aiPct: aiPct ?? this.aiPct,
    );
  }
}
