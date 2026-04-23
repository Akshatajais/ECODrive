import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/history_point.dart';

class MlPreprocessBundle {
  const MlPreprocessBundle({
    required this.featureColumns,
    required this.mean,
    required this.scale,
  });

  final List<String> featureColumns;
  final List<double> mean;
  final List<double> scale;

  factory MlPreprocessBundle.fromJson(Map<String, dynamic> json) {
    return MlPreprocessBundle(
      featureColumns: (json['feature_columns'] as List).cast<String>(),
      mean: (json['mean'] as List).map((e) => (e as num).toDouble()).toList(),
      scale: (json['scale'] as List).map((e) => (e as num).toDouble()).toList(),
    );
  }
}

class MlPrediction {
  const MlPrediction({
    required this.label,
    required this.confidence,
    required this.probabilities,
  });

  final String label;
  final double confidence;
  final Map<String, double> probabilities;
}

class MlInsightsService {
  static const String _driverModelAsset = 'ML/models/driver_model.tflite';
  static const String _vehicleModelAsset = 'ML/models/vehicle_model.tflite';
  static const String _driverClassesAsset = 'ML/models/driver_classes.txt';
  static const String _vehicleClassesAsset = 'ML/models/vehicle_classes.txt';
  static const String _driverPreprocessAsset = 'ML/models/driver_preprocess.json';
  static const String _vehiclePreprocessAsset = 'ML/models/vehicle_preprocess.json';

  Interpreter? _driver;
  Interpreter? _vehicle;
  late final List<String> _driverClasses;
  late final List<String> _vehicleClasses;
  late final MlPreprocessBundle _driverPre;
  late final MlPreprocessBundle _vehiclePre;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    _driverClasses = await _loadClasses(_driverClassesAsset);
    _vehicleClasses = await _loadClasses(_vehicleClassesAsset);
    _driverPre = await _loadPreprocess(_driverPreprocessAsset);
    _vehiclePre = await _loadPreprocess(_vehiclePreprocessAsset);

    _driver = await Interpreter.fromAsset(_driverModelAsset);
    _vehicle = await Interpreter.fromAsset(_vehicleModelAsset);

    _initialized = true;
  }

  void dispose() {
    _driver?.close();
    _vehicle?.close();
    _driver = null;
    _vehicle = null;
    _initialized = false;
  }

  Future<MlPrediction> predictDriverBehavior(List<HistoryPoint> history) async {
    await init();
    final input = _buildModelInput(
      history: history,
      preprocess: _driverPre,
      interpreter: _driver!,
    );
    return _run(
      interpreter: _driver!,
      classes: _driverClasses,
      input: input,
    );
  }

  Future<MlPrediction> predictVehicleHealth(List<HistoryPoint> history) async {
    await init();
    final input = _buildModelInput(
      history: history,
      preprocess: _vehiclePre,
      interpreter: _vehicle!,
    );
    return _run(
      interpreter: _vehicle!,
      classes: _vehicleClasses,
      input: input,
    );
  }

  Future<List<String>> _loadClasses(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  Future<MlPreprocessBundle> _loadPreprocess(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return MlPreprocessBundle.fromJson(decoded);
  }

  Map<String, double> _extractFeatures(List<HistoryPoint> session) {
    if (session.isEmpty) {
      throw StateError('No history available for ML session window.');
    }

    final e = session.map((p) => p.emissionScore).where(_finite).toList();
    final g = session.map((p) => p.rawGas).where(_finite).toList();
    if (e.isEmpty || g.isEmpty) {
      throw StateError('Session has no finite emissionScore/rawGas values.');
    }

    final eMean = _mean(e);
    final eStd = _safeStd(e);
    final gMean = _mean(g);
    final gStd = _safeStd(g);

    final zDenom = eStd > 1e-12 ? eStd : 1.0;
    final z = e.map((v) => (v - eMean) / zDenom).toList();

    const spikeZ = 2.0;
    final spikes = z.map((v) => v > spikeZ).toList();
    final spikeCount = spikes.where((s) => s).length;
    final spikeFreq = spikeCount / max(1, e.length);

    final recSlopes = <double>[];
    for (var i = 0; i < spikes.length; i++) {
      if (!spikes[i]) continue;
      if (i + 1 >= e.length) continue;
      recSlopes.add(e[i + 1] - e[i]);
    }
    final recoveryRate = recSlopes.isEmpty ? 0.0 : -_mean(recSlopes);

    // Idle estimate: rawGas unusually stable within a tight band around median.
    final gMed = _median(g);
    final band = max(
      1e-6,
      0.15 * (gStd > 1e-12 ? gStd : max(1.0, gMed.abs())),
    );
    final idleRatio =
        g.where((v) => (v - gMed).abs() <= band).length / max(1, g.length);

    final driftSlope = _linSlope(e);
    const sustainedHighZ = 1.0;
    final sustainedHighRatio =
        z.where((v) => v > sustainedHighZ).length / max(1, z.length);
    final variance = _variance(e, eMean);

    return {
      'mean_emissionScore': eMean,
      'std_emissionScore': eStd,
      'mean_rawGas': gMean,
      'std_rawGas': gStd,
      'spike_freq': spikeFreq,
      'spike_count': spikeCount.toDouble(),
      'recovery_rate': recoveryRate,
      'idle_ratio': idleRatio,
      'baseline_drift': driftSlope,
      'sustained_high_ratio': sustainedHighRatio,
      'variance_emissionScore': variance,
      'worsening_trend_slope': driftSlope,
      'high_spike_count': spikeCount.toDouble(),
      'session_len': e.length.toDouble(),
    };
  }

  /// Builds a single feature vector in the correct column order,
  /// then standardizes and quantizes to the model's int8 input tensor.
  List<int> _buildModelInput({
    required List<HistoryPoint> history,
    required MlPreprocessBundle preprocess,
    required Interpreter interpreter,
  }) {
    // Use a rolling window; ML README suggests 50–100.
    final window = history.length <= 80 ? history : history.sublist(history.length - 80);
    final feats = _extractFeatures(window);

    final ordered = <double>[];
    for (final col in preprocess.featureColumns) {
      ordered.add(feats[col] ?? 0.0);
    }

    final standardized = List<double>.generate(
      ordered.length,
      (i) => (ordered[i] - preprocess.mean[i]) / (preprocess.scale[i] == 0 ? 1.0 : preprocess.scale[i]),
    );

    final inputTensor = interpreter.getInputTensor(0);
    final q = inputTensor.params;
    final scale = q.scale;
    final zeroPoint = q.zeroPoint;

    return standardized.map((v) {
      final qv = (v / scale + zeroPoint).round();
      return qv.clamp(-128, 127).toInt();
    }).toList();
  }

  MlPrediction _run({
    required Interpreter interpreter,
    required List<String> classes,
    required List<int> input,
  }) {
    final inputTensor = interpreter.getInputTensor(0);
    final inShape = inputTensor.shape; // e.g. [1, N]
    final n = inShape.length > 1 ? inShape[1] : input.length;
    final in2d = [input.take(n).toList()];

    final outTensor = interpreter.getOutputTensor(0);
    final outShape = outTensor.shape; // e.g. [1, C]
    final c = outShape.length > 1 ? outShape[1] : classes.length;
    final out2d = List.generate(1, (_) => List.filled(c, 0));

    interpreter.run(in2d, out2d);

    // Dequantize output to float, then softmax for probabilities.
    final oq = outTensor.params;
    final outScale = oq.scale;
    final outZeroPoint = oq.zeroPoint;
    final logits = out2d[0]
        .take(c)
        .map((v) => (v - outZeroPoint) * outScale)
        .toList();

    final probs = _softmax(logits);
    var bestIdx = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[bestIdx]) bestIdx = i;
    }

    final map = <String, double>{};
    for (var i = 0; i < min(classes.length, probs.length); i++) {
      map[classes[i]] = probs[i];
    }

    return MlPrediction(
      label: classes.isNotEmpty && bestIdx < classes.length ? classes[bestIdx] : 'Unknown',
      confidence: probs.isNotEmpty ? probs[bestIdx] : 0.0,
      probabilities: map,
    );
  }

  static bool _finite(double v) => v.isFinite;

  static double _mean(List<double> x) => x.reduce((a, b) => a + b) / x.length;

  static double _safeStd(List<double> x) {
    final m = _mean(x);
    final v = _variance(x, m);
    final s = sqrt(v);
    if (!s.isFinite || s <= 1e-12) return 0.0;
    return s;
  }

  static double _variance(List<double> x, double mean) {
    if (x.isEmpty) return 0.0;
    var acc = 0.0;
    for (final v in x) {
      final d = v - mean;
      acc += d * d;
    }
    return acc / x.length;
  }

  static double _median(List<double> x) {
    if (x.isEmpty) return 0.0;
    final s = [...x]..sort();
    final mid = s.length ~/ 2;
    if (s.length.isOdd) return s[mid];
    return (s[mid - 1] + s[mid]) / 2.0;
  }

  static double _linSlope(List<double> y) {
    if (y.length < 2) return 0.0;
    final n = y.length;
    final xMean = (n - 1) / 2.0;
    final yMean = _mean(y);
    var num = 0.0;
    var den = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = i - xMean;
      final dy = y[i] - yMean;
      num += dx * dy;
      den += dx * dx;
    }
    if (den.abs() < 1e-12) return 0.0;
    return num / den;
  }

  static List<double> _softmax(List<double> logits) {
    if (logits.isEmpty) return const [];
    final maxLogit = logits.reduce(max);
    final exps = logits.map((l) => exp(l - maxLogit)).toList();
    final sum = exps.reduce((a, b) => a + b);
    if (sum == 0) return List.filled(logits.length, 0.0);
    return exps.map((e) => e / sum).toList();
  }
}

