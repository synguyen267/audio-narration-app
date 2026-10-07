import 'package:geolocator/geolocator.dart';

enum LocationStatus { ok, serviceDisabled, denied, deniedForever }

class LocationService {
  /// Kiểm tra dịch vụ vị trí và xin quyền. Trả về đúng 1 trong 4 tình huống.
  Future<LocationStatus> checkAndRequest() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationStatus.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) return LocationStatus.denied;
    if (permission == LocationPermission.deniedForever) {
      return LocationStatus.deniedForever;
    }
    return LocationStatus.ok;
  }

  /// Luồng vị trí, tự cập nhật khi di chuyển (từ 5 m trở lên).
  Stream<Position> positionStream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      );
}