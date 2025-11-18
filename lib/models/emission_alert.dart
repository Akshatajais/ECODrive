class EmissionAlert {
  final String id;
  final DateTime timestamp;
  final double emissionScore;
  final String message;

  EmissionAlert({
    required this.id,
    required this.timestamp,
    required this.emissionScore,
    required this.message,
  });
}

