import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/run_record.dart';

class RunHistoryRepository {
  static const String _keyHistory = 'lock_run_history';

  Future<List<RunRecord>> getRunHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? rawList = prefs.getStringList(_keyHistory);
    if (rawList == null || rawList.isEmpty) {
      return [];
    }

    final List<RunRecord> records = [];
    for (final itemStr in rawList) {
      try {
        final Map<String, dynamic> jsonMap = jsonDecode(itemStr) as Map<String, dynamic>;
        records.add(RunRecord.fromJson(jsonMap));
      } catch (_) {
        // Skip corrupted entries safely
      }
    }

    // Sort newest first
    records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return records;
  }

  Future<void> saveRun(RunRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final List<RunRecord> current = await getRunHistory();
    current.insert(0, record);

    final List<String> encodedList = current.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(_keyHistory, encodedList);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHistory);
  }
}
