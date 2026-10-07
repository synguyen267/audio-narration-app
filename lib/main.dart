import 'package:flutter/material.dart';

import 'data/poi_database.dart';
import 'models/poi.dart';

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
  late final Future<List<Poi>> _pois;

  @override
  void initState() {
    super.initState();
    _pois = PoiDatabase.getAll('vi'); // tạm thời cố định tiếng Việt
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Danh sách điểm thuyết minh')),
      body: FutureBuilder<List<Poi>>(
        future: _pois,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Lỗi: ${snapshot.error}'));
          }
          final pois = snapshot.data ?? [];
          return ListView.builder(
            itemCount: pois.length,
            itemBuilder: (context, i) {
              final poi = pois[i];
              return ListTile(
                leading: CircleAvatar(child: Text('${poi.priority}')),
                title: Text(poi.name),
                subtitle: Text(
                  '${poi.lat}, ${poi.lng}  •  bán kính ${poi.radiusM} m',
                ),
              );
            },
          );
        },
      ),
    );
  }
}
