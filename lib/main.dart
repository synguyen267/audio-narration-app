import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'data/poi_database.dart';
import 'models/poi.dart';
import 'services/geo_utils.dart';
import 'services/location_service.dart';
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
  late final Future<List<Poi>> _pois;
  StreamSubscription<Position>? _sub;
  LocationStatus? _status;
  Position? _position;

  @override
  void initState() {
    super.initState();
    _pois = PoiDatabase.getAll('vi'); // tạm thời cố định tiếng Việt
    _startLocation();
  }

  Future<void> _startLocation() async {
    final status = await _locationService.checkAndRequest();
    if (!mounted) return;
    setState(() => _status = status);
    if (status == LocationStatus.ok) {
      _sub?.cancel();
      _sub = _locationService.positionStream().listen((p) {
        if (mounted) setState(() => _position = p);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _formatDistance(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Danh sách điểm thuyết minh')),
      body: Column(
        children: [
          LocationBanner(
            status: _status,
            position: _position,
            onRetry: _startLocation,
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
                final pos = _position;
                final items = (snapshot.data ?? [])
                    .map((p) => (
                          poi: p,
                          distance: pos == null
                              ? null
                              : distanceMeters(
                                  pos.latitude, pos.longitude, p.lat, p.lng),
                        ))
                    .toList();
                if (pos != null) {
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