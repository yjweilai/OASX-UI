import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/home/models/config_model.dart';

/// Displays an 8-day (today + next 7 days) scheduled task count distribution card.
class TaskDateDistributionCard extends StatelessWidget {
  const TaskDateDistributionCard({
    super.key,
    required this.scriptModel,
    required this.selectedDate,
    required this.onSelectDate,
  });

  final ScriptModel scriptModel;
  final DateTime? selectedDate;
  final ValueChanged<DateTime?> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Obx(() {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final days = List<DateTime>.generate(
            8,
            (index) => today.add(Duration(days: index)),
          );
          final counts = List<int>.filled(8, 0);
          var totalInWindow = 0;

          void countTimeText(String raw) {
            final parsed = parseTaskNextRunDate(raw, now: now);
            if (parsed == null) {
              counts[0]++;
              totalInWindow++;
              return;
            }
            final taskDay = DateTime(parsed.year, parsed.month, parsed.day);
            final diff = taskDay.difference(today).inDays;
            if (diff <= 0) {
              counts[0]++;
              totalInWindow++;
            } else if (diff < 8) {
              counts[diff]++;
              totalInWindow++;
            }
          }

          if (scriptModel.runningTask.value.taskName.value.trim().isNotEmpty) {
            counts[0]++;
            totalInWindow++;
          }
          for (final item in scriptModel.pendingTaskList) {
            if (item.taskName.value.trim().isNotEmpty) {
              countTimeText(item.nextRun.value);
            }
          }
          for (final item in scriptModel.waitingTaskList) {
            if (item.taskName.value.trim().isNotEmpty) {
              countTimeText(item.nextRun.value);
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '任务日期分布',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '未来7天',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (selectedDate != null) ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => onSelectDate(null),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          '清除筛选',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    '共$totalInWindow项',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: List.generate(days.length, (index) {
                  final day = days[index];
                  final count = counts[index];
                  final isSelected = selectedDate != null &&
                      selectedDate!.year == day.year &&
                      selectedDate!.month == day.month &&
                      selectedDate!.day == day.day;
                  final label = index == 0 ? '今天' : _weekdayLabel(day.weekday);

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: index == 0 ? 0 : 4,
                        right: index == days.length - 1 ? 0 : 4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isSelected
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Material(
                            color: isSelected
                                ? scheme.primary.withValues(
                                    alpha: isDark ? 0.28 : 0.14,
                                  )
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.10)
                                    : Colors.black.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(10),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () =>
                                  onSelectDate(isSelected ? null : day),
                              child: Container(
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? scheme.primary.withValues(alpha: 0.6)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Text(
                                  '$count',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: count > 0 || isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isSelected
                                        ? scheme.primary
                                        : (count > 0
                                            ? scheme.onSurface
                                            : scheme.onSurfaceVariant),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 4),
            ],
          );
        }),
      ),
    );
  }

  String _weekdayLabel(int weekday) {
    return switch (weekday) {
      DateTime.monday => '周一',
      DateTime.tuesday => '周二',
      DateTime.wednesday => '周三',
      DateTime.thursday => '周四',
      DateTime.friday => '周五',
      DateTime.saturday => '周六',
      DateTime.sunday => '周日',
      _ => '',
    };
  }
}

/// Parses OAS task `nextRun` strings (e.g. `2026-11-19 08:10:00` or `11-19 08:10`).
DateTime? parseTaskNextRunDate(String raw, {DateTime? now}) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final normalized = text.replaceFirst(' ', 'T');
  final direct = DateTime.tryParse(normalized);
  if (direct != null) {
    return direct;
  }
  final reference = now ?? DateTime.now();
  final mdMatch = RegExp(r'^(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})')
      .firstMatch(text);
  if (mdMatch != null) {
    final month = int.tryParse(mdMatch.group(1)!);
    final day = int.tryParse(mdMatch.group(2)!);
    final hour = int.tryParse(mdMatch.group(3)!);
    final minute = int.tryParse(mdMatch.group(4)!);
    if (month != null && day != null && hour != null && minute != null) {
      var candidate = DateTime(reference.year, month, day, hour, minute);
      if (candidate.isBefore(reference.subtract(const Duration(days: 180)))) {
        candidate = DateTime(reference.year + 1, month, day, hour, minute);
      }
      return candidate;
    }
  }
  final hmMatch = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(text);
  if (hmMatch != null) {
    final hour = int.tryParse(hmMatch.group(1)!);
    final minute = int.tryParse(hmMatch.group(2)!);
    final second = int.tryParse(hmMatch.group(3) ?? '0') ?? 0;
    if (hour != null && minute != null) {
      return DateTime(
        reference.year,
        reference.month,
        reference.day,
        hour,
        minute,
        second,
      );
    }
  }
  return null;
}
