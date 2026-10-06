import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedRecording {
  final String id;
  final String path;
  final String title;
  final String mode;
  final DateTime createdAt;
  final int durationSeconds;

  const SavedRecording({
    required this.id,
    required this.path,
    required this.title,
    required this.mode,
    required this.createdAt,
    required this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'title': title,
        'mode': mode,
        'createdAt': createdAt.toIso8601String(),
        'durationSeconds': durationSeconds,
      };

  factory SavedRecording.fromJson(Map<String, dynamic> json) => SavedRecording(
        id: json['id'] as String,
        path: json['path'] as String,
        title: json['title'] as String? ?? '未命名录音',
        mode: json['mode'] as String? ?? '课堂',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      );
}

class StorageService {
  static const _key = 'saved_recordings_v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<SavedRecording>> loadRecordings() async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(_key) ?? [];
    final result = <SavedRecording>[];
    for (final item in raw) {
      try {
        result.add(SavedRecording.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {}
    }

    // 自动清理索引中的失效文件，避免列表出现“幽灵录音”。
    final existing = <SavedRecording>[];
    for (final r in result) {
      if (await File(r.path).exists()) existing.add(r);
    }
    if (existing.length != result.length) await _save(existing);

    // V3 早期版本没有录音索引：自动把历史 voice_*.m4a 纳入管理，方便用户删除旧文件。
    final knownPaths = existing.map((e) => e.path).toSet();
    final docs = await getApplicationDocumentsDirectory();
    if (await docs.exists()) {
      await for (final entity in docs.list(recursive: false, followLinks: false)) {
        if (entity is! File || knownPaths.contains(entity.path)) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (!name.startsWith('voice_') || !name.toLowerCase().endsWith('.m4a')) continue;
        final stat = await entity.stat();
        existing.add(SavedRecording(
          id: 'legacy_${stat.modified.microsecondsSinceEpoch}_${entity.hashCode}',
          path: entity.path,
          title: '历史录音 ${_formatDate(stat.modified)}',
          mode: '历史',
          createdAt: stat.modified,
          durationSeconds: 0,
        ));
      }
      await _save(existing);
    }
    return existing..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> addRecording(SavedRecording recording) async {
    final list = await loadRecordings();
    list.removeWhere((r) => r.id == recording.id || r.path == recording.path);
    list.insert(0, recording);
    await _save(list);
  }

  Future<void> deleteRecording(SavedRecording recording) async {
    try {
      final file = File(recording.path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    final list = await loadRecordings();
    list.removeWhere((r) => r.id == recording.id || r.path == recording.path);
    await _save(list);
  }

  Future<void> deleteRecordings(Iterable<SavedRecording> recordings) async {
    final paths = recordings.map((e) => e.path).toSet();
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    final list = await loadRecordings();
    list.removeWhere((r) => paths.contains(r.path));
    await _save(list);
  }

  /// 删除应用自己产生的临时文件，不碰已登记的正式录音。
  Future<CleanupResult> cleanupJunkFiles() async {
    final docs = await getApplicationDocumentsDirectory();
    final cache = await getTemporaryDirectory();
    final saved = (await loadRecordings()).map((e) => e.path).toSet();
    final files = <File>[];
    for (final dir in [docs, cache]) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last.toLowerCase();
        final isJunk = name.endsWith('.tmp') ||
            name.endsWith('.partial') ||
            name.endsWith('.part') ||
            name.startsWith('temp_') ||
            name.startsWith('stt_') ||
            name.startsWith('pcm_');
        if (isJunk && !saved.contains(entity.path)) files.add(entity);
      }
    }

    var bytes = 0;
    var count = 0;
    for (final file in files) {
      try {
        bytes += await file.length();
        await file.delete();
        count++;
      } catch (_) {}
    }
    return CleanupResult(count: count, bytes: bytes);
  }

  Future<StorageStats> stats() async {
    final recordings = await loadRecordings();
    var bytes = 0;
    for (final r in recordings) {
      try { bytes += await File(r.path).length(); } catch (_) {}
    }
    return StorageStats(recordingCount: recordings.length, recordingBytes: bytes);
  }

  Future<void> _save(List<SavedRecording> list) async {
    final prefs = await _prefs;
    await prefs.setStringList(_key, list.map((e) => jsonEncode(e.toJson())).toList());
  }
}

String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class CleanupResult {
  final int count;
  final int bytes;
  const CleanupResult({required this.count, required this.bytes});
}

class StorageStats {
  final int recordingCount;
  final int recordingBytes;
  const StorageStats({required this.recordingCount, required this.recordingBytes});
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
