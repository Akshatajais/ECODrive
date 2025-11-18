class HistoryPoint {
  final DateTime timestamp;
  final double emissionScore;
  final double rawGas;
  final double temperature;

  HistoryPoint({
    required this.timestamp,
    required this.emissionScore,
    required this.rawGas,
    required this.temperature,
  });
}

