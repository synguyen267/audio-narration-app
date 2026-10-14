import '../models/poi.dart';
import 'geo_utils.dart';

/// Một POI kèm khoảng cách (mét) từ vị trí hiện tại tới POI đó.
class PoiMatch {
  final Poi poi;
  final double distanceM;

  const PoiMatch(this.poi, this.distanceM);
}

/// Geofence Engine: xác định POI nào đang "trong vùng" và POI nào nên được
/// thuyết minh. Lớp này thuần logic (không đụng GPS, SQLite hay âm thanh)
/// nên rất dễ viết unit test.
class GeofenceEngine {
  const GeofenceEngine();

  /// Tất cả POI mà vị trí ([lat], [lng]) nằm trong bán kính của chính POI đó.
  /// Sắp xếp: priority cao trước; cùng priority thì POI gần hơn trước.
  List<PoiMatch> poisInRange(List<Poi> pois, double lat, double lng) {
    final matches = <PoiMatch>[];
    for (final poi in pois) {
      final d = distanceMeters(lat, lng, poi.lat, poi.lng);
      if (d <= poi.radiusM) {
        matches.add(PoiMatch(poi, d));
      }
    }
    matches.sort((a, b) {
      final byPriority = b.poi.priority.compareTo(a.poi.priority);
      if (byPriority != 0) return byPriority;
      return a.distanceM.compareTo(b.distanceM);
    });
    return matches;
  }

  /// POI nên thuyết minh lúc này: ưu tiên cao nhất trong vùng, cùng ưu tiên
  /// thì chọn POI gần nhất. Trả về null nếu không có POI nào trong vùng.
  PoiMatch? pickTarget(List<Poi> pois, double lat, double lng) {
    final inRange = poisInRange(pois, lat, lng);
    return inRange.isEmpty ? null : inRange.first;
  }

  /// POI gần nhất bất kể có nằm trong bán kính hay không
  /// (dùng để highlight trên bản đồ ở Giai đoạn 4). Null nếu danh sách rỗng.
  PoiMatch? nearest(List<Poi> pois, double lat, double lng) {
    PoiMatch? best;
    for (final poi in pois) {
      final d = distanceMeters(lat, lng, poi.lat, poi.lng);
      if (best == null || d < best.distanceM) {
        best = PoiMatch(poi, d);
      }
    }
    return best;
  }
}
