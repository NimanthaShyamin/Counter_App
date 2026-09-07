import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/services/native_tracker_service.dart';
import 'core/theme/app_theme.dart';
import 'features/history/data/run_history_repository.dart';
import 'features/tracker/presentation/screens/main_tracker_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set immersive dark status bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final nativeService = NativeTrackerService();
  final historyRepository = RunHistoryRepository();

  runApp(LockRunTrackerApp(
    trackerService: nativeService,
    historyRepository: historyRepository,
  ));
}

class LockRunTrackerApp extends StatelessWidget {
  final NativeTrackerService trackerService;
  final RunHistoryRepository historyRepository;

  const LockRunTrackerApp({
    super.key,
    required this.trackerService,
    required this.historyRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lock Run Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: MainTrackerScreen(
        trackerService: trackerService,
        historyRepository: historyRepository,
      ),
    );
  }
}
