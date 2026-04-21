import 'package:flutter/foundation.dart';

import '../services/evidence_capture_service.dart';
import 'camera_stream_provider.dart';
import 'driver_score_provider.dart';

class EvidenceCaptureProvider {
  EvidenceCaptureProvider({
    EvidenceCaptureService? service,
    this.threshold = 500,
    this.cooldown = const Duration(seconds: 45),
  }) : _service = service ?? EvidenceCaptureService();

  final EvidenceCaptureService _service;

  final double threshold;
  final Duration cooldown;

  DateTime? _lastCaptureAt;
  bool _wasHigh = false;
  bool _inFlight = false;

  void maybeCapture({
    required DriverScoreProvider driver,
    required CameraStreamProvider camera,
  }) {
    final score = driver.driverScore;
    final isHigh = score >= threshold;

    if (!isHigh) {
      _wasHigh = false;
      return;
    }

    final now = DateTime.now();
    final cooldownOk =
        _lastCaptureAt == null || now.difference(_lastCaptureAt!) >= cooldown;
    final shouldCapture = (!_wasHigh) || cooldownOk;

    if (!shouldCapture) {
      _wasHigh = true;
      return;
    }

    if (_inFlight) return;
    _inFlight = true;
    _wasHigh = true;
    _lastCaptureAt = now;

    final deviceId = driver.licensePlate;
    debugPrint(
      '[EVIDENCE] trigger score=$score threshold=$threshold cooldown=${cooldown.inSeconds}s device=$deviceId streamUrl=${camera.streamUrl}',
    );

    () async {
      try {
        await _service.captureAndStore(
          deviceId: deviceId,
          emissionScore: driver.driverScore,
          rawGas: driver.rawGas,
          streamUrl: camera.streamUrl,
          eventTime: driver.timestamp,
          source: driver.lastRealtimeSource,
        );
      } catch (e) {
        debugPrint('[EVIDENCE] capture failed: $e');
      } finally {
        _inFlight = false;
      }
    }();
  }
}

