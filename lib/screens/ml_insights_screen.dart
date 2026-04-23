import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/driver_score_provider.dart';
import '../models/history_point.dart';
import '../services/ml_insights_service.dart';

class MlInsightsScreen extends StatefulWidget {
  const MlInsightsScreen({super.key});

  @override
  State<MlInsightsScreen> createState() => _MlInsightsScreenState();
}

class _MlInsightsScreenState extends State<MlInsightsScreen> {
  final MlInsightsService _ml = MlInsightsService();
  Future<void>? _initFuture;

  MlPrediction? _driver;
  MlPrediction? _vehicle;
  String? _error;
  bool _running = false;

  Timer? _debounce;
  int _lastScheduledHistoryLen = -1;

  @override
  void initState() {
    super.initState();
    _initFuture = _ml.init();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Pull some historical data early so the ML page can analyze immediately.
      // Live MQTT/Firebase updates will continue populating the rolling buffer.
      try {
        await context.read<DriverScoreProvider>().fetchHistory();
      } catch (_) {
        // Ignore history fetch failures; the page can still work from live points.
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ml.dispose();
    super.dispose();
  }

  void _scheduleRun(List<HistoryPoint> history) {
    if (history.length == _lastScheduledHistoryLen) return;
    _lastScheduledHistoryLen = history.length;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _run(history);
    });
  }

  Future<void> _run(List<HistoryPoint> history) async {
    if (_running) return;
    if (history.length < 20) {
      setState(() {
        _driver = null;
        _vehicle = null;
        _error = null;
      });
      return;
    }

    setState(() {
      _running = true;
      _error = null;
    });

    try {
      await _initFuture;
      final driver = await _ml.predictDriverBehavior(history);
      final vehicle = await _ml.predictVehicleHealth(history);
      if (!mounted) return;
      setState(() {
        _driver = driver;
        _vehicle = vehicle;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Insights',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green[600],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<DriverScoreProvider>(
        builder: (context, provider, _) {
          final history = provider.history;
          _scheduleRun(history);

          return RefreshIndicator(
            onRefresh: () async {
              await provider.fetchHistory();
              await _run(provider.history);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroCard(
                    theme: theme,
                    lastSource: provider.lastRealtimeSource,
                    lastArrival: provider.lastRealtimeArrival,
                    score: provider.driverScore,
                    rawGas: provider.rawGas,
                    temperature: provider.temperature,
                    humidity: provider.humidity,
                    status: provider.status,
                  ),
                  const SizedBox(height: 20),
                  _buildSectionHeader(
                    icon: Icons.psychology,
                    title: 'ML Insights (on-device)',
                    subtitle: 'Based on the last ~80 readings',
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    _buildErrorCard(_error!),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _PredictionCard(
                          title: 'Driver behavior',
                          icon: Icons.directions_car,
                          accent: Colors.green,
                          prediction: _driver,
                          isRunning: _running,
                          emptyHint: history.length < 20
                              ? 'Need ${20 - history.length} more readings to analyze.'
                              : 'Analyzing…',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PredictionCard(
                          title: 'Vehicle health',
                          icon: Icons.health_and_safety,
                          accent: Colors.blueGrey,
                          prediction: _vehicle,
                          isRunning: _running,
                          emptyHint: history.length < 20
                              ? 'Need ${20 - history.length} more readings to analyze.'
                              : 'Analyzing…',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildSectionHeader(
                    icon: Icons.lightbulb_outline,
                    title: 'Suggested actions',
                    subtitle: 'Personalized based on live data',
                  ),
                  const SizedBox(height: 12),
                  _buildRecommendations(
                    driver: _driver,
                    vehicle: _vehicle,
                    score: provider.driverScore,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroCard({
    required ThemeData theme,
    required String lastSource,
    required DateTime? lastArrival,
    required double score,
    required double rawGas,
    required double temperature,
    required double humidity,
    required String status,
  }) {
    final color = Colors.green[600]!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.25),
            spreadRadius: 2,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insights, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live summary',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Source: $lastSource'
                      '${lastArrival == null ? '' : ' • ${_timeAgo(lastArrival)}'}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MetricPill(
                  label: 'Emission score',
                  value: score.toStringAsFixed(0),
                  unit: '',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricPill(
                  label: 'Raw gas',
                  value: rawGas.toStringAsFixed(0),
                  unit: 'ppm',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricPill(
                  label: 'Temp',
                  value: temperature.toStringAsFixed(1),
                  unit: '°C',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricPill(
                  label: 'Humidity',
                  value: humidity.toStringAsFixed(0),
                  unit: '%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.green[700], size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.red[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendations({
    required MlPrediction? driver,
    required MlPrediction? vehicle,
    required double score,
  }) {
    final items = <_Recommendation>[];

    if (driver != null) {
      final label = driver.label.toLowerCase();
      if (label.contains('aggressive')) {
        items.add(
          const _Recommendation(
            icon: Icons.speed,
            title: 'Smooth acceleration',
            body: 'Gradual throttle inputs can reduce spikes and improve efficiency.',
          ),
        );
      } else if (label.contains('idle')) {
        items.add(
          const _Recommendation(
            icon: Icons.timer,
            title: 'Reduce idling',
            body: 'Turn off the engine during long stops to reduce emissions.',
          ),
        );
      } else if (label.contains('eco')) {
        items.add(
          const _Recommendation(
            icon: Icons.eco,
            title: 'Keep it up',
            body: 'Your driving pattern looks efficient—maintain steady speed where possible.',
          ),
        );
      }
    }

    if (vehicle != null) {
      final label = vehicle.label.toLowerCase();
      if (label.contains('critical')) {
        items.add(
          const _Recommendation(
            icon: Icons.build_circle,
            title: 'Service recommended',
            body: 'Model indicates possible vehicle health issues—consider a maintenance check.',
          ),
        );
      } else if (label.contains('needs')) {
        items.add(
          const _Recommendation(
            icon: Icons.build,
            title: 'Preventive maintenance',
            body: 'Check air filter, spark plugs, and fuel system for improved combustion.',
          ),
        );
      }
    }

    if (items.isEmpty) {
      items.add(
        _Recommendation(
          icon: Icons.insights,
          title: score > 400 ? 'High emissions detected' : 'Collect more data',
          body: score > 400
              ? 'Consider checking the vehicle and reviewing driving patterns to reduce emissions.'
              : 'We’ll refine insights as more readings arrive (aim for 20+).',
        ),
      );
    }

    return Column(
      children: items
          .map(
            (r) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.08),
                    spreadRadius: 1,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(r.icon, color: Colors.green[700]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.title,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.body,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey[700],
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  static String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 10) return 'just now';
    if (d.inMinutes < 1) return '${d.inSeconds}s ago';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$value$unit',
            style: GoogleFonts.poppins(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.prediction,
    required this.isRunning,
    required this.emptyHint,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final MlPrediction? prediction;
  final bool isRunning;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final label = p?.label;
    final conf = p?.confidence ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (isRunning) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (label == null) ...[
            Text(
              emptyHint,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700]),
            ),
          ] else ...[
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: conf.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Confidence ${(conf * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }
}

class _Recommendation {
  const _Recommendation({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

