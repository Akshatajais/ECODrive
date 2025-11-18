import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

class WeatherProvider with ChangeNotifier {
  final Random _random = Random();
  double _aqi = 0.0;
  double _temperature = 0.0;
  double _humidity = 0.0;
  bool _isLoading = true;
  String? _error;
  DateTime? _lastUpdate;
  Timer? _refreshTimer;

  // Base values for realistic mock data
  double _baseAQI = 45.0;
  double _baseTemperature = 25.0;
  double _baseHumidity = 60.0;

  double get aqi => _aqi;
  double get temperature => _temperature;
  double get humidity => _humidity;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastUpdate => _lastUpdate;

  Future<void> fetchWeatherData({String? city, double? lat, double? lon}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Generate realistic mock data with gradual variations
    _baseAQI += (_random.nextDouble() - 0.5) * 5;
    _baseAQI = _baseAQI.clamp(30.0, 80.0);

    _baseTemperature += (_random.nextDouble() - 0.5) * 2;
    _baseTemperature = _baseTemperature.clamp(20.0, 35.0);

    _baseHumidity += (_random.nextDouble() - 0.5) * 3;
    _baseHumidity = _baseHumidity.clamp(40.0, 80.0);

    _aqi = _baseAQI;
    _temperature = _baseTemperature;
    _humidity = _baseHumidity;
    _lastUpdate = DateTime.now();
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  void startAutoRefresh({String? city, double? lat, double? lon, int intervalSeconds = 45}) {
    _refreshTimer?.cancel();
    fetchWeatherData(city: city, lat: lat, lon: lon);
    
    // Auto-refresh every intervalSeconds
    _refreshTimer = Timer.periodic(Duration(seconds: intervalSeconds), (timer) {
      fetchWeatherData(city: city, lat: lat, lon: lon);
    });
  }

  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }
}
