import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/debug_logger.dart';
import '../l10n/app_localizations.dart';

/// Debug log panel that shows recent log entries
class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DebugLogger>(
      builder: (context, logger, _) {
        return Container(
          color: const Color(0xFF1E1E1E),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: const Color(0xFF2D2D2D),
                child: Row(
                  children: [
                    const Icon(Icons.bug_report, size: 14, color: Colors.orange),
                    const SizedBox(width: 6),
                    Text(
                      AppLocalizations.of(context).debugLog,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${logger.logs.length}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => logger.clear(),
                      child: const Icon(Icons.delete_sweep, size: 14, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              // Log entries
              Expanded(
                child: ListView.builder(
                  itemCount: logger.logs.length,
                  reverse: true,
                  itemBuilder: (context, index) {
                    final entry = logger.logs[logger.logs.length - 1 - index];
                    return _LogLine(entry: entry);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LogLine extends StatelessWidget {
  final DebugLogEntry entry;

  const _LogLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = _colorForLevel(entry.level);
    return InkWell(
      onTap: () {
        if (entry.detail != null && entry.detail!.isNotEmpty) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(entry.message, style: const TextStyle(fontSize: 14)),
              content: SingleChildScrollView(
                child: Text(
                  entry.detail!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(AppLocalizations.of(context).close),
                ),
              ],
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.timeStr,
              style: const TextStyle(
                color: Colors.white24,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 4),
            Text(
              entry.prefix,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                entry.message,
                style: TextStyle(
                  color: entry.level == LogLevel.error ? Colors.red[300] : Colors.white70,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
                maxLines: entry.detail != null ? 1 : 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return Colors.blue[300]!;
      case LogLevel.warn:
        return Colors.orange[300]!;
      case LogLevel.error:
        return Colors.red[300]!;
      case LogLevel.success:
        return Colors.green[300]!;
    }
  }
}
