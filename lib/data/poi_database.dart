import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/poi.dart';

/// Quản lý SQLite trong điện thoại (bản sao offline của dữ liệu POI).
class PoiDatabase {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'narration.db');
    _db = await openDatabase(path, version: 1, onCreate: _onCreate);
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
    await _seedSamples(db);
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
}
