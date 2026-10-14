import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/poi.dart';

/// Quản lý SQLite trong điện thoại (bản sao offline của dữ liệu POI).
class PoiDatabase {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'narration.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE poi (
        id         INTEGER PRIMARY KEY,
        lat        REAL NOT NULL,
        lng        REAL NOT NULL,
        radius_m   INTEGER NOT NULL DEFAULT 50,
        priority   INTEGER NOT NULL DEFAULT 0,
        image_url  TEXT,
        map_url    TEXT,
        is_active  INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE poi_translation (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        poi_id      INTEGER NOT NULL REFERENCES poi(id) ON DELETE CASCADE,
        lang        TEXT NOT NULL,
        name        TEXT NOT NULL,
        description TEXT,
        tts_script  TEXT,
        audio_url   TEXT,
        UNIQUE (poi_id, lang)
      )
    ''');
    await _createPlayLog(db);
    await _seedSamples(db);
  }

  /// v1 -> v2: thêm bảng play_log mà không mất dữ liệu cũ.
  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createPlayLog(db);
    }
  }

  static Future<void> _createPlayLog(Database db) async {
    await db.execute('''
      CREATE TABLE play_log (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        poi_id       INTEGER NOT NULL,
        lang         TEXT NOT NULL,
        source       TEXT NOT NULL,          -- 'audio' hoặc 'tts'
        trigger      TEXT NOT NULL,          -- 'gps' hoặc 'qr'
        played_at    TEXT NOT NULL,          -- ISO-8601
        duration_sec INTEGER,                -- thời gian nghe thực tế
        completed    INTEGER NOT NULL DEFAULT 0,
        synced       INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_play_log_poi_time ON play_log (poi_id, played_at)');
  }

  // DỮ LIỆU MẪU: tọa độ gần đúng, chỉ để thử. Sẽ thay bằng tọa độ thật.
  static const _samples = [
    {
      'id': 1, 'lat': 10.7683, 'lng': 106.7066, 'radius': 60, 'priority': 3,
      'vi': 'Điểm mẫu 1 (Khánh Hội)', 'en': 'Sample stop 1 (Khanh Hoi)',
    },
    {
      'id': 2, 'lat': 10.7630, 'lng': 106.7040, 'radius': 50, 'priority': 2,
      'vi': 'Điểm mẫu 2 (Khánh Hội)', 'en': 'Sample stop 2 (Khanh Hoi)',
    },
    {
      'id': 3, 'lat': 10.7590, 'lng': 106.7080, 'radius': 50, 'priority': 1,
      'vi': 'Điểm mẫu 3 (Vĩnh Hội)', 'en': 'Sample stop 3 (Vinh Hoi)',
    },
    {
      'id': 4, 'lat': 10.7560, 'lng': 106.7120, 'radius': 40, 'priority': 1,
      'vi': 'Điểm mẫu 4 (Xóm Chiếu)', 'en': 'Sample stop 4 (Xom Chieu)',
    },
  ];

  static Future<void> _seedSamples(Database db) async {
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final s in _samples) {
      batch.insert('poi', {
        'id': s['id'],
        'lat': s['lat'],
        'lng': s['lng'],
        'radius_m': s['radius'],
        'priority': s['priority'],
        'updated_at': now,
      });
      for (final lang in ['vi', 'en']) {
        batch.insert('poi_translation', {
          'poi_id': s['id'],
          'lang': lang,
          'name': s[lang],
          'description': 'Mô tả của ${s[lang]}',
          'tts_script': 'Đây là nội dung thuyết minh của ${s[lang]}',
        });
      }
    }
    await batch.commit(noResult: true);
  }

  /// Lấy tất cả POI đang bật, kèm nội dung theo ngôn ngữ [lang].
  static Future<List<Poi>> getAll(String lang) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.id, p.lat, p.lng, p.radius_m, p.priority,
             t.name, t.description, t.tts_script, t.audio_url
      FROM poi p
      JOIN poi_translation t ON t.poi_id = p.id
      WHERE p.is_active = 1 AND t.lang = ?
      ORDER BY p.priority DESC
    ''', [lang]);
    return rows.map(Poi.fromMap).toList();
  }

  // ---------------------------------------------------------------
  // play_log
  // ---------------------------------------------------------------

  /// Ghi một lượt phát. Trả về id của dòng log (để cập nhật thời lượng sau).
  static Future<int> insertPlayLog({
    required int poiId,
    required String lang,
    required String source, // 'audio' | 'tts'
    required String trigger, // 'gps' | 'qr'
    DateTime? playedAt,
  }) async {
    final db = await database;
    return db.insert('play_log', {
      'poi_id': poiId,
      'lang': lang,
      'source': source,
      'trigger': trigger,
      'played_at': (playedAt ?? DateTime.now()).toIso8601String(),
    });
  }

  /// Cập nhật khi phát xong hoặc bị ngắt: nghe được bao nhiêu giây.
  static Future<void> finishPlayLog(
    int logId, {
    required int durationSec,
    required bool completed,
  }) async {
    final db = await database;
    await db.update(
      'play_log',
      {'duration_sec': durationSec, 'completed': completed ? 1 : 0},
      where: 'id = ?',
      whereArgs: [logId],
    );
  }

  /// Lần gần nhất POI này được phát (null nếu chưa từng).
  /// Dùng để kiểm tra "đã phát trong X phút chưa?".
  static Future<DateTime?> lastPlayedAt(int poiId) async {
    final db = await database;
    final rows = await db.query(
      'play_log',
      columns: ['played_at'],
      where: 'poi_id = ?',
      whereArgs: [poiId],
      orderBy: 'played_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.parse(rows.first['played_at'] as String);
  }
}