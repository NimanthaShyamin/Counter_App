import 'package:intl/intl.dart';

class RunRecord {
  final String id;
  final DateTime timestamp;
  final int totalDurationSeconds;
  final List<int> laps;

  const RunRecord({
    required this.id,
    required this.timestamp,
    required this.totalDurationSeconds,
    required this.laps,
  });

  String get formattedDate {
    return DateFormat('MMM d, yyyy • h:mm a').format(timestamp);
  }

  int get lapCount => laps.length;

  int get averageLapSeconds {
    if (laps.isEmpty) return totalDurationSeconds;
    final int sum = laps.fold(0, (a, b) => a + b);
    return (sum / laps.length).round();
  }

  int get bestLapSeconds {
    if (laps.isEmpty) return totalDurationSeconds;
    return laps.reduce((curr, next) => curr < next ? curr : next);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'totalDurationSeconds': totalDurationSeconds,
      'laps': laps,
    };
  }

  factory RunRecord.fromJson(Map<String, dynamic> json) {
    return RunRecord(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      totalDurationSeconds: (json['totalDurationSeconds'] as num).toInt(),
      laps: (json['laps'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? [],
    );
  }
}
