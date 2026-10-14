import 'dart:collection';

import '../models/poi.dart';

/// Cách phát một lượt thuyết minh.
enum NarrationSource { audio, tts }

/// Thành phần thực sự phát âm thanh. Tách thành interface để engine
/// không phụ thuộc vào flutter_tts / audioplayers (và test được bằng đồ giả).
///
/// Quy ước: [playAudio] và [speak] chỉ hoàn thành khi phát XONG hoặc khi bị
/// [stop] cắt ngang.
abstract class NarrationPlayer {
  Future<void> playAudio(String url);
  Future<void> speak(String text, String lang);
  Future<void> stop();
}

/// Nơi ghi và tra nhật ký phát (bảng play_log).
abstract class PlayLogStore {
  Future<int> insert({
    required int poiId,
    required String lang,
    required String source, // 'audio' | 'tts'
    required String trigger, // 'gps' | 'qr'
    required DateTime playedAt,
  });

  Future<void> finish(
    int logId, {
    required int durationSec,
    required bool completed,
  });

  Future<DateTime?> lastPlayedAt(int poiId);
}

class _Job {
  final Poi poi;
  final String trigger;
  const _Job(this.poi, this.trigger);
}

/// Narration Engine: nhận yêu cầu "hãy thuyết minh POI này" rồi lo phần còn
/// lại: chọn audio hay TTS, xếp hàng chờ, không phát trùng, dừng khi có
/// thông báo khác, và ghi play_log.
class NarrationEngine {
  NarrationEngine({
    required this.player,
    required this.log,
    this.lang = 'vi',
    this.cooldown = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final NarrationPlayer player;
  final PlayLogStore log;

  /// Ngôn ngữ đọc (đổi được từ màn cài đặt).
  String lang;

  /// Một POI vừa phát trong khoảng này thì không phát lại (X phút).
  final Duration cooldown;

  final DateTime Function() _now;

  final Queue<_Job> _queue = Queue<_Job>();
  int? _currentPoiId;
  bool _interrupted = false;
  Future<void>? _worker;

  /// Đang phát một POI nào đó không?
  bool get isPlaying => _currentPoiId != null;

  /// Số POI đang xếp hàng chờ (không tính cái đang phát).
  int get queueLength => _queue.length;

  /// Hoàn thành khi hàng chờ đã phát hết. Chủ yếu để test dùng.
  Future<void> get idle => _worker ?? Future<void>.value();

  /// POI này sẽ phát bằng cách nào? Có audio_url thì audio, không thì TTS,
  /// không có gì để phát thì null.
  static NarrationSource? sourceFor(Poi poi) {
    final audio = poi.audioUrl?.trim() ?? '';
    if (audio.isNotEmpty) return NarrationSource.audio;
    final script = poi.ttsScript?.trim() ?? '';
    if (script.isNotEmpty) return NarrationSource.tts;
    return null;
  }

  bool _isBusyWith(int poiId) =>
      _currentPoiId == poiId || _queue.any((j) => j.poi.id == poiId);

  /// Yêu cầu thuyết minh một POI (thường do GPS kích hoạt).
  /// Trả về true nếu được nhận (đang phát hoặc đã vào hàng chờ),
  /// false nếu bị bỏ qua: không có nội dung, đang phát/đang chờ rồi,
  /// hoặc vừa phát trong khoảng [cooldown].
  Future<bool> request(Poi poi, {String trigger = 'gps'}) async {
    if (sourceFor(poi) == null) return false;
    if (_isBusyWith(poi.id)) return false;

    final last = await log.lastPlayedAt(poi.id);
    if (last != null && _now().difference(last) < cooldown) return false;

    // Trong lúc chờ truy vấn, có thể POI này đã được yêu cầu bởi nơi khác.
    if (_isBusyWith(poi.id)) return false;

    _queue.add(_Job(poi, trigger));
    _startWorker();
    return true;
  }

  /// Phát ngay (thường do quét QR): cắt bài đang đọc, xóa hàng chờ và
  /// bỏ qua kiểm tra cooldown, vì người dùng chủ động yêu cầu.
  Future<void> playNow(Poi poi, {String trigger = 'qr'}) async {
    if (sourceFor(poi) == null) return;
    if (_currentPoiId == poi.id) return; // đang đọc đúng POI này rồi

    _queue
      ..clear()
      ..addFirst(_Job(poi, trigger));

    if (isPlaying) {
      _interrupted = true;
      await player.stop(); // vòng lặp sẽ tự chuyển sang job vừa thêm
    } else {
      _startWorker();
    }
  }

  /// Dừng hẳn: bỏ hàng chờ và cắt bài đang đọc.
  Future<void> stop() async {
    _queue.clear();
    if (isPlaying) {
      _interrupted = true;
      await player.stop();
    }
  }

  void _startWorker() {
    _worker ??= _run().whenComplete(() => _worker = null);
  }

  Future<void> _run() async {
    while (_queue.isNotEmpty) {
      await _play(_queue.removeFirst());
    }
  }

  Future<void> _play(_Job job) async {
    final poi = job.poi;
    final source = sourceFor(poi)!;
    _currentPoiId = poi.id;
    _interrupted = false;

    int? logId;
    var completed = false;
    final watch = Stopwatch()..start();
    try {
      // Ghi log TRƯỚC khi phát để các lần kiểm tra sau thấy POI này vừa phát.
      logId = await log.insert(
        poiId: poi.id,
        lang: lang,
        source: source.name,
        trigger: job.trigger,
        playedAt: _now(),
      );
      if (!_interrupted) {
        if (source == NarrationSource.audio) {
          await player.playAudio(poi.audioUrl!.trim());
        } else {
          await player.speak(poi.ttsScript!.trim(), lang);
        }
        completed = !_interrupted;
      }
    } catch (_) {
      completed = false; // lỗi phát (mất mạng, thiếu giọng đọc...): bỏ qua
    } finally {
      watch.stop();
      _currentPoiId = null;
      if (logId != null) {
        try {
          await log.finish(
            logId,
            durationSec: watch.elapsed.inSeconds,
            completed: completed,
          );
        } catch (_) {
          // Không để lỗi ghi log làm hỏng hàng chờ.
        }
      }
    }
  }
}
