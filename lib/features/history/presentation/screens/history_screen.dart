import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/time_formatter.dart';
import '../../data/run_history_repository.dart';
import '../../domain/models/run_record.dart';

/// Standalone history screen (for backwards compatibility / Navigator.push usage).
class HistoryScreen extends StatelessWidget {
  final RunHistoryRepository repository;

  const HistoryScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('HISTORY'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textSecondary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: HistoryPageEmbed(repository: repository),
    );
  }
}

/// Embeddable history page — used inside the PageView on the main tracker screen.
class HistoryPageEmbed extends StatefulWidget {
  final RunHistoryRepository repository;

  const HistoryPageEmbed({super.key, required this.repository});

  @override
  State<HistoryPageEmbed> createState() => _HistoryPageEmbedState();
}

class _HistoryPageEmbedState extends State<HistoryPageEmbed> {
  List<RunRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final list = await widget.repository.getRunHistory();
    if (mounted) {
      setState(() {
        _records = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
        ),
        title: const Text(
          'Clear History?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        content: const Text(
          'This will permanently delete all saved runs.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.repository.clearHistory();
      await _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2,
        ),
      );
    }

    if (_records.isEmpty) {
      return _buildEmptyState();
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'HISTORY',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                    color: AppColors.textPrimary,
                  ),
                ),
                GestureDetector(
                  onTap: _confirmClearHistory,
                  child: Text(
                    'CLEAR',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: AppColors.danger.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 24)),
          // List
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              itemCount: _records.length,
              itemBuilder: (context, index) => _buildRunCard(_records[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            size: 36,
            color: AppColors.textMuted.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 14),
          const Text(
            'No runs yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Finish a run to see it here',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textMuted.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunCard(RunRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date + Total time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                record.formattedDate,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                TimeFormatter.formatSeconds(record.totalDurationSeconds),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 0.5, color: AppColors.border),
          const SizedBox(height: 12),
          // Metrics row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetric('LAPS', '${record.lapCount}', AppColors.textPrimary),
              _buildMetric('AVG', TimeFormatter.formatLapTime(record.averageLapSeconds), AppColors.accent),
              _buildMetric('BEST', TimeFormatter.formatLapTime(record.bestLapSeconds), AppColors.positive),
            ],
          ),
          // Lap splits
          if (record.laps.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: List.generate(record.laps.length, (i) {
                final lapTime = record.laps[i];
                final isBest = lapTime == record.bestLapSeconds;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isBest
                        ? AppColors.positive.withValues(alpha: 0.08)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'L${i + 1}: ${TimeFormatter.formatLapTime(lapTime)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                      color: isBest ? AppColors.positive : AppColors.textSecondary,
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
            color: color,
          ),
        ),
      ],
    );
  }
}
