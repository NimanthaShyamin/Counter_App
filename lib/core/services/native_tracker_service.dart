import 'dart:async';
import 'package:flutter/services.dart';
import '../../features/tracker/domain/tracker_state.dart';

class NativeTrackerService {
  static const MethodChannel _channel = MethodChannel('com.lockrun.tracker/service');

  final StreamController<TrackerState> _stateController = StreamController<TrackerState>.broadcast();
  Stream<TrackerState> get stateStream => _stateController.stream;

  TrackerState _currentState = const TrackerState();
  TrackerState get currentState => _currentState;

  void Function(int lapNumber, int lapDuration, int totalDuration)? onLapRecorded;
  void Function(int restoredTime, int currentLapNumber)? onLapDeleted;

  NativeTrackerService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onTick':
        final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
        final int total = (args['totalSeconds'] as num?)?.toInt() ?? _currentState.totalSeconds;
        final int lap = (args['lapSeconds'] as num?)?.toInt() ?? _currentState.currentLapSeconds;
        _updateState(_currentState.copyWith(
          totalSeconds: total,
          currentLapSeconds: lap,
        ));
        break;

      case 'onStateChanged':
        final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
        final bool isRunning = args['isRunning'] as bool? ?? _currentState.isRunning;
        final bool isLocked = args['isVolumeLocked'] as bool? ?? _currentState.isVolumeLocked;
        final int total = (args['totalSeconds'] as num?)?.toInt() ?? _currentState.totalSeconds;
        final int lap = (args['currentLapSeconds'] as num?)?.toInt() ?? _currentState.currentLapSeconds;
        final List<dynamic>? rawLaps = args['laps'] as List<dynamic>?;
        final List<int> laps = rawLaps != null ? rawLaps.map((e) => (e as num).toInt()).toList() : _currentState.laps;

        _updateState(_currentState.copyWith(
          isServiceInitialized: true,
          isRunning: isRunning,
          isVolumeLocked: isLocked,
          totalSeconds: total,
          currentLapSeconds: lap,
          laps: laps,
        ));
        break;

      case 'onLapRecorded':
        final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
        final int lapNumber = (args['lapNumber'] as num?)?.toInt() ?? 0;
        final int lapTime = (args['lapTime'] as num?)?.toInt() ?? 0;
        final int totalTime = (args['totalTime'] as num?)?.toInt() ?? 0;
        
        final List<int> updatedLaps = List<int>.from(_currentState.laps)..add(lapTime);
        _updateState(_currentState.copyWith(
          currentLapSeconds: 0,
          totalSeconds: totalTime,
          laps: updatedLaps,
        ));

        HapticFeedback.heavyImpact();
        onLapRecorded?.call(lapNumber, lapTime, totalTime);
        break;

      case 'onLapDeleted':
        final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
        final int restoredTime = (args['restoredTime'] as num?)?.toInt() ?? 0;
        final int lapNum = (args['currentLapNumber'] as num?)?.toInt() ?? _currentState.currentLapIndex;
        final int total = (args['totalSeconds'] as num?)?.toInt() ?? _currentState.totalSeconds;
        final int lapSec = (args['currentLapSeconds'] as num?)?.toInt() ?? _currentState.currentLapSeconds;
        final List<dynamic>? rawLaps = args['laps'] as List<dynamic>?;
        final List<int> updatedLaps = rawLaps != null 
            ? rawLaps.map((e) => (e as num).toInt()).toList() 
            : (_currentState.laps.isNotEmpty ? (List<int>.from(_currentState.laps)..removeLast()) : []);

        _updateState(_currentState.copyWith(
          totalSeconds: total,
          currentLapSeconds: lapSec,
          laps: updatedLaps,
        ));
        HapticFeedback.selectionClick();
        onLapDeleted?.call(restoredTime, lapNum);
        break;

      case 'onServiceStopped':
        _updateState(const TrackerState(isServiceInitialized: false));
        break;
    }
  }

  void _updateState(TrackerState newState) {
    _currentState = newState;
    _stateController.add(_currentState);
  }

  /// Initialize the native background service & MediaSession in idle state
  Future<bool> initializeService() async {
    try {
      final bool result = await _channel.invokeMethod<bool>('initializeService') ?? false;
      if (result) {
        _updateState(_currentState.copyWith(isServiceInitialized: true));
      }
      return result;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('Failed to initialize native service: ${e.message}');
      return false;
    }
  }

  /// Explicitly request notification permission from the system
  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('Failed to request notification permission: ${e.message}');
    }
  }

  /// Enable or disable the Show Over Lock Screen overlay
  Future<void> setLockScreenMode(bool enabled) async {
    try {
      await _channel.invokeMethod('setLockScreenMode', {'enabled': enabled});
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('Failed to set lock screen mode: ${e.message}');
    }
  }

  /// Enable or disable keep screen on flag
  Future<void> setKeepScreenOn(bool enabled) async {
    try {
      await _channel.invokeMethod('setKeepScreenOn', {'enabled': enabled});
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('Failed to set keep screen on: ${e.message}');
    }
  }

  /// Toggle start/pause on the native timer
  Future<void> toggleTimer() async {
    try {
      await _channel.invokeMethod('toggleTimer');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('Failed to toggle timer: ${e.message}');
    }
  }

  /// Trigger a lap
  Future<void> triggerLap() async {
    try {
      await _channel.invokeMethod('triggerLap');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('Failed to trigger lap: ${e.message}');
    }
  }

  /// Delete/reduce the last lap and back 1 in lap count
  Future<bool> deleteLastLap() async {
    try {
      final bool result = await _channel.invokeMethod<bool>('deleteLastLap') ?? false;
      return result;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('Failed to delete lap: ${e.message}');
      return false;
    }
  }

  /// Toggle physical volume button hijacking (Locked: Vol = Lap, Unlocked: Vol = Volume)
  Future<void> toggleVolumeLock() async {
    try {
      await _channel.invokeMethod('toggleVolumeLock');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('Failed to toggle volume lock: ${e.message}');
    }
  }

  /// Finish the current workout session and stop the foreground service
  Future<TrackerState> finishRun() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod<Map<dynamic, dynamic>>('finishRun');
      final finishedState = _currentState;
      _updateState(const TrackerState(isServiceInitialized: false));
      if (result != null) {
        final int total = (result['totalSeconds'] as num?)?.toInt() ?? finishedState.totalSeconds;
        final List<dynamic>? rawLaps = result['laps'] as List<dynamic>?;
        final List<int> laps = rawLaps != null
            ? rawLaps.map((e) => (e as num).toInt()).toList()
            : [
                ...finishedState.laps,
                if (finishedState.currentLapSeconds > 0) finishedState.currentLapSeconds,
              ];
        return finishedState.copyWith(totalSeconds: total, laps: laps);
      }
      final fallbackLaps = [
        ...finishedState.laps,
        if (finishedState.currentLapSeconds > 0) finishedState.currentLapSeconds,
      ];
      return finishedState.copyWith(laps: fallbackLaps);
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('Failed to finish run: ${e.message}');
      final finished = _currentState;
      _updateState(const TrackerState(isServiceInitialized: false));
      final fallbackLaps = [
        ...finished.laps,
        if (finished.currentLapSeconds > 0) finished.currentLapSeconds,
      ];
      return finished.copyWith(laps: fallbackLaps);
    }
  }

  void dispose() {
    _stateController.close();
  }
}
