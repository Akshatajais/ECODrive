import 'package:flutter/material.dart';

class SensorData {
  final String vehicleId;
  final double coLevel; // 0-1000 ppm
  final double aqi; // Air Quality Index
  final double temperature; // Celsius
  final double humidity; // Percentage
  final DateTime timestamp;

  SensorData({
    required this.vehicleId,
    required this.coLevel,
    required this.aqi,
    required this.temperature,
    required this.humidity,
    required this.timestamp,
  });

  // Calculate emission score: 100 - (CO/5 + AQI/10)
  double get emissionScore {
    double score = 100 - (coLevel / 5 + aqi / 10);
    return score.clamp(0, 100);
  }

  // Get status based on emission score
  String get status {
    if (emissionScore >= 70) return 'Good';
    if (emissionScore >= 40) return 'Moderate';
    return 'High Emission';
  }

  // Get status color
  Color get statusColor {
    if (emissionScore >= 70) return Colors.green;
    if (emissionScore >= 40) return Colors.orange;
    return Colors.red;
  }

  Map<String, dynamic> toJson() {
    return {
      'vehicleId': vehicleId,
      'coLevel': coLevel,
      'aqi': aqi,
      'temperature': temperature,
      'humidity': humidity,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      vehicleId: json['vehicleId'] ?? '',
      coLevel: (json['coLevel'] ?? 0).toDouble(),
      aqi: (json['aqi'] ?? 0).toDouble(),
      temperature: (json['temperature'] ?? 0).toDouble(),
      humidity: (json['humidity'] ?? 0).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

