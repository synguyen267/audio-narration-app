import '../services/narration_engine.dart';
import 'poi_database.dart';

/// Nối Narration Engine với bảng play_log trong SQLite.
class PoiDatabasePlayLog implements PlayLogStore {
  const PoiDatabasePlayLog();

  @override
  Future<int> insert({
    required int poiId,
    required String lang,
    required String source,
    required String trigger,
    required DateTime playedAt,
  }) =>
      PoiDatabase.insertPlayLog(
        poiId: poiId,
        lang: lang,
        source: source,
        trigger: trigger,
        playedAt: playedAt,
      );

  @override
  Future<void> finish(
    int logId, {
    required int durationSec,
    required bool completed,
  }) =>
      PoiDatabase.finishPlayLog(
        logId,
        durationSec: durationSec,
        completed: completed,
      );

  @override
  Future<DateTime?> lastPlayedAt(int poiId) => PoiDatabase.lastPlayedAt(poiId);
}
