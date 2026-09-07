import 'package:flutter_test/flutter_test.dart';
import 'package:lock_run_tracker/core/services/native_tracker_service.dart';
import 'package:lock_run_tracker/features/history/data/run_history_repository.dart';
import 'package:lock_run_tracker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Renders Pulse Run screen with Lap #0 and Start Run', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = NativeTrackerService();
    final repository = RunHistoryRepository();

    await tester.pumpWidget(LockRunTrackerApp(
      trackerService: service,
      historyRepository: repository,
    ));

    expect(find.text('PULSE RUN'), findsOneWidget);
    expect(find.text('START RUN'), findsOneWidget);
    expect(find.text('#0'), findsOneWidget);
    expect(find.text('ADD LAP'), findsOneWidget);
  });
}
