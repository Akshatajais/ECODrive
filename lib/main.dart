import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/dashboard_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/graphs_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/camera_feed_screen.dart';
import 'providers/driver_score_provider.dart';
import 'providers/camera_stream_provider.dart';
import 'providers/evidence_capture_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  // Note: You'll need to add firebase_options.dart after running:
  // flutterfire configure
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // If Firebase is not configured, the app will use mock data
    debugPrint('Firebase initialization error: $e');
  }
  
  runApp(const SmartVehicleEmissionMonitorApp());
}

class SmartVehicleEmissionMonitorApp extends StatelessWidget {
  const SmartVehicleEmissionMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DriverScoreProvider()),
        ChangeNotifierProvider(create: (_) => CameraStreamProvider()),
        Provider(
          create: (_) => EvidenceCaptureProvider(),
        ),
        ProxyProvider3<DriverScoreProvider, CameraStreamProvider,
            EvidenceCaptureProvider, EvidenceCaptureProvider>(
          update: (context, driver, camera, evidence, prev) {
            evidence.maybeCapture(driver: driver, camera: camera);
            return evidence;
          },
        ),
      ],
      child: MaterialApp(
        title: 'EcoDrive',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.green,
          primaryColor: Colors.green[600],
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          textTheme: GoogleFonts.poppinsTextTheme(),
          cardTheme: const CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
          appBarTheme: AppBarTheme(
            elevation: 0,
            centerTitle: false,
            backgroundColor: Colors.green[600],
            foregroundColor: Colors.white,
            titleTextStyle: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        home: const MainNavigationScreen(),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const CameraFeedScreen(),
    const AlertsScreen(),
    const GraphsScreen(),
    InsightsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: Colors.green[600],
          unselectedItemColor: Colors.grey[600],
          selectedFontSize: 12,
          unselectedFontSize: 12,
          elevation: 8,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.videocam),
              label: 'Camera',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications),
              label: 'Alerts',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.analytics),
              label: 'Graphs',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book),
              label: 'Insights',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
