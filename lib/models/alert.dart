class Alert {
  final String id;
  final DateTime timestamp;
  final double coLevel;
  final double aqi;
  final String message;
  final bool isMuted;
  final bool isCleared;

  Alert({
    required this.id,
    required this.timestamp,
    required this.coLevel,
    required this.aqi,
    required this.message,
    this.isMuted = false,
    this.isCleared = false,
  });

  Alert copyWith({
    String? id,
    DateTime? timestamp,
    double? coLevel,
    double? aqi,
    String? message,
    bool? isMuted,
    bool? isCleared,
  }) {
    return Alert(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      coLevel: coLevel ?? this.coLevel,
      aqi: aqi ?? this.aqi,
      message: message ?? this.message,
      isMuted: isMuted ?? this.isMuted,
      isCleared: isCleared ?? this.isCleared,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'coLevel': coLevel,
      'aqi': aqi,
      'message': message,
      'isMuted': isMuted,
      'isCleared': isCleared,
    };
  }

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      coLevel: (json['coLevel'] ?? 0).toDouble(),
      aqi: (json['aqi'] ?? 0).toDouble(),
      message: json['message'] ?? '',
      isMuted: json['isMuted'] ?? false,
      isCleared: json['isCleared'] ?? false,
    );
  }
}

