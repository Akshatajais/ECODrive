import 'dart:math';
import '../models/sensor_data.dart';
import '../models/alert.dart';

class MockDataService {
  static final MockDataService _instance = MockDataService._internal();
  factory MockDataService() => _instance;
  MockDataService._internal();

  final Random _random = Random();
  double _baseCO = 200.0;
  double _baseAQI = 50.0;
  double _baseTemp = 25.0;
  double _baseHumidity = 60.0;
  
  final List<SensorData> _history = [];
  final List<Alert> _alerts = [];

  // Simulate sensor data with realistic variations
  SensorData generateMockData(String vehicleId) {
    // Simulate gradual changes with some randomness
    _baseCO += (_random.nextDouble() - 0.5) * 20;
    _baseCO = _baseCO.clamp(50.0, 800.0);
    
    _baseAQI += (_random.nextDouble() - 0.5) * 10;
    _baseAQI = _baseAQI.clamp(20.0, 200.0);
    
    _baseTemp += (_random.nextDouble() - 0.5) * 2;
    _baseTemp = _baseTemp.clamp(20.0, 35.0);
    
    _baseHumidity += (_random.nextDouble() - 0.5) * 5;
    _baseHumidity = _baseHumidity.clamp(40.0, 80.0);

    final data = SensorData(
      vehicleId: vehicleId,
      coLevel: _baseCO,
      aqi: _baseAQI,
      temperature: _baseTemp,
      humidity: _baseHumidity,
      timestamp: DateTime.now(),
    );

    _history.add(data);
    
    // Keep only last 100 readings
    if (_history.length > 100) {
      _history.removeAt(0);
    }

    // Check for alerts
    _checkAlerts(data);

    return data;
  }

  void _checkAlerts(SensorData data) {
    // Check CO threshold (default 500 ppm)
    if (data.coLevel > 500 && !_hasRecentAlert('CO_HIGH')) {
      _alerts.add(Alert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        coLevel: data.coLevel,
        aqi: data.aqi,
        message: 'High CO Level Detected: ${data.coLevel.toStringAsFixed(1)} ppm',
      ));
    }

    // Check AQI threshold (default 100)
    if (data.aqi > 100 && !_hasRecentAlert('AQI_HIGH')) {
      _alerts.add(Alert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        coLevel: data.coLevel,
        aqi: data.aqi,
        message: 'Poor Air Quality: AQI ${data.aqi.toStringAsFixed(1)}',
      ));
    }

    // Check for idling (CO rises but temp stable)
    if (_history.length >= 5) {
      final recent = _history.sublist(_history.length - 5);
      final coRising = recent.last.coLevel > recent.first.coLevel + 50;
      final tempStable = (recent.last.temperature - recent.first.temperature).abs() < 2;
      
      if (coRising && tempStable && !_hasRecentAlert('IDLING')) {
        _alerts.add(Alert(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          coLevel: data.coLevel,
          aqi: data.aqi,
          message: 'Idling Detected: CO rising while temperature stable',
        ));
      }
    }
  }

  bool _hasRecentAlert(String type) {
    final recent = DateTime.now().subtract(const Duration(minutes: 5));
    return _alerts.any((alert) => 
      alert.message.contains(type) && 
      alert.timestamp.isAfter(recent) &&
      !alert.isCleared
    );
  }

  List<SensorData> getHistory() => List.unmodifiable(_history);
  List<Alert> getAlerts() => List.unmodifiable(_alerts.where((a) => !a.isCleared));

  void clearAlert(String id) {
    final index = _alerts.indexWhere((a) => a.id == id);
    if (index != -1) {
      _alerts[index] = _alerts[index].copyWith(isCleared: true);
    }
  }

  void muteAlert(String id) {
    final index = _alerts.indexWhere((a) => a.id == id);
    if (index != -1) {
      _alerts[index] = _alerts[index].copyWith(isMuted: true);
    }
  }

  int getWarningCountToday() {
    final today = DateTime.now();
    return _alerts.where((alert) => 
      alert.timestamp.year == today.year &&
      alert.timestamp.month == today.month &&
      alert.timestamp.day == today.day &&
      !alert.isCleared
    ).length;
  }

  // Get average daily values
  Map<String, double> getDailyAverages() {
    if (_history.isEmpty) {
      return {'co': 0.0, 'aqi': 0.0};
    }

    final today = DateTime.now();
    final todayData = _history.where((data) =>
      data.timestamp.year == today.year &&
      data.timestamp.month == today.month &&
      data.timestamp.day == today.day
    ).toList();

    if (todayData.isEmpty) {
      return {'co': 0.0, 'aqi': 0.0};
    }

    final avgCO = todayData.map((d) => d.coLevel).reduce((a, b) => a + b) / todayData.length;
    final avgAQI = todayData.map((d) => d.aqi).reduce((a, b) => a + b) / todayData.length;

    return {'co': avgCO, 'aqi': avgAQI};
  }
}

