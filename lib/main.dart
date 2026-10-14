import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'data/poi_database.dart';
import 'data/poi_database_play_log.dart';
import 'models/poi.dart';
import 'services/device_narration_player.dart';
import 'services/geo_utils.dart';
import 'services/geofence_engine.dart';
import 'services/location_service.dart';
import 'services/narration_engine.dart';
import 'ui/location_banner.dart';

void main() {
  runApp(const NarrationApp());
}

class NarrationApp extends StatelessWidget {
  const NarrationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Narration',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const PoiListScreen(),
    );
  }
}

class PoiListScreen extends StatefulWidget {
  const PoiListScreen({super.key});

  @override
  State<PoiListScreen> createState() => _PoiListScreenState();
}

class _PoiListScreenState extends State<PoiListScreen> {
  final _locationService = LocationService();
  final _geofence = const GeofenceEngine();
  final _narration = NarrationEngine(
    player: DeviceNarrationPlayer(),
    log: const PoiDatabasePlayLog(),
    lang: 'vi', // tạm thời cố định tiếng Việt
  );

  late final Future<List<Poi>> _pois;
  List<Poi> _poiList = []; // bản sao để Geofence Engine dùng
  StreamSubscription<Position>? _sub;
  LocationStatus? _status;
  Position? _position;

  /// Khi khác null: đang giả lập có mặt tại POI này (để thử không cần đi).
  Poi? _simulatedAt;

  @override
  void initState() {
    super.initState();
    _pois = PoiDatabase.getAll('vi').then((list) {
      _poiList = list;
      return list;
    });
    _startLocation();
  }

  Future<void> _startLocation() async {
    final status = await _locationService.checkAndRequest();
    if (!mounted) return;
    setState(() => _status = status);
    if (status == LocationStatus.ok) {
      _sub?.cancel();
      _sub = _locationService.positionStream().listen((p) {
        if (!mounted) return;
        setState(() => _position = p);
        // Đang giả lập thì bỏ qua GPS thật.
        if (_simulatedAt == null) _checkGeofence(p.latitude, p.longitude);
      });
    }
  }

  /// Mỗi khi có vị trí mới: Geofence chọn POI, Narration Engine lo việc đọc.
  Future<void> _checkGeofence(double lat, double lng) async {
    final target = _geofence.pickTarget(_poiList, lat, lng);
    if (target == null) return;
    final accepted = await _narration.request(target.poi);
    if (accepted && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Đang thuyết minh: ${target.poi.name}')),
        );
    }
  }

  void _simulateAt(Poi poi) {
    setState(() => _simulatedAt = poi);
    _checkGeofence(poi.lat, poi.lng);
  }

  void _stopSimulation() => setState(() => _simulatedAt = null);

  /// Vị trí đang dùng để tính khoảng cách: giả lập nếu có, không thì GPS thật.
  ({double lat, double lng})? get _currentPoint {
    final sim = _simulatedAt;
    if (sim != null) return (lat: sim.lat, lng: sim.lng);
    final p = _position;
    if (p != null) return (lat: p.latitude, lng: p.longitude);
    return null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _narration.stop();
    super.dispose();
  }

  String _formatDistance(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh sách điểm thuyết minh'),
        actions: [
          IconButton(
            tooltip: 'Dừng thuyết minh',
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: _narration.stop,
          ),
        ],
      ),
      body: Column(
        children: [
          LocationBanner(
            status: _status,
            position: _position,
            onRetry: _startLocation,
          ),
          if (_simulatedAt != null)
            Container(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Đang giả lập vị trí tại: ${_simulatedAt!.name}'),
                  ),
                  TextButton(
                    onPressed: _stopSimulation,
                    child: const Text('Tắt'),
                  ),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'Mẹo: giữ lâu một điểm để giả lập có mặt tại đó.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<Poi>>(
              future: _pois,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Lỗi: ${snapshot.error}'));
                }
                final point = _currentPoint;
                final items = (snapshot.data ?? [])
                    .map((p) => (
                          poi: p,
                          distance: point == null
                              ? null
                              : distanceMeters(
                                  point.lat, point.lng, p.lat, p.lng),
                        ))
                    .toList();
                if (point != null) {
                  items.sort((a, b) => a.distance!.compareTo(b.distance!));
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final poi = items[i].poi;
                    final d = items[i].distance;
                    return ListTile(
                      leading: CircleAvatar(child: Text('${poi.priority}')),
                      title: Text(poi.name),
                      subtitle: Text(
                        '${poi.lat}, ${poi.lng}  •  bán kính ${poi.radiusM} m',
                      ),
                      trailing: d == null
                          ? null
                          : Text(
                              _formatDistance(d),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                      onLongPress: () => _simulateAt(poi),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}