import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

class LocationBanner extends StatelessWidget {
  final LocationStatus? status;
  final Position? position;
  final VoidCallback onRetry;

  const LocationBanner({
    super.key,
    required this.status,
    required this.position,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case null:
        return const ListTile(title: Text('Đang kiểm tra vị trí...'));
      case LocationStatus.ok:
        final p = position;
        return ListTile(
          leading: const Icon(Icons.my_location),
          title: Text(p == null
              ? 'Đang lấy vị trí...'
              : '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'),
        );
      case LocationStatus.serviceDisabled:
        return ListTile(
          leading: const Icon(Icons.location_off),
          title: const Text('Dịch vụ vị trí đang tắt'),
          trailing: TextButton(
            onPressed: () async {
              await Geolocator.openLocationSettings();
              onRetry();
            },
            child: const Text('Bật'),
          ),
        );
      case LocationStatus.denied:
        return ListTile(
          leading: const Icon(Icons.location_disabled),
          title: const Text('Cần quyền vị trí để dùng thuyết minh'),
          trailing: TextButton(onPressed: onRetry, child: const Text('Thử lại')),
        );
      case LocationStatus.deniedForever:
        return ListTile(
          leading: const Icon(Icons.location_disabled),
          title: const Text('Quyền vị trí bị chặn'),
          trailing: TextButton(
            onPressed: Geolocator.openAppSettings,
            child: const Text('Mở cài đặt'),
          ),
        );
    }
  }
}