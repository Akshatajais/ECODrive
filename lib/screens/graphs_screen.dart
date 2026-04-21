import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/history_point.dart';
import '../providers/driver_score_provider.dart';

enum TimeFilter { hour, day, week }

class GraphsScreen extends StatefulWidget {
  const GraphsScreen({super.key});

  @override
  State<GraphsScreen> createState() => _GraphsScreenState();
}

class _GraphsScreenState extends State<GraphsScreen> {
  TimeFilter _filter = TimeFilter.day;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DriverScoreProvider>(context, listen: false).fetchHistory();
    });
  }

  void _setFilter(TimeFilter filter) {
    setState(() => _filter = filter);
  }

  Duration get _filterDuration {
    switch (_filter) {
      case TimeFilter.hour:
        return const Duration(hours: 1);
      case TimeFilter.day:
        return const Duration(days: 1);
      case TimeFilter.week:
        return const Duration(days: 7);
    }
  }

  List<HistoryPoint> _filteredHistory(List<HistoryPoint> history) {
    if (history.isEmpty) return history;
    final now = DateTime.now();
    final cutoff = now.subtract(_filterDuration);
    final filtered =
        history.where((point) => point.timestamp.isAfter(cutoff)).toList();
    filtered.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return filtered;
  }

  List<FlSpot> _buildSpots(
    List<HistoryPoint> data,
    double Function(HistoryPoint point) mapper,
  ) {
    return List.generate(
      data.length,
      (index) => FlSpot(index.toDouble(), mapper(data[index])),
    );
  }

  Widget _buildTimeFilter() {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildChip('Last 1 hr', TimeFilter.hour),
          _buildChip('Last 24 hrs', TimeFilter.day),
          _buildChip('Last 7 days', TimeFilter.week),
        ],
      ),
    );
  }

  Widget _buildChip(String label, TimeFilter filter) {
    final isSelected = _filter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _setFilter(filter),
      selectedColor: Colors.green[200],
    );
  }

  Widget _buildSingleChart({
    required String title,
    required List<HistoryPoint> data,
    required List<FlSpot> spots,
    required Color color,
    required double minY,
    required double maxY,
    required String unit,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 220,
            child: spots.isEmpty
                ? Center(
                    child: Text(
                      'No data in selected range',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (spots.length - 1).toDouble().clamp(0, double.infinity),
                      minY: minY,
                      maxY: maxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: (maxY - minY) / 4,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey[200]!,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) => Text(
                              '${value.toInt()}$unit',
                              style: TextStyle(color: Colors.grey[600], fontSize: 10),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: spots.length <= 1 ? 1 : (spots.length / 4),
                            getTitlesWidget: (value, meta) {
                              final index = value.round();
                              if (index >= 0 && index < data.length) {
                                return Text(
                                  DateFormat('MMM d\nHH:mm').format(data[index].timestamp),
                                  style: TextStyle(color: Colors.grey[600], fontSize: 10),
                                  textAlign: TextAlign.center,
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: color,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: color.withOpacity(0.15),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDualChart({
    required String title,
    required List<HistoryPoint> data,
    required List<FlSpot> rawGasSpots,
    required List<FlSpot> temperatureSpots,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Raw Gas (ppm) & Temperature (°C)',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 240,
            child: rawGasSpots.isEmpty
                ? Center(
                    child: Text(
                      'No data in selected range',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (rawGasSpots.length - 1)
                          .toDouble()
                          .clamp(0, double.infinity),
                      minY: 0,
                      maxY:  _dualMax(rawGasSpots, temperatureSpots),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey[200]!,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) => Text(
                              value.toInt().toString(),
                              style: TextStyle(color: Colors.grey[600], fontSize: 10),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: rawGasSpots.length <= 1
                                ? 1
                                : (rawGasSpots.length / 4),
                            getTitlesWidget: (value, meta) {
                              final index = value.round();
                              if (index >= 0 && index < data.length) {
                                return Text(
                                  DateFormat('MMM d\nHH:mm')
                                      .format(data[index].timestamp),
                                  style:
                                      TextStyle(color: Colors.grey[600], fontSize: 10),
                                  textAlign: TextAlign.center,
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        _buildLine(rawGasSpots, Colors.deepPurple),
                        _buildLine(
                          temperatureSpots,
                          Colors.orange,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _buildLine(
    List<FlSpot> spots,
    Color color,
  ) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 3,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withOpacity(0.1),
      ),
    );
  }

  double _maxValue(List<FlSpot> spots) {
    if (spots.isEmpty) return 0;
    return spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
  }

  double _dualMax(List<FlSpot> a, List<FlSpot> b) {
    final value = math.max(_maxValue(a), _maxValue(b));
    if (value == 0) return 10;
    return value * 1.1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Analytics & Graphs',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green[600],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              Provider.of<DriverScoreProvider>(context, listen: false)
                  .fetchHistory();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<DriverScoreProvider>(
        builder: (context, provider, child) {
          final filtered = _filteredHistory(provider.history);
          final emissionSpots = _buildSpots(filtered, (point) => point.emissionScore);
          final rawGasSpots = _buildSpots(filtered, (point) => point.rawGas);
          final tempSpots = _buildSpots(filtered, (point) => point.temperature);

          return RefreshIndicator(
            onRefresh: () async {
              await provider.fetchHistory();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTimeFilter(),
                  const SizedBox(height: 16),
                  _buildSingleChart(
                    title: 'Emission Score vs Time',
                    data: filtered,
                    spots: emissionSpots,
                    color: Colors.green,
                    minY: 0,
                    maxY: 500,
                    unit: '',
                  ),
                  _buildDualChart(
                    title: 'Raw Gas & Temperature',
                    data: filtered,
                    rawGasSpots: rawGasSpots,
                    temperatureSpots: tempSpots,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

