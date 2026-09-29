import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/app_logger.dart';
import '../player/models/track.dart';

/// A track stored on the device for offline playback.
class DownloadedTrack {
  final String id;
  final String title;
  final String? subtitle;
  final String? coverUrl;
  final String? objectType;
  final String? objectHash;
  final String filePath;
  final int bytes;
  final DateTime downloadedAt;

  const DownloadedTrack({
    required this.id,
    required this.title,
    required this.filePath,
    required this.downloadedAt,
    this.subtitle,
    this.coverUrl,
    this.objectType,
    this.objectHash,
    this.bytes = 0,
    this.aiPct = 0,
  });

  final int aiPct;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'coverUrl': coverUrl,
        'objectType': objectType,
        'objectHash': objectHash,
        'filePath': filePath,
        'bytes': bytes,
        'aiPct': aiPct,
        'downloadedAt': downloadedAt.millisecondsSinceEpoch,
      };

  factory DownloadedTrack.fromJson(Map<String, dynamic> json) => DownloadedTrack(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        subtitle: json['subtitle']?.toString(),
        coverUrl: json['coverUrl']?.toString(),
        objectType: json['objectType']?.toString(),
        objectHash: json['objectHash']?.toString(),
        filePath: json['filePath']?.toString() ?? '',
        bytes: json['bytes'] is int ? json['bytes'] as int : int.tryParse('${json['bytes']}') ?? 0,
        aiPct: json['aiPct'] is int ? json['aiPct'] as int : int.tryParse('${json['aiPct'] ?? json['ai_pct']}') ?? 0,
        downloadedAt: DateTime.fromMillisecondsSinceEpoch(
          json['downloadedAt'] is int ? json['downloadedAt'] as int : int.tryParse('${json['downloadedAt']}') ?? 0,
        ),
      );

  Track toTrack() => Track(
        id: id,
        title: title,
        subtitle: subtitle,
        coverUrl: coverUrl,
        objectType: objectType,
        objectHash: objectHash,
        url: Uri.file(filePath).toString(),
        sourceType: 'audio',
        aiPct: aiPct,
      );
}

/// Manages on-device audio downloads for offline playback.
class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  static const String _indexKey = 'downloads_index_v1';

  Map<String, DownloadedTrack> _items = {};
  bool _loaded = false;

  final _itemsController = StreamController<List<DownloadedTrack>>.broadcast();
  Stream<List<DownloadedTrack>> get itemsStream => _itemsController.stream;

  /// Per-track download progress (0..1). Emits only while downloading.
  final Map<String, StreamController<double>> _progressControllers = {};
  final Set<String> _active = {};

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = json.decode(raw) as List;
      _items = {
        for (final e in list.whereType<Map>())
          (e['id']?.toString() ?? ''): DownloadedTrack.fromJson(Map<String, dynamic>.from(e)),
      }..removeWhere((k, v) => k.isEmpty);
      // Drop entries whose file no longer exists.
      final missing = <String>[];
      for (final entry in _items.entries) {
        if (!File(entry.value.filePath).existsSync()) missing.add(entry.key);
      }
      for (final k in missing) {
        _items.remove(k);
      }
      if (missing.isNotEmpty) await _persist();
    } catch (_) {
      _items = {};
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexKey, json.encode(_items.values.map((e) => e.toJson()).toList()));
    _itemsController.add(_items.values.toList()..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt)));
  }

  Future<Directory> _downloadDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final dl = Directory('${dir.path}${Platform.pathSeparator}downloads');
    if (!dl.existsSync()) await dl.create(recursive: true);
    return dl;
  }

  String _keyFor(Track t) =>
      (t.objectHash != null && t.objectHash!.isNotEmpty) ? '${t.objectType ?? 'm_track'}:${t.objectHash}' : t.id;

  String _extFromUrl(String url) {
    final clean = url.split('?').first.split('#').first.toLowerCase();
    final m = RegExp(r'\.(mp3|m4a|aac|ogg|opus|flac|wav)$').firstMatch(clean);
    return m?.group(1) ?? 'm4a';
  }

  bool isDownloading(Track t) => _active.contains(_keyFor(t));

  Stream<double> progressStreamFor(Track t) {
    final key = _keyFor(t);
    return _progressControllers.putIfAbsent(key, () => StreamController<double>.broadcast()).stream;
  }

  Future<bool> isDownloaded(Track t) async {
    await _ensureLoaded();
    final item = _items[_keyFor(t)];
    if (item == null) return false;
    if (!File(item.filePath).existsSync()) {
      _items.remove(_keyFor(t));
      await _persist();
      return false;
    }
    return true;
  }

  /// Returns a `file://` URL when the track is stored locally.
  Future<String?> localFileUrl(String objectType, String objectHash) async {
    await _ensureLoaded();
    final item = _items['$objectType:$objectHash'];
    if (item == null || !File(item.filePath).existsSync()) return null;
    return Uri.file(item.filePath).toString();
  }

  Future<List<DownloadedTrack>> list() async {
    await _ensureLoaded();
    return _items.values.toList()..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
  }

  /// Download [resolvedUrl] for [track]. The caller is responsible for
  /// resolving the playable URL (see PlayerService.resolveUrlFor) and for
  /// rejecting HLS streams (m3u8), which cannot be stored as a single file.
  Future<void> download(Track track, String resolvedUrl) async {
    await _ensureLoaded();
    final key = _keyFor(track);
    if (_active.contains(key)) return;
    if (await isDownloaded(track)) return;

    _active.add(key);
    final progress = _progressControllers.putIfAbsent(key, () => StreamController<double>.broadcast());

    try {
      final dir = await _downloadDir();
      final ext = _extFromUrl(resolvedUrl);
      final safeName = key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file = File('${dir.path}${Platform.pathSeparator}$safeName.$ext');

      final req = http.Request('GET', Uri.parse(resolvedUrl));
      final res = await http.Client().send(req);
      if (res.statusCode != 200) {
        throw Exception('Download failed (HTTP ${res.statusCode})');
      }

      final total = res.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.add(received / total);
      }
      await sink.flush();
      await sink.close();

      _items[key] = DownloadedTrack(
        id: key,
        title: track.title,
        subtitle: track.subtitle,
        coverUrl: track.coverUrl,
        objectType: track.objectType,
        objectHash: track.objectHash,
        filePath: file.path,
        bytes: received,
        aiPct: track.aiPct,
        downloadedAt: DateTime.now(),
      );
      await _persist();
    } finally {
      _active.remove(key);
      await _progressControllers.remove(key)?.close();
    }
  }

  Future<void> remove(Track track) async {
    await _ensureLoaded();
    final key = _keyFor(track);
    final item = _items.remove(key);
    if (item != null) {
      try {
        final f = File(item.filePath);
        if (f.existsSync()) await f.delete();
      } catch (e) {
        AppLogger.d('[DownloadService] delete failed: $e');
      }
      await _persist();
    }
  }

  Future<void> clearAll() async {
    await _ensureLoaded();
    for (final item in _items.values) {
      try {
        final f = File(item.filePath);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    _items.clear();
    await _persist();
  }

  Future<int> totalBytes() async {
    await _ensureLoaded();
    return _items.values.fold<int>(0, (sum, e) => sum + e.bytes);
  }
}
