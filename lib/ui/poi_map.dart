import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/poi.dart';

/// Bản đồ hiện vị trí người dùng, các POI (kèm vòng tròn bán kính geofence)
/// và tự nhấn mạnh POI gần nhất. Dùng bản đồ OpenStreetMap (không cần API key).
class PoiMap extends StatefulWidget {
  const PoiMap({
    super.key,
    required this.pois,
    required this.me,
    required this.highlightId,
    required this.onLongPressPoi,
  });

  final List<Poi> pois;

  /// Vị trí hiện tại (GPS thật hoặc giả lập). Null nếu chưa có.
  final ({double lat, double lng})? me;

  /// Id của POI gần nhất, được vẽ nổi bật. Null nếu chưa biết.
  final int? highlightId;

  /// Giữ lâu một POI trên bản đồ: giả lập có mặt tại đó (giống màn danh sách).
  final void Function(Poi poi) onLongPressPoi;

  @override
  State<PoiMap> createState() => _PoiMapState();
}

class _PoiMapState extends State<PoiMap> {
  final _controller = MapController();

  // Nếu chưa có gì thì mở bản đồ ở khu vực Khánh Hội - Vĩnh Hội.
  static const _fallbackCenter = LatLng(10.7600, 106.7000);

  LatLng get _initialCenter {
    final me = widget.me;
    if (me != null) return LatLng(me.lat, me.lng);
    if (widget.pois.isNotEmpty) {
      return LatLng(widget.pois.first.lat, widget.pois.first.lng);
    }
    return _fallbackCenter;
  }

  // Bản đồ được dựng khi chưa có GPS nên mở ở vị trí dự phòng; lần đầu có
  // vị trí thì tự dời tới đó (sau đó người dùng tự kéo bản đồ thoải mái).
  late bool _centeredOnMe = widget.me != null;

  @override
  void didUpdateWidget(PoiMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final me = widget.me;
    if (!_centeredOnMe && me != null) {
      _centeredOnMe = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.move(LatLng(me.lat, me.lng), 16);
      });
    }
  }

  void _goToMe() {
    final me = widget.me;
    if (me != null) _controller.move(LatLng(me.lat, me.lng), 16);
  }

  void _showAllPois() {
    final points = widget.pois.map((p) => LatLng(p.lat, p.lng)).toList();
    if (points.length < 2) return;
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = widget.me;

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(initialCenter: _initialCenter, initialZoom: 15),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.audio_narration_app',
            ),
            // Vòng tròn bán kính geofence của từng POI (đơn vị mét thật).
            CircleLayer(
              circles: [
                for (final poi in widget.pois)
                  CircleMarker(
                    point: LatLng(poi.lat, poi.lng),
                    radius: poi.radiusM.toDouble(),
                    useRadiusInMeter: true,
                    color: scheme.primary.withValues(alpha: 0.15),
                    borderColor: scheme.primary,
                    borderStrokeWidth: 1.5,
                  ),
              ],
            ),
            // Điểm POI: số trong vòng tròn là mức ưu tiên, POI gần nhất nổi bật.
            MarkerLayer(
              markers: [
                for (final poi in widget.pois)
                  _poiMarker(poi, poi.id == widget.highlightId, scheme),
              ],
            ),
            // Vị trí người dùng.
            if (me != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(me.lat, me.lng),
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
            const SimpleAttributionWidget(
              source: Text('© OpenStreetMap contributors'),
            ),
          ],
        ),
        Positioned(
          right: 12,
          bottom: 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'fit_all',
                tooltip: 'Xem tất cả các điểm',
                onPressed: _showAllPois,
                child: const Icon(Icons.zoom_out_map),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'go_to_me',
                tooltip: 'Về vị trí của tôi',
                onPressed: me == null ? null : _goToMe,
                child: const Icon(Icons.my_location),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Marker _poiMarker(Poi poi, bool highlighted, ColorScheme scheme) {
    final size = highlighted ? 44.0 : 32.0;
    return Marker(
      point: LatLng(poi.lat, poi.lng),
      width: size,
      height: size,
      child: GestureDetector(
        onLongPress: () => widget.onLongPressPoi(poi),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: highlighted ? scheme.primary : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.primary, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: Text(
            '${poi.priority}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: highlighted ? Colors.white : scheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}