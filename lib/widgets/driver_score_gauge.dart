import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

class DriverScoreGauge extends StatelessWidget {
  final double score;
  final String status;
  final bool isLoading;

  const DriverScoreGauge({
    super.key,
    required this.score,
    required this.status,
    this.isLoading = false,
  });

  Color _getColorForScore(double score) {
    if (score <= 150) return Colors.green;
    if (score <= 300) return Colors.orange;
    return Colors.red;
  }


  @override
  Widget build(BuildContext context) {
    final color = _getColorForScore(score);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                height: 280,
                width: 320,
                child: SfRadialGauge(
                  axes: <RadialAxis>[
                    RadialAxis(
                      minimum: 0,
                      maximum: 500,
                      showLabels: false,
                      showTicks: false,
                      startAngle: 180,
                      endAngle: 0,
                      radiusFactor: 0.95,
                      axisLineStyle: const AxisLineStyle(
                        thickness: 0.15,
                        thicknessUnit: GaugeSizeUnit.factor,
                        color: Colors.grey,
                      ),
                      ranges: <GaugeRange>[
                        GaugeRange(
                          startValue: 0,
                          endValue: 150,
                          color: Colors.green,
                          startWidth: 0.15,
                          endWidth: 0.15,
                          sizeUnit: GaugeSizeUnit.factor,
                        ),
                        GaugeRange(
                          startValue: 150,
                          endValue: 300,
                          color: Colors.orange,
                          startWidth: 0.15,
                          endWidth: 0.15,
                          sizeUnit: GaugeSizeUnit.factor,
                        ),
                        GaugeRange(
                          startValue: 300,
                          endValue: 500,
                          color: Colors.red,
                          startWidth: 0.15,
                          endWidth: 0.15,
                          sizeUnit: GaugeSizeUnit.factor,
                        ),
                      ],
                      pointers: <GaugePointer>[
                        NeedlePointer(
                          value: score,
                          enableAnimation: true,
                          animationDuration: 1200,
                          knobStyle: KnobStyle(
                            color: color,
                            knobRadius: 0.06,
                          ),
                          needleColor: color,
                          tailStyle: TailStyle(color: color, width: 4, length: 0.18),
                        ),
                      ],
                      annotations: isLoading
                          ? <GaugeAnnotation>[
                              GaugeAnnotation(
                                widget: const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                ),
                                positionFactor: 0.0,
                              ),
                            ]
                          : const <GaugeAnnotation>[],
                    ),
                  ],
                ),
              ),
              if (!isLoading)
                Positioned(
                  bottom: 50,
                  child: Text(
                    score.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      color: color,
                      height: 1.0,
                      letterSpacing: -1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
          if (!isLoading) ...[
            const SizedBox(height: 5),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: color.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

