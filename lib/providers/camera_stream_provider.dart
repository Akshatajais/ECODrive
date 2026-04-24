import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

class CameraStreamProvider with ChangeNotifier {
  static const String _databaseUrl =
      'https://ecodrive-85155-default-rtdb.firebaseio.com';
  static const String _fallbackStreamUrl = 'http://192.168.54.213';

  DatabaseReference? _databaseRef;
  DatabaseReference? _cameraRef;
  StreamSubscription<DatabaseEvent>? _cameraSubscription;

  bool _isLoading = true;
  String? _error;
  String? _streamUrl;
  String _lastSource = 'none';

  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get streamUrl => _streamUrl;
  String get lastSource => _lastSource;

  bool get isCameraConnected => (_streamUrl ?? '').trim().isNotEmpty;

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

      _cameraRef ??= _databaseRef!.child('carEmissions/camera');

      await _cameraSubscription?.cancel();
      _cameraSubscription = _cameraRef!.onValue.listen(
        (event) {
          final value = event.snapshot.value;
          _streamUrl = _extractStreamUrl(value) ?? _fallbackStreamUrl;
          _lastSource = _extractStreamUrl(value) == null ? 'FALLBACK' : 'FIREBASE';
          debugPrint(
            '[CAMERA][FIREBASE] Firebase update received streamUrl=${_streamUrl ?? 'null'} raw=$value',
          );
          _isLoading = false;
          _error = null;
          notifyListeners();
        },
        onError: (e) {
          _isLoading = false;
          _error = 'Backend error: $e';
          _streamUrl = _fallbackStreamUrl;
          _lastSource = 'FALLBACK';
          notifyListeners();
        },
      );
    } catch (e) {
      _isLoading = false;
      _error = 'Backend unavailable';
      _streamUrl = _fallbackStreamUrl;
      _lastSource = 'FALLBACK';
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await startListening();
  }

  String? _extractStreamUrl(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is Map) {
      final streamUrl = value['streamUrl'] ?? value['url'] ?? value['stream'];
      if (streamUrl is String) {
        final trimmed = streamUrl.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
    }
    return null;
  }

  void stopListening() {
    _cameraSubscription?.cancel();
    _cameraSubscription = null;
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}

