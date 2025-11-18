import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _keyVehicleId = 'vehicle_id';
  static const String _keyCOThreshold = 'co_threshold';
  static const String _keyAQIThreshold = 'aqi_threshold';
  static const String _keyNotifications = 'notifications';
  static const String _keyUpdateInterval = 'update_interval';
  static const String _keyLastPollutionCheck = 'last_pollution_check';
  static const String _keyNextPollutionCheck = 'next_pollution_check';

  Future<String> getVehicleId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyVehicleId) ?? 'MH12AB1234';
  }

  Future<void> setVehicleId(String vehicleId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVehicleId, vehicleId);
  }

  Future<double> getCOThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyCOThreshold) ?? 500.0;
  }

  Future<void> setCOThreshold(double threshold) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCOThreshold, threshold);
  }

  Future<double> getAQIThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyAQIThreshold) ?? 100.0;
  }

  Future<void> setAQIThreshold(double threshold) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyAQIThreshold, threshold);
  }

  Future<bool> getNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNotifications) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotifications, enabled);
  }

  Future<int> getUpdateInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyUpdateInterval) ?? 5;
  }

  Future<void> setUpdateInterval(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUpdateInterval, seconds);
  }

  Future<DateTime?> getLastPollutionCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_keyLastPollutionCheck);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> setLastPollutionCheck(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastPollutionCheck, date.millisecondsSinceEpoch);
  }

  Future<DateTime?> getNextPollutionCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_keyNextPollutionCheck);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> setNextPollutionCheck(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyNextPollutionCheck, date.millisecondsSinceEpoch);
  }

  Future<void> scheduleNextPollutionCheck() async {
    final nextCheck = DateTime.now().add(const Duration(days: 40));
    await setNextPollutionCheck(nextCheck);
    await setLastPollutionCheck(DateTime.now());
  }
}

