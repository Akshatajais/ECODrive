import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/history_point.dart';
import '../models/emission_alert.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';

class DriverScoreProvider with ChangeNotifier {
  static const String _databaseUrl =
      'https://ecodrive-85155-default-rtdb.firebaseio.com';
  static const String _fallbackPlate = 'MH12AB1234';

  final NotificationService _notificationService = NotificationService();
  final SettingsService _settingsService = SettingsService();

  DatabaseReference? _databaseRef;
  DatabaseReference? _liveRef;
  DatabaseReference? _historyRef;
  DatabaseReference? _alertsRef;

  StreamSubscription<DatabaseEvent>? _liveSubscription;
  StreamSubscription<DatabaseEvent>? _alertsSubscription;

  double _driverScore = 0.0;
  double _rawGas = 0.0;
  double _temperature = 0.0;
  double _humidity = 0.0;
  DateTime? _timestamp;
  bool _isLoading = true;
  String? _error;
  String _licensePlate = _fallbackPlate;

  final List<HistoryPoint> _history = [];
  bool _historyFromFirebase = false;
  final List<EmissionAlert> _alerts = [];
  DateTime? _lastAlertTimestamp;

  double get driverScore => _driverScore;
  double get rawGas => _rawGas;
  double get temperature => _temperature;
  double get humidity => _humidity;
  DateTime? get timestamp => _timestamp;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get licensePlate => _licensePlate;

  List<HistoryPoint> get history => List.unmodifiable(_history);
  List<EmissionAlert> get alertLogs => List.unmodifiable(_alerts);

  String get status {
    if (_driverScore <= 150) return 'GOOD';
    if (_driverScore <= 300) return 'MODERATE';
    return 'POOR';
  }

  Future<bool> _ensureDatabase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      _databaseRef ??= FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _databaseUrl,
      ).ref();
      await _notificationService.init();
      _licensePlate = await _settingsService.getVehicleId();
      return true;
    } catch (e) {
      _setMockData('Firebase initialization failed. Showing demo data.');
      return false;
    }
  }

  Future<void> startListening() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final hasDatabase = await _ensureDatabase();
    if (!hasDatabase) return;

    _liveRef ??= _databaseRef!.child('carEmissions/liveData');
    _alertsRef ??= _databaseRef!.child('carEmissions/alerts');

    _listenToAlerts();

    _liveSubscription?.cancel();
    _liveSubscription = _liveRef!.onValue.listen(
      (event) {
        final data = event.snapshot.value;
        if (data == null) {
          _setMockData('No live data found. Showing demo data.');
          return;
        }
        _applyRealtimeData(data);
      },
      onError: (error) {
        _setMockData('Firebase error: $error. Showing demo data.');
      },
    );
  }

  Future<void> fetchHistory() async {
    final hasDatabase = await _ensureDatabase();
    if (!hasDatabase) return;

    _historyRef ??= _databaseRef!.child('carEmissions/history');
    final snapshot = await _historyRef!.get();
    if (!snapshot.exists || snapshot.value == null) {
      _historyFromFirebase = false;
      return;
    }

    final List<HistoryPoint> points = [];
    final value = snapshot.value;
    if (value is Map) {
      value.forEach((key, entry) {
        if (entry is Map) {
          final timestamp = _parseTimestamp(entry['timestamp']);
          final score = _parseDouble(entry['emissionScore']);
          final rawGas = _parseDouble(entry['rawGas']);
          final temp = _parseDouble(entry['temperature']);
          if (timestamp != null && score != null && rawGas != null && temp != null) {
            points.add(
              HistoryPoint(
                timestamp: timestamp,
                emissionScore: score,
                rawGas: rawGas,
                temperature: temp,
              ),
            );
          }
        }
      });
    }

    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (points.isEmpty) {
      _historyFromFirebase = false;
      notifyListeners();
      return;
    }

    _history
      ..clear()
      ..addAll(points);
    _historyFromFirebase = true;
    notifyListeners();
  }

  void _listenToAlerts() {
    if (_alertsRef == null || _alertsSubscription != null) return;

    _alertsSubscription = _alertsRef!.onValue.listen((event) {
      final value = event.snapshot.value;
      final List<EmissionAlert> loaded = [];
      if (value is Map) {
        value.forEach((key, entry) {
          if (entry is Map) {
            final timestamp = _parseTimestamp(entry['timestamp']);
            final score = _parseDouble(entry['emissionScore']);
            final message = entry['message']?.toString() ?? 'High emission event';
            if (timestamp != null && score != null) {
              loaded.add(
                EmissionAlert(
                  id: key,
                  timestamp: timestamp,
                  emissionScore: score,
                  message: message,
                ),
              );
            }
          }
        });
      }

      loaded.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _alerts
        ..clear()
        ..addAll(loaded);
      notifyListeners();
    });
  }

  void _applyRealtimeData(dynamic data) {
    double? parsedScore;
    double? parsedTemp;
    double? parsedHumidity;
    double? parsedRawGas;
    DateTime? parsedTimestamp;

    if (data is Map) {
      parsedScore = _parseDouble(data['emissionScore']);
      parsedTemp = _parseDouble(data['temperature']);
      parsedHumidity = _parseDouble(data['humidity']);
      parsedRawGas = _parseDouble(data['rawGas']);
      parsedTimestamp = _parseTimestamp(data['timestamp']);
    } else if (data is num) {
      parsedScore = data.toDouble();
    } else if (data is String) {
      parsedScore = double.tryParse(data);
    }

    if (parsedScore == null &&
        parsedTemp == null &&
        parsedHumidity == null &&
        parsedRawGas == null) {
      _setMockData('Invalid live data. Showing demo data.');
      return;
    }

    if (parsedScore != null) {
      _driverScore = parsedScore.clamp(0.0, 500.0);
    }
    if (parsedTemp != null) {
      _temperature = parsedTemp;
    }
    if (parsedHumidity != null) {
      _humidity = parsedHumidity;
    }
    if (parsedRawGas != null) {
      _rawGas = parsedRawGas;
    }
    _timestamp = parsedTimestamp ?? DateTime.now();

    if (!_historyFromFirebase && _timestamp != null) {
      _appendLocalHistory(
        HistoryPoint(
          timestamp: _timestamp!,
          emissionScore: _driverScore,
          rawGas: _rawGas,
          temperature: _temperature,
        ),
      );
    }

    _evaluateAlertThresholds();

    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  void _appendLocalHistory(HistoryPoint point) {
    _history.add(point);
    if (_history.length > 200) {
      _history.removeAt(0);
    }
  }

  void _evaluateAlertThresholds() {
    if (_timestamp == null) return;
    if (_driverScore <= 400) return;
    if (_lastAlertTimestamp != null &&
        _timestamp!.difference(_lastAlertTimestamp!).inMinutes < 5) {
      return;
    }

    _lastAlertTimestamp = _timestamp;
    _notificationService.showHighEmissionAlert(
      title: 'High Emission Detected',
      body:
          'Driver score > 400. Follow good practices or get your vehicle checked.',
    );
    schedule30DayReminder(_timestamp!);
    addAlertEntry(
      emissionScore: _driverScore,
      timestamp: _timestamp!,
      message: 'High emission event',
    );
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) {
      if (value > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    if (value is double) {
      final millis = value > 1000000000000 ? value.toInt() : (value * 1000).toInt();
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
      final numeric = double.tryParse(value);
      if (numeric != null) {
        return _parseTimestamp(numeric);
      }
    }
    return null;
  }

  void _setMockData(String message) {
    _driverScore = 120.0;
    _rawGas = 320.0;
    _temperature = 26.0;
    _humidity = 58.0;
    _timestamp = DateTime.now();
    _isLoading = false;
    _error = message;
    notifyListeners();
  }

  Future<void> addAlertEntry({
    required double emissionScore,
    required DateTime timestamp,
    required String message,
  }) async {
    final alert = EmissionAlert(
      id: timestamp.millisecondsSinceEpoch.toString(),
      timestamp: timestamp,
      emissionScore: emissionScore,
      message: message,
    );
    _alerts.insert(0, alert);
    notifyListeners();

    try {
      await _alertsRef?.push().set({
        'emissionScore': emissionScore,
        'timestamp': timestamp.toIso8601String(),
        'message': message,
      });
    } catch (_) {
      // ignore write failures for now
    }
  }

  Future<void> schedule30DayReminder(DateTime sourceTimestamp) async {
    DateTime triggerDate = sourceTimestamp.add(const Duration(days: 30));
    if (triggerDate.isBefore(DateTime.now())) {
      triggerDate = DateTime.now().add(const Duration(minutes: 1));
    }
    await _notificationService.scheduleReminder(
      id: triggerDate.millisecondsSinceEpoch ~/ 1000,
      title: 'Pollution Check Reminder',
      body: 'It\'s been 30 days since the last high emission event.',
      scheduledDate: triggerDate,
    );
  }

  Future<void> updateLicensePlate(String plate) async {
    _licensePlate = plate.isEmpty ? _fallbackPlate : plate;
    await _settingsService.setVehicleId(_licensePlate);
    notifyListeners();
  }

  void stopListening() {
    _liveSubscription?.cancel();
    _liveSubscription = null;
    _alertsSubscription?.cancel();
    _alertsSubscription = null;
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}

