import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';

class InsightsScreen extends StatefulWidget {
  InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final NotificationService _notificationService = NotificationService();
  final SettingsService _settingsService = SettingsService();
  
  DateTime? _nextPollutionCheck;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPollutionCheckData();
    _initializeReminder();
  }

  Future<void> _loadPollutionCheckData() async {
    final nextCheck = await _settingsService.getNextPollutionCheck();
    
    setState(() {
      _nextPollutionCheck = nextCheck;
      _isLoading = false;
    });
  }

  Future<void> _initializeReminder() async {
    final nextCheck = await _settingsService.getNextPollutionCheck();
    if (nextCheck == null) {
      // If no reminder is set, schedule one for 40 days from now
      await _settingsService.scheduleNextPollutionCheck();
      final newNextCheck = await _settingsService.getNextPollutionCheck();
      if (newNextCheck != null) {
        await _notificationService.scheduleReminder(
          id: newNextCheck.millisecondsSinceEpoch ~/ 1000,
          title: 'Pollution Check Reminder',
          body: 'Time to perform an emission check on your vehicle.',
          scheduledDate: newNextCheck,
        );
      }
      await _loadPollutionCheckData();
    }
  }

  Future<void> _markCheckAsDone() async {
    await _settingsService.scheduleNextPollutionCheck();
    final newNextCheck = await _settingsService.getNextPollutionCheck();
    if (newNextCheck != null) {
      await _notificationService.scheduleReminder(
        id: newNextCheck.millisecondsSinceEpoch ~/ 1000,
        title: 'Pollution Check Reminder',
        body: 'Time to perform an emission check on your vehicle.',
        scheduledDate: newNextCheck,
      );
    }
    await _loadPollutionCheckData();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pollution check marked as done. Next reminder scheduled in 40 days.',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _scheduleReminder(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextPollutionCheck ?? now.add(const Duration(days: 40)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked == null) return;

    await _settingsService.setNextPollutionCheck(picked);
    await _notificationService.scheduleReminder(
      id: picked.millisecondsSinceEpoch ~/ 1000,
      title: 'Pollution Check Reminder',
      body: 'Time to perform an emission check on your vehicle.',
      scheduledDate: picked,
    );

    await _loadPollutionCheckData();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reminder scheduled for ${DateFormat('MMM dd, yyyy').format(picked)}',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  int _getDaysUntilCheck() {
    if (_nextPollutionCheck == null) return 40;
    final now = DateTime.now();
    final difference = _nextPollutionCheck!.difference(now).inDays;
    return difference > 0 ? difference : 0;
  }

  final List<Map<String, String>> _articles = [
    {
      'title': 'What causes vehicle emissions?',
      'content':
          'Unburned fuel, worn-out spark plugs, and clogged filters can increase toxic gases.'
    },
    {
      'title': 'Impact of idling on air quality',
      'content':
          'Idling for 10 minutes burns more fuel than restarting and releases additional NOx.'
    },
    {
      'title': 'How tyre pressure affects pollution',
      'content':
          'Underinflated tyres force the engine to work harder, increasing particulate matter.'
    },
    {
      'title': 'Fuel choices that help the planet',
      'content':
          'Low-sulfur fuels and regular fuel-system cleaners can keep sensors performing optimally.'
    },
    {
      'title': 'Why emission testing matters',
      'content':
          'Regular tests detect catalytic converter failures before they harm public health.'
    },
    {
      'title': 'Driving habits that cut CO₂',
      'content':
          'Smooth acceleration and anticipatory braking can reduce emissions by up to 20%.'
    },
    {
      'title': 'Urban heat & pollution',
      'content':
          'Higher city temperatures amplify ozone formation, worsening breathing conditions.'
    },
  ];

  final List<String> _goodPractices = [
    'Schedule periodic emission checks.',
    'Clean the air filter every 5000 km.',
    'Avoid prolonged idling in traffic.',
    'Keep tyre pressure within recommended range.',
    'Use certified fuel additives sparingly.',
  ];

  @override
  Widget build(BuildContext context) {
    final daysUntil = _getDaysUntilCheck();
    final isDue = daysUntil == 0;
    final isSoon = daysUntil > 0 && daysUntil <= 7;

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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadPollutionCheckData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pollution Check Reminder Card
                    _buildPollutionCheckCard(daysUntil, isDue, isSoon),
                    const SizedBox(height: 24),
                    
                    // Good Practices Card
                    _buildPracticesCard(),
                    const SizedBox(height: 24),
                    
                    // Articles Section Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.article,
                            color: Colors.green[700],
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Air Quality Insights',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Articles
                    ..._articles.map((article) => _ArticleCard(article: article)),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPollutionCheckCard(int daysUntil, bool isDue, bool isSoon) {
    Color cardColor;
    Color textColor;
    IconData icon;
    String statusText;
    
    if (isDue) {
      cardColor = Colors.red[600]!;
      textColor = Colors.white;
      icon = Icons.warning;
      statusText = 'Due Now';
    } else if (isSoon) {
      cardColor = Colors.orange[600]!;
      textColor = Colors.white;
      icon = Icons.schedule;
      statusText = 'Due Soon';
    } else {
      cardColor = Colors.green[600]!;
      textColor = Colors.white;
      icon = Icons.check_circle;
      statusText = 'Scheduled';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cardColor,
            cardColor.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cardColor.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: textColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pollution Check Reminder',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusText,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: textColor.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  isDue
                      ? 'Check Due Now!'
                      : 'Due in $daysUntil ${daysUntil == 1 ? 'day' : 'days'}',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ),
          if (_nextPollutionCheck != null) ...[
            const SizedBox(height: 12),
            Text(
              'Next check: ${DateFormat('MMM dd, yyyy').format(_nextPollutionCheck!)}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: textColor.withOpacity(0.8),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _markCheckAsDone,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Mark as Done'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textColor,
                    side: BorderSide(color: textColor, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _scheduleReminder(context),
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: const Text('Reschedule'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: cardColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPracticesCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.eco,
                  color: Colors.green[700],
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Good Practices',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ..._goodPractices.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tip,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.5,
                      ),
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
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article});

  final Map<String, String> article;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 8,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.article,
                  color: Colors.green[700],
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  article['title'] ?? '',
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            article['content'] ?? '',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
