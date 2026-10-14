import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:audio_narration_app/models/poi.dart';
import 'package:audio_narration_app/services/narration_engine.dart';

/// Bộ phát giả: ghi lại các lệnh, và chỉ "phát xong" khi test gọi finish().
class FakePlayer implements NarrationPlayer {
  final events = <String>[];
  Completer<void>? _current;
  Object? errorOnNext;

  Future<void> _start(String label) {
    events.add(label);
    final err = errorOnNext;
    if (err != null) {
      errorOnNext = null;
      return Future<void>.error(err);
    }
    _current = Completer<void>();
    return _current!.future;
  }

  @override
  Future<void> playAudio(String url) => _start('audio:$url');

  @override
  Future<void> speak(String text, String lang) => _start('tts:$text');

  @override
  Future<void> stop() async {
    events.add('stop');
    finish();
  }

  /// Giả lập: bài đang phát đã đọc xong.
  void finish() {
    final c = _current;
    if (c != null && !c.isCompleted) c.complete();
  }
}

/// Nhật ký giả lưu trong bộ nhớ.
class FakeLog implements PlayLogStore {
  final rows = <Map<String, Object?>>[];

  @override
  Future<int> insert({
    required int poiId,
    required String lang,
    required String source,
    required String trigger,
    required DateTime playedAt,
  }) async {
    rows.add({
      'poi_id': poiId,
      'lang': lang,
      'source': source,
      'trigger': trigger,
      'played_at': playedAt,
      'duration_sec': null,
      'completed': null,
    });
    return rows.length - 1; // id = vị trí trong danh sách
  }

  @override
  Future<void> finish(
    int logId, {
    required int durationSec,
    required bool completed,
  }) async {
    rows[logId]['duration_sec'] = durationSec;
    rows[logId]['completed'] = completed;
  }

  @override
  Future<DateTime?> lastPlayedAt(int poiId) async {
    DateTime? latest;
    for (final r in rows) {
      if (r['poi_id'] == poiId) latest = r['played_at'] as DateTime;
    }
    return latest;
  }
}

Poi makePoi(int id, {String? audioUrl, String? tts}) => Poi(
      id: id,
      lat: 10.76,
      lng: 106.70,
      radiusM: 50,
      priority: 1,
      name: 'POI $id',
      ttsScript: tts ?? 'Nội dung $id',
      audioUrl: audioUrl,
    );

void main() {
  late FakePlayer player;
  late FakeLog log;
  late DateTime clock;
  late NarrationEngine engine;

  setUp(() {
    player = FakePlayer();
    log = FakeLog();
    clock = DateTime(2026, 10, 14, 9, 0);
    engine = NarrationEngine(
      player: player,
      log: log,
      cooldown: const Duration(minutes: 10),
      now: () => clock,
    );
  });

  test('không có audio_url thì đọc bằng TTS và ghi log', () async {
    expect(await engine.request(makePoi(1)), isTrue);
    await pumpEventQueue();

    expect(player.events, ['tts:Nội dung 1']);
    expect(engine.isPlaying, isTrue);

    player.finish();
    await engine.idle;

    expect(engine.isPlaying, isFalse);
    expect(log.rows.single['source'], 'tts');
    expect(log.rows.single['trigger'], 'gps');
    expect(log.rows.single['completed'], isTrue);
  });

  test('có audio_url thì phát audio', () async {
    final poi = makePoi(1, audioUrl: 'https://x.test/1.mp3');
    await engine.request(poi);
    await pumpEventQueue();

    expect(player.events, ['audio:https://x.test/1.mp3']);
    player.finish();
    await engine.idle;
    expect(log.rows.single['source'], 'audio');
  });

  test('POI không có nội dung nào thì bị bỏ qua, không ghi log', () async {
    expect(await engine.request(makePoi(1, tts: '')), isFalse);
    await pumpEventQueue();

    expect(player.events, isEmpty);
    expect(log.rows, isEmpty);
  });

  test('yêu cầu trùng khi POI đang phát thì bị bỏ qua', () async {
    await engine.request(makePoi(1));
    await pumpEventQueue();

    expect(await engine.request(makePoi(1)), isFalse);
    expect(engine.queueLength, 0);
    player.finish();
    await engine.idle;
    expect(log.rows.length, 1);
  });

  test('vừa phát xong trong cooldown thì không phát lại, hết cooldown thì được',
      () async {
    await engine.request(makePoi(1));
    await pumpEventQueue();
    player.finish();
    await engine.idle;

    clock = clock.add(const Duration(minutes: 5));
    expect(await engine.request(makePoi(1)), isFalse);

    clock = clock.add(const Duration(minutes: 6)); // tổng 11 phút
    expect(await engine.request(makePoi(1)), isTrue);
    await pumpEventQueue();
    player.finish();
    await engine.idle;
    expect(log.rows.length, 2);
  });

  test('hàng chờ: POI thứ hai chỉ phát sau khi POI thứ nhất xong', () async {
    expect(await engine.request(makePoi(1)), isTrue);
    expect(await engine.request(makePoi(2)), isTrue);
    await pumpEventQueue();

    expect(player.events, ['tts:Nội dung 1']);
    expect(engine.queueLength, 1);

    player.finish();
    await pumpEventQueue();
    expect(player.events, ['tts:Nội dung 1', 'tts:Nội dung 2']);

    player.finish();
    await engine.idle;
    expect(log.rows.map((r) => r['poi_id']), [1, 2]);
  });

  test('playNow cắt bài đang đọc, xóa hàng chờ và ghi trigger qr', () async {
    await engine.request(makePoi(1));
    await engine.request(makePoi(2));
    await pumpEventQueue();

    await engine.playNow(makePoi(3));
    await pumpEventQueue();

    expect(player.events, ['tts:Nội dung 1', 'stop', 'tts:Nội dung 3']);

    player.finish();
    await engine.idle;

    expect(log.rows.length, 2); // POI 2 bị xóa khỏi hàng chờ, không phát
    expect(log.rows[0]['poi_id'], 1);
    expect(log.rows[0]['completed'], isFalse); // bị cắt ngang
    expect(log.rows[1]['poi_id'], 3);
    expect(log.rows[1]['trigger'], 'qr');
    expect(log.rows[1]['completed'], isTrue);
  });

  test('playNow bỏ qua cooldown', () async {
    await engine.request(makePoi(1));
    await pumpEventQueue();
    player.finish();
    await engine.idle;

    await engine.playNow(makePoi(1)); // vừa phát xong, vẫn phát lại
    await pumpEventQueue();
    expect(player.events.length, 2);
    player.finish();
    await engine.idle;
  });

  test('stop() dừng bài đang đọc và bỏ hàng chờ', () async {
    await engine.request(makePoi(1));
    await engine.request(makePoi(2));
    await pumpEventQueue();

    await engine.stop();
    await engine.idle;

    expect(player.events, ['tts:Nội dung 1', 'stop']);
    expect(log.rows.length, 1);
    expect(log.rows.single['completed'], isFalse);
    expect(engine.isPlaying, isFalse);
  });

  test('lỗi khi phát một POI thì ghi completed=false và chạy tiếp POI sau',
      () async {
    player.errorOnNext = Exception('mất mạng');
    await engine.request(makePoi(1));
    await engine.request(makePoi(2));
    await pumpEventQueue();

    expect(player.events, ['tts:Nội dung 1', 'tts:Nội dung 2']);
    expect(log.rows[0]['completed'], isFalse);

    player.finish();
    await engine.idle;
    expect(log.rows[1]['completed'], isTrue);
  });
}
