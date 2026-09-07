import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/native_tracker_service.dart';
import '../../../../core/utils/time_formatter.dart';
import '../../../history/data/run_history_repository.dart';
import '../../../history/domain/models/run_record.dart';
import '../../../history/presentation/screens/history_screen.dart';
import '../../domain/tracker_state.dart';

class MainTrackerScreen extends StatefulWidget {
  final NativeTrackerService trackerService;
  final RunHistoryRepository historyRepository;

  const MainTrackerScreen({
    super.key,
    required this.trackerService,
    required this.historyRepository,
  });

  @override
  State<MainTrackerScreen> createState() => _MainTrackerScreenState();
}

class _MainTrackerScreenState extends State<MainTrackerScreen>
    with TickerProviderStateMixin {
  TrackerState _state = const TrackerState();
  late PageController _pageController;
  int _currentPage = 0;
  bool _isLockScreenActive = true;

  // Animations
  late AnimationController _lapBounceController;
  late Animation<double> _lapBounceAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _state = widget.trackerService.currentState;

    // Lap count bounce animation
    _lapBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _lapBounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 0.95), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 35),
    ]).animate(CurvedAnimation(
      parent: _lapBounceController,
      curve: Curves.easeOut,
    ));

    // Subtle breathing pulse for running state
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-init native service
    widget.trackerService.initializeService();

    widget.trackerService.stateStream.listen((state) {
      if (mounted) {
        final oldLapCount = _state.laps.length;
        setState(() => _state = state);
        if (state.laps.length != oldLapCount) {
          _lapBounceController.forward(from: 0.0);
        }
        if (state.isRunning && !_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        } else if (!state.isRunning && _pulseController.isAnimating) {
          _pulseController.stop();
          _pulseController.value = 0.0;
        }
      }
    });

    widget.trackerService.onLapRecorded = (lapNum, lapDur, totalDur) {};
    widget.trackerService.onLapDeleted = (restored, lapNum) {};
  }

  @override
  void dispose() {
    _pageController.dispose();
    _lapBounceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // --- Handlers ---

  Future<void> _handleToggleLockScreen() async {
    HapticFeedback.mediumImpact();
    setState(() => _isLockScreenActive = !_isLockScreenActive);
    await widget.trackerService.initializeService();
    await widget.trackerService.requestNotificationPermission();
    await widget.trackerService.setLockScreenMode(_isLockScreenActive);
    await widget.trackerService.setKeepScreenOn(_isLockScreenActive);
  }

  Future<void> _handleStartPause() async {
    HapticFeedback.mediumImpact();
    if (!_state.isServiceInitialized) {
      await widget.trackerService.initializeService();
    }
    await widget.trackerService.toggleTimer();
  }

  Future<void> _handleAddLap() async {
    HapticFeedback.heavyImpact();
    if (!_state.isRunning) {
      await widget.trackerService.toggleTimer();
    }
    await widget.trackerService.triggerLap();
  }

  Future<void> _handleReduceLap() async {
    HapticFeedback.lightImpact();
    await widget.trackerService.deleteLastLap();
  }

  Future<void> _handleFinishRun() async {
    HapticFeedback.mediumImpact();
    final finishedState = await widget.trackerService.finishRun();
    if (finishedState.totalSeconds > 0) {
      final runRecord = RunRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        totalDurationSeconds: finishedState.totalSeconds,
        laps: finishedState.laps,
      );
      await widget.historyRepository.saveRun(runRecord);
    }
  }

  Future<void> _handleVolumeLockToggle() async {
    HapticFeedback.selectionClick();
    await widget.trackerService.toggleVolumeLock();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _currentPage = i),
              physics: const BouncingScrollPhysics(),
              children: [
                _buildTrackerPage(),
                HistoryPageEmbed(repository: widget.historyRepository),
              ],
            ),
          ),
          // Page indicator dots
          _buildPageIndicator(),
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
        top: 6,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(2, (i) {
          final isActive = i == _currentPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? AppColors.accent : AppColors.textMuted,
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTrackerPage() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Top bar: Lock toggle + Total time
            _buildTopBar(),
            const SizedBox(height: 24),
            // Hero: Current lap number + lap time
            _buildLapHero(),
            const SizedBox(height: 20),
            // Lap list (hero element, takes remaining space)
            Expanded(child: _buildLapList()),
            const SizedBox(height: 16),
            // Bottom controls
            _buildControls(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Volume lock toggle
        GestureDetector(
          onTap: _handleVolumeLockToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _state.isVolumeLocked
                  ? AppColors.accent.withValues(alpha: 0.12)
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _state.isVolumeLocked
                    ? AppColors.accent.withValues(alpha: 0.4)
                    : AppColors.border,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _state.isVolumeLocked
                      ? Icons.lock_rounded
                      : Icons.lock_open_rounded,
                  size: 14,
                  color: _state.isVolumeLocked
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _state.isVolumeLocked ? 'VOL LOCKED' : 'VOL FREE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: _state.isVolumeLocked
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Lock screen toggle
        GestureDetector(
          onTap: _handleToggleLockScreen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _isLockScreenActive
                  ? AppColors.positive.withValues(alpha: 0.1)
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isLockScreenActive
                    ? AppColors.positive.withValues(alpha: 0.3)
                    : AppColors.border,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isLockScreenActive
                        ? AppColors.positive
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isLockScreenActive ? 'SCREEN ON' : 'SCREEN OFF',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: _isLockScreenActive
                        ? AppColors.positive
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLapHero() {
    return Column(
      children: [
        // Total time - small label
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_state.isRunning)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.positive.withValues(
                        alpha: _pulseAnimation.value,
                      ),
                    ),
                  ),
                Text(
                  TimeFormatter.formatSeconds(_state.totalSeconds),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                    color: _state.isRunning
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),

        // Current lap number — big hero
        ScaleTransition(
          scale: _lapBounceAnimation,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${_state.currentLapIndex}',
              style: const TextStyle(
                fontSize: 200,
                fontWeight: FontWeight.w900,
                height: 0.92,
                color: AppColors.textPrimary,
                letterSpacing: -6,
              ),
            ),
          ),
        ),

        // Label
        Text(
          _state.currentLapIndex == 1 ? 'LAP' : 'LAPS',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 4.0,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 6),

        // Current lap time
        Text(
          TimeFormatter.formatLapTime(_state.currentLapSeconds),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w300,
            letterSpacing: 2.0,
            color: AppColors.accent.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildLapList() {
    if (_state.laps.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 32,
              color: AppColors.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              'No laps recorded',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textMuted.withValues(alpha: 0.7),
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Press + or Volume Up to add a lap',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    // Find best lap
    final bestLapTime = _state.laps.reduce((a, b) => a < b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_state.laps.length} ${_state.laps.length == 1 ? 'LAP' : 'LAPS'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.textMuted,
                ),
              ),
              Text(
                'BEST ${TimeFormatter.formatLapTime(bestLapTime)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppColors.positive,
                ),
              ),
            ],
          ),
        ),
        // Divider
        Container(height: 0.5, color: AppColors.border),
        // List
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            reverse: true,
            itemCount: _state.laps.length,
            itemBuilder: (context, index) {
              final lapDuration = _state.laps[index];
              final isBest = lapDuration == bestLapTime;

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.5),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Lap number
                    SizedBox(
                      width: 48,
                      child: Text(
                        'L${index + 1}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isBest
                              ? AppColors.positive
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    // Lap time
                    Expanded(
                      child: Text(
                        TimeFormatter.formatLapTime(lapDuration),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.5,
                          fontFamily: 'monospace',
                          color: isBest
                              ? AppColors.positive
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    // Best badge
                    if (isBest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.positive.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'BEST',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: AppColors.positive,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Column(
      children: [
        // Top row: [-] (Red) and [+] (Green) dividing the horizontal space
        Row(
          children: [
            // Minus button (red)
            Expanded(
              child: _buildWideActionButton(
                icon: Icons.remove_rounded,
                onTap: _state.laps.isNotEmpty ? _handleReduceLap : null,
                color: AppColors.danger,
                height: 76,
                iconSize: 46,
              ),
            ),

            const SizedBox(width: 14),

            // Plus button (green)
            Expanded(
              child: _buildWideActionButton(
                icon: Icons.add_rounded,
                onTap: _handleAddLap,
                color: AppColors.positive,
                height: 76,
                iconSize: 46,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Start / Pause / Resume button
        _buildMainActionButton(),

        // Finish button — only visible when there's data
        if (_state.totalSeconds > 0) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _handleFinishRun,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.stop_rounded,
                    size: 16,
                    color: AppColors.danger.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'FINISH RUN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                      color: AppColors.danger.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMainActionButton() {
    final isRunning = _state.isRunning;
    final hasTime = _state.totalSeconds > 0;

    String label;
    IconData icon;
    if (isRunning) {
      label = 'PAUSE';
      icon = Icons.pause_rounded;
    } else if (hasTime) {
      label = 'RESUME';
      icon = Icons.play_arrow_rounded;
    } else {
      label = 'START';
      icon = Icons.play_arrow_rounded;
    }

    return _MinimalPressButton(
      onTap: _handleStartPause,
      child: Container(
        height: 52,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isRunning
              ? AppColors.textPrimary.withValues(alpha: 0.1)
              : AppColors.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRunning
                ? AppColors.textSecondary.withValues(alpha: 0.3)
                : AppColors.accent.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: isRunning ? AppColors.textPrimary : AppColors.accent,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
                color: isRunning ? AppColors.textPrimary : AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideActionButton({
    required IconData icon,
    required VoidCallback? onTap,
    required Color color,
    double height = 76,
    double iconSize = 46,
  }) {
    final isEnabled = onTap != null;

    return _MinimalPressButton(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: isEnabled
              ? color.withValues(alpha: 0.14)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isEnabled
                ? color.withValues(alpha: 0.5)
                : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: isEnabled
                ? color
                : AppColors.textMuted.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

/// A minimal press-scale button wrapper.
class _MinimalPressButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _MinimalPressButton({required this.onTap, required this.child});

  @override
  State<_MinimalPressButton> createState() => _MinimalPressButtonState();
}

class _MinimalPressButtonState extends State<_MinimalPressButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.onTap != null ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
