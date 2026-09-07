class TrackerState {
  final bool isServiceInitialized;
  final bool isRunning;
  final bool isVolumeLocked;
  final int totalSeconds;
  final int currentLapSeconds;
  final List<int> laps;

  const TrackerState({
    this.isServiceInitialized = false,
    this.isRunning = false,
    this.isVolumeLocked = true, // Default to hijacked for laps
    this.totalSeconds = 0,
    this.currentLapSeconds = 0,
    this.laps = const [],
  });

  TrackerState copyWith({
    bool? isServiceInitialized,
    bool? isRunning,
    bool? isVolumeLocked,
    int? totalSeconds,
    int? currentLapSeconds,
    List<int>? laps,
  }) {
    return TrackerState(
      isServiceInitialized: isServiceInitialized ?? this.isServiceInitialized,
      isRunning: isRunning ?? this.isRunning,
      isVolumeLocked: isVolumeLocked ?? this.isVolumeLocked,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      currentLapSeconds: currentLapSeconds ?? this.currentLapSeconds,
      laps: laps ?? this.laps,
    );
  }

  int get currentLapIndex => laps.length;
}
