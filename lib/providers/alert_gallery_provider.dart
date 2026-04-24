import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

@immutable
class AlertSnapshot {
  const AlertSnapshot({
    required this.id,
    required this.timestampRaw,
    required this.emissionScore,
    required this.imageBase64,
  });

  final String id;
  final String timestampRaw;
  final int emissionScore;
  final String imageBase64;

  DateTime? get timestamp {
    // Accept both "YYYY-MM-DD HH:MM:SS" and ISO8601.
    final raw = timestampRaw.trim();
    if (raw.isEmpty) return null;
    final iso = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    return DateTime.tryParse(iso);
  }

  Uint8List? get imageBytes {
    final raw = imageBase64.trim();
    if (raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }
}

class AlertGalleryProvider with ChangeNotifier {
  static const String _databaseUrl =
      'https://ecodrive-85155-default-rtdb.firebaseio.com';

  DatabaseReference? _databaseRef;
  DatabaseReference? _alertsRef;
  StreamSubscription<DatabaseEvent>? _sub;

  bool _isLoading = true;
  String? _error;
  List<AlertSnapshot> _items = const [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<AlertSnapshot> get items => _items;

  Future<void> startListening() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      _databaseRef ??= FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _databaseUrl,
      ).ref();

      _alertsRef ??= _databaseRef!.child('carEmissions/alerts');

      await _sub?.cancel();
      _sub = _alertsRef!.onValue.listen(
        (event) {
          final value = event.snapshot.value;
          _items = _parseSnapshots(value);
          _isLoading = false;
          _error = null;
          notifyListeners();
        },
        onError: (e) {
          _isLoading = false;
          _error = 'Backend error: $e';
          notifyListeners();
        },
      );
    } catch (e) {
      _isLoading = false;
      _error = 'Backend unavailable';
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await startListening();
  }

  List<AlertSnapshot> _parseSnapshots(dynamic value) {
    if (value is! Map) return const [];

    final out = <AlertSnapshot>[];
    value.forEach((key, v) {
      if (key is! String) return;
      if (v is! Map) return;

      final ts = (v['timestamp'] ?? v['time'] ?? '').toString();
      final emission = v['emissionScore'];
      final score = emission is int
          ? emission
          : int.tryParse(emission?.toString() ?? '') ?? 0;

      // We only show snapshots that include an image payload.
      final img = (v['imageBase64'] ?? '').toString();
      if (img.trim().isEmpty) return;

      out.add(
        AlertSnapshot(
          id: key,
          timestampRaw: ts,
          emissionScore: score,
          imageBase64: img,
        ),
      );
    });

    // Sort newest-first. Prefer parsed timestamp when possible.
    out.sort((a, b) {
      final at = a.timestamp;
      final bt = b.timestamp;
      if (at != null && bt != null) return bt.compareTo(at);
      if (at != null) return -1;
      if (bt != null) return 1;
      return b.id.compareTo(a.id);
    });

    // Keep UI fast: show only the most recent N.
    const maxItems = 25;
    if (out.length > maxItems) return out.sublist(0, maxItems);
    return out;
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}

