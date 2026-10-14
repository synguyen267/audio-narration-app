import 'package:flutter_test/flutter_test.dart';
import 'package:audio_narration_app/models/poi.dart';
import 'package:audio_narration_app/services/geofence_engine.dart';

// Vị trí người dùng giả lập. 0.0001 độ vĩ ≈ 11 m.
const userLat = 10.7600;
const userLng = 106.7000;

Poi makePoi(
  int id, {
  required double dLat, // lệch vĩ độ so với người dùng (độ)
  int radiusM = 50,
  int priority = 1,
}) =>
    Poi(
      id: id,
      lat: userLat + dLat,
      lng: userLng,
      radiusM: radiusM,
      priority: priority,
      name: 'POI $id',
    );

void main() {
  const engine = GeofenceEngine();

  group('poisInRange', () {
    test('chỉ trả về POI nằm trong bán kính', () {
      final near = makePoi(1, dLat: 0.0001); // ~11 m
      final far = makePoi(2, dLat: 0.01); // ~1112 m
      final result = engine.poisInRange([near, far], userLat, userLng);

      expect(result.map((m) => m.poi.id), [1]);
    });

    test('POI nằm ngoài bán kính của chính nó thì bị loại', () {
      // ~55.6 m, bán kính 50 -> ngoài; bán kính 60 -> trong.
      final outside = makePoi(1, dLat: 0.0005, radiusM: 50);
      final inside = makePoi(2, dLat: 0.0005, radiusM: 60);

      expect(engine.poisInRange([outside], userLat, userLng), isEmpty);
      expect(engine.poisInRange([inside], userLat, userLng).length, 1);
    });

    test('priority cao đứng trước dù POI ở xa hơn', () {
      final lowNear = makePoi(1, dLat: 0.0001, priority: 1);
      final highFar = makePoi(2, dLat: 0.0003, priority: 5);
      final result = engine.poisInRange([lowNear, highFar], userLat, userLng);

      expect(result.map((m) => m.poi.id), [2, 1]);
    });

    test('cùng priority thì POI gần hơn đứng trước', () {
      final farther = makePoi(1, dLat: 0.0003, priority: 2);
      final closer = makePoi(2, dLat: 0.0001, priority: 2);
      final result = engine.poisInRange([farther, closer], userLat, userLng);

      expect(result.map((m) => m.poi.id), [2, 1]);
    });

    test('danh sách rỗng trả về rỗng', () {
      expect(engine.poisInRange([], userLat, userLng), isEmpty);
    });
  });

  group('pickTarget', () {
    test('trả về null khi không có POI nào trong vùng', () {
      final far = makePoi(1, dLat: 0.01);
      expect(engine.pickTarget([far], userLat, userLng), isNull);
    });

    test('chọn POI ưu tiên cao nhất trong vùng', () {
      final a = makePoi(1, dLat: 0.0001, priority: 1);
      final b = makePoi(2, dLat: 0.0002, priority: 3);
      final c = makePoi(3, dLat: 0.01, priority: 9); // ngoài vùng, bỏ qua

      final target = engine.pickTarget([a, b, c], userLat, userLng);
      expect(target?.poi.id, 2);
    });

    test('khoảng cách trả về hợp lý (~11 m)', () {
      final a = makePoi(1, dLat: 0.0001);
      final target = engine.pickTarget([a], userLat, userLng);

      expect(target, isNotNull);
      expect(target!.distanceM, closeTo(11.1, 0.5));
    });
  });

  group('nearest', () {
    test('trả về POI gần nhất kể cả khi ngoài bán kính', () {
      final a = makePoi(1, dLat: 0.01);
      final b = makePoi(2, dLat: 0.005);

      expect(engine.nearest([a, b], userLat, userLng)?.poi.id, 2);
    });

    test('danh sách rỗng trả về null', () {
      expect(engine.nearest([], userLat, userLng), isNull);
    });
  });
}
