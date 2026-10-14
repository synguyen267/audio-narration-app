import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'narration_engine.dart';

/// Bộ phát thật trên điện thoại: flutter_tts cho giọng đọc,
/// audioplayers cho file audio.
class DeviceNarrationPlayer implements NarrationPlayer {
  DeviceNarrationPlayer() {
    _tts.setCompletionHandler(() => _complete(_speaking));
    _tts.setCancelHandler(() => _complete(_speaking));
    _tts.setErrorHandler((_) => _complete(_speaking));
    _audio.onPlayerComplete.listen((_) => _complete(_audioDone));
  }

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audio = AudioPlayer();
  Completer<void>? _speaking;
  Completer<void>? _audioDone;

  void _complete(Completer<void>? c) {
    if (c != null && !c.isCompleted) c.complete();
  }

  /// 'vi' -> 'vi-VN', 'en' -> 'en-US'...
  String _locale(String lang) {
    switch (lang) {
      case 'vi':
        return 'vi-VN';
      case 'en':
        return 'en-US';
      case 'zh':
        return 'zh-CN';
      case 'ja':
        return 'ja-JP';
      default:
        return lang;
    }
  }

  @override
  Future<void> speak(String text, String lang) async {
    _speaking = Completer<void>();
    await _tts.setLanguage(_locale(lang));
    await _tts.speak(text);
    await _speaking!.future; // xong khi đọc hết, bị hủy hoặc lỗi
  }

  @override
  Future<void> playAudio(String url) async {
    _audioDone = Completer<void>();
    await _audio.play(UrlSource(url));
    await _audioDone!.future; // xong khi phát hết hoặc bị stop()
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _complete(_speaking);
    await _audio.stop();
    _complete(_audioDone);
  }
}
