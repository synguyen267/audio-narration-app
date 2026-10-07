/// Một điểm quan tâm (POI) kèm nội dung thuyết minh theo 1 ngôn ngữ.
class Poi {
  final int id;
  final double lat;
  final double lng;
  final int radiusM; // bán kính geofence (mét)
  final int priority; // số càng lớn càng ưu tiên
  final String name;
  final String? description;
  final String? ttsScript; // dùng khi không có file audio
  final String? audioUrl; // có thì phát audio, không có thì đọc ttsScript

  const Poi({
    required this.id,
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.priority,
    required this.name,
    this.description,
    this.ttsScript,
    this.audioUrl,
  });

  /// Tạo Poi từ một dòng kết quả của SQLite.
  factory Poi.fromMap(Map<String, Object?> m) => Poi(
        id: m['id'] as int,
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        radiusM: m['radius_m'] as int,
        priority: m['priority'] as int,
        name: m['name'] as String,
        description: m['description'] as String?,
        ttsScript: m['tts_script'] as String?,
        audioUrl: m['audio_url'] as String?,
      );
}
