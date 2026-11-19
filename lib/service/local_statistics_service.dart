import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';

/// Tracks script runtime, task runs, and battle counts locally from WebSocket
/// events so statistics work even when the OAS backend does not expose `/stats`.
class LocalStatisticsService extends GetxService {
  static const String _kStoragePrefix = 'local_stats_v1::';
  static const int _kMaxRetainedDays = 14;
  static final RegExp _kBattleLogPattern = RegExp(
    r'(?:Current\s+count\s*[:=]|General\s+battle\s+start|Start\s+battle|Battle\s+result|BATTLE_WIN|VICTORY|战斗胜利|战斗失败|第\s*\d+\s*次战斗)',
    caseSensitive: false,
  );

  final GetStorage _storage = GetStorage();

  /// Monotonic counter incremented whenever local stats change.
  final revision = 0.obs;

  /// Per-script persisted day maps: scriptName -> dateKey -> _LocalDayBucket.
  final Map<String, Map<String, _LocalDayBucket>> _store = {};

  /// Per-script live session trackers.
  final Map<String, _ScriptLiveSession> _sessions = {};

  Timer? _tickTimer;
  int _tickCount = 0;

  @override
  void onInit() {
    _tickTimer = Timer.periodic(const Duration(seconds: 3), (_) => _onTick());
    super.onInit();
  }

  @override
  void onClose() {
    _tickTimer?.cancel();
    _tickTimer = null;
    for (final scriptName in _sessions.keys.toList()) {
      _flushSession(scriptName, closeActiveRun: true);
    }
    super.onClose();
  }

  /// Updates running/stopped state for a script from WebSocket state updates.
  void recordState(String scriptName, ScriptState state) {
    final name = scriptName.trim();
    if (name.isEmpty) {
      return;
    }
    final session = _sessionFor(name);
    final now = DateTime.now();
    final isNowRunning = state == ScriptState.running;

    if (isNowRunning && !session.isRunning) {
      session.isRunning = true;
      session.lastRuntimeTick = now;
      _ensureDayBucket(name, _dateKey(now));
      _notifyChanged();
    } else if (!isNowRunning && session.isRunning) {
      _accumulateRuntime(name, session, now);
      _closeActiveTaskRun(name, session, now);
      session.isRunning = false;
      session.lastRuntimeTick = null;
      _persistScript(name);
      _notifyChanged();
    }
  }

  /// Updates the active running task from WebSocket schedule updates.
  void recordRunningTask(String scriptName, String taskName) {
    final name = scriptName.trim();
    if (name.isEmpty) {
      return;
    }
    final normalizedTask = taskName.trim();
    final session = _sessionFor(name);
    final now = DateTime.now();

    if (session.activeTaskName == normalizedTask) {
      return;
    }

    if (session.isRunning) {
      _accumulateRuntime(name, session, now);
    }
    _closeActiveTaskRun(name, session, now);

    if (normalizedTask.isNotEmpty) {
      session.activeTaskName = normalizedTask;
      session.activeTaskStartTime = now;
      session.activeTaskBattles = 0;
      if (!session.isRunning) {
        session.isRunning = true;
        session.lastRuntimeTick = now;
      }
      _ensureDayBucket(name, _dateKey(now));
    }
    _persistScript(name);
    _notifyChanged();
  }

  /// Inspects incoming WebSocket log lines to count battle completions/starts.
  void recordLogLine(String scriptName, String rawLine) {
    final name = scriptName.trim();
    if (name.isEmpty || rawLine.trim().isEmpty) {
      return;
    }
    if (!_kBattleLogPattern.hasMatch(rawLine)) {
      return;
    }
    final session = _sessionFor(name);
    final now = DateTime.now();
    if (session.lastBattleAt != null &&
        now.difference(session.lastBattleAt!).inMilliseconds < 2000) {
      return;
    }
    session.lastBattleAt = now;

    if (session.activeTaskName.isNotEmpty) {
      session.activeTaskBattles++;
    } else {
      final bucket = _ensureDayBucket(name, _dateKey(now));
      bucket.extraBattleCount++;
    }
    _notifyChanged();
  }


  /// Clears all locally persisted and in-memory statistics for one script.
  void clearScriptStatistics(String scriptName) {
    final name = scriptName.trim();
    if (name.isEmpty) {
      return;
    }
    _store.remove(name);
    final session = _sessions[name];
    if (session != null) {
      session.activeTaskName = '';
      session.activeTaskStartTime = null;
      session.activeTaskBattles = 0;
      session.lastBattleAt = null;
      if (session.isRunning) {
        session.lastRuntimeTick = DateTime.now();
      }
    }
    _storage.remove('$_kStoragePrefix$name');
    _notifyChanged();
  }

  /// Returns available date keys (newest first), always including today.
  List<String> getAvailableDates(String scriptName) {
    final name = scriptName.trim();
    if (name.isEmpty) {
      return const [];
    }
    final days = _daysFor(name);
    final todayKey = _dateKey(DateTime.now());
    final keys = <String>{todayKey, ...days.keys}.toList()
      ..sort((a, b) => b.compareTo(a));
    return keys;
  }

  /// Builds a [ScriptStatisticsDay] snapshot for the given script and date.
  ScriptStatisticsDay getDayStatistics(String scriptName, String dateKey) {
    final name = scriptName.trim();
    final now = DateTime.now();
    final todayKey = _dateKey(now);
    final days = _daysFor(name);
    final bucket = days[dateKey];
    final session = _sessions[name];

    var totalRuntime = bucket?.totalRuntimeSeconds ?? 0.0;
    var totalTaskRuns = 0;
    var totalBattles = bucket?.extraBattleCount ?? 0;

    final taskBuilders = <String, List<_LocalRunEntry>>{};
    if (bucket != null) {
      for (final entry in bucket.taskRuns.entries) {
        taskBuilders[entry.key] = List<_LocalRunEntry>.from(entry.value);
      }
    }

    // Merge live in-progress session into today's snapshot.
    if (dateKey == todayKey && session != null) {
      if (session.isRunning && session.lastRuntimeTick != null) {
        final delta =
            now.difference(session.lastRuntimeTick!).inMilliseconds / 1000.0;
        if (delta > 0 && delta < 3600) {
          totalRuntime += delta;
        }
      }
      if (session.activeTaskName.isNotEmpty &&
          session.activeTaskStartTime != null) {
        final liveDuration = now
                .difference(session.activeTaskStartTime!)
                .inMilliseconds /
            1000.0;
        final liveEntry = _LocalRunEntry(
          startTime: session.activeTaskStartTime!,
          endTime: now,
          durationSeconds: liveDuration < 0 ? 0 : liveDuration,
          battleCount: session.activeTaskBattles,
        );
        taskBuilders
            .putIfAbsent(session.activeTaskName, () => <_LocalRunEntry>[])
            .add(liveEntry);
      }
    }

    final tasks = <String, ScriptTaskStatistics>{};
    for (final entry in taskBuilders.entries) {
      final runs = entry.value;
      if (runs.isEmpty) {
        continue;
      }
      var taskDuration = 0.0;
      var taskBattles = 0;
      final records = <ScriptTaskRunRecord>[];
      DateTime? latestStart;

      for (final run in runs) {
        taskDuration += run.durationSeconds;
        taskBattles += run.battleCount;
        if (latestStart == null || run.startTime.isAfter(latestStart)) {
          latestStart = run.startTime;
        }
        records.add(
          ScriptTaskRunRecord(
            startTimeText: _formatDateTime(run.startTime),
            endTimeText: _formatDateTime(run.endTime),
            durationSeconds: run.durationSeconds,
            battle: run.battleCount > 0
                ? ScriptStatisticsBattleSummary(
                    count: run.battleCount,
                    avgDurationSeconds: run.durationSeconds / run.battleCount,
                  )
                : null,
            startTime: run.startTime,
            endTime: run.endTime,
          ),
        );
      }

      totalTaskRuns += runs.length;
      totalBattles += taskBattles;
      tasks[entry.key] = ScriptTaskStatistics(
        runCount: runs.length,
        totalDurationSeconds: taskDuration,
        battle: taskBattles > 0
            ? ScriptStatisticsBattleSummary(
                count: taskBattles,
                avgDurationSeconds: taskDuration / taskBattles,
              )
            : null,
        runs: records,
        latestRunStartTime: latestStart,
      );
    }

    return ScriptStatisticsDay(
      scriptName: name,
      dateKey: dateKey,
      totalRuntimeSeconds: totalRuntime,
      totalTaskRunCount: totalTaskRuns,
      totalBattleCount: totalBattles,
      tasks: tasks,
    );
  }

  void _onTick() {
    _tickCount++;
    final now = DateTime.now();
    var anyRunning = false;
    for (final entry in _sessions.entries) {
      final session = entry.value;
      if (session.isRunning) {
        anyRunning = true;
        _accumulateRuntime(entry.key, session, now);
        if (_tickCount % 5 == 0) {
          _persistScript(entry.key);
        }
      }
    }
    if (anyRunning) {
      _notifyChanged();
    }
  }

  void _flushSession(String scriptName, {required bool closeActiveRun}) {
    final session = _sessions[scriptName];
    if (session == null) {
      return;
    }
    final now = DateTime.now();
    if (session.isRunning) {
      _accumulateRuntime(scriptName, session, now);
    }
    if (closeActiveRun) {
      _closeActiveTaskRun(scriptName, session, now);
    }
    _persistScript(scriptName);
  }

  void _accumulateRuntime(
    String scriptName,
    _ScriptLiveSession session,
    DateTime now,
  ) {
    final last = session.lastRuntimeTick;
    session.lastRuntimeTick = now;
    if (last == null) {
      return;
    }
    final delta = now.difference(last).inMilliseconds / 1000.0;
    if (delta <= 0 || delta > 3600) {
      return;
    }
    final bucket = _ensureDayBucket(scriptName, _dateKey(now));
    bucket.totalRuntimeSeconds += delta;
  }

  void _closeActiveTaskRun(
    String scriptName,
    _ScriptLiveSession session,
    DateTime now,
  ) {
    final taskName = session.activeTaskName;
    final start = session.activeTaskStartTime;
    final battles = session.activeTaskBattles;
    session.activeTaskName = '';
    session.activeTaskStartTime = null;
    session.activeTaskBattles = 0;

    if (taskName.isEmpty || start == null) {
      return;
    }
    final duration = now.difference(start).inMilliseconds / 1000.0;
    final bucket = _ensureDayBucket(scriptName, _dateKey(start));
    bucket.taskRuns.putIfAbsent(taskName, () => <_LocalRunEntry>[]).add(
          _LocalRunEntry(
            startTime: start,
            endTime: now,
            durationSeconds: duration < 0 ? 0 : duration,
            battleCount: battles,
          ),
        );
  }

  _ScriptLiveSession _sessionFor(String scriptName) {
    return _sessions.putIfAbsent(scriptName, _ScriptLiveSession.new);
  }

  Map<String, _LocalDayBucket> _daysFor(String scriptName) {
    final existing = _store[scriptName];
    if (existing != null) {
      return existing;
    }
    final loaded = _loadScriptFromStorage(scriptName);
    _store[scriptName] = loaded;
    return loaded;
  }

  _LocalDayBucket _ensureDayBucket(String scriptName, String dateKey) {
    final days = _daysFor(scriptName);
    return days.putIfAbsent(dateKey, _LocalDayBucket.new);
  }

  Map<String, _LocalDayBucket> _loadScriptFromStorage(String scriptName) {
    final raw = _storage.read('$_kStoragePrefix$scriptName');
    if (raw == null) {
      return <String, _LocalDayBucket>{};
    }
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) {
        return <String, _LocalDayBucket>{};
      }
      final result = <String, _LocalDayBucket>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          result[entry.key.toString()] = _LocalDayBucket.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
      return result;
    } catch (_) {
      return <String, _LocalDayBucket>{};
    }
  }

  void _persistScript(String scriptName) {
    final days = _store[scriptName];
    if (days == null) {
      return;
    }
    final sortedKeys = days.keys.toList()..sort((a, b) => b.compareTo(a));
    if (sortedKeys.length > _kMaxRetainedDays) {
      for (final staleKey in sortedKeys.skip(_kMaxRetainedDays)) {
        days.remove(staleKey);
      }
    }
    final encoded = <String, dynamic>{};
    for (final entry in days.entries) {
      encoded[entry.key] = entry.value.toJson();
    }
    _storage.write('$_kStoragePrefix$scriptName', jsonEncode(encoded));
  }

  void _notifyChanged() {
    revision.value++;
  }

  String _dateKey(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  String _formatDateTime(DateTime dt) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
}

class _ScriptLiveSession {
  bool isRunning = false;
  DateTime? lastRuntimeTick;
  String activeTaskName = '';
  DateTime? activeTaskStartTime;
  int activeTaskBattles = 0;
  DateTime? lastBattleAt;
}

class _LocalDayBucket {
  double totalRuntimeSeconds = 0.0;
  int extraBattleCount = 0;
  final Map<String, List<_LocalRunEntry>> taskRuns = {};

  _LocalDayBucket();

  factory _LocalDayBucket.fromJson(Map<String, dynamic> json) {
    final bucket = _LocalDayBucket();
    bucket.totalRuntimeSeconds =
        (json['total_runtime_seconds'] as num?)?.toDouble() ?? 0.0;
    bucket.extraBattleCount = (json['extra_battle_count'] as num?)?.toInt() ?? 0;
    final rawTasks = json['task_runs'];
    if (rawTasks is Map) {
      for (final entry in rawTasks.entries) {
        if (entry.value is List) {
          final parsedRuns = <_LocalRunEntry>[];
          for (final item in entry.value as List) {
            if (item is Map) {
              final run =
                  _LocalRunEntry.fromJson(Map<String, dynamic>.from(item));
              if (run != null) {
                parsedRuns.add(run);
              }
            }
          }
          if (parsedRuns.isNotEmpty) {
            bucket.taskRuns[entry.key.toString()] = parsedRuns;
          }
        }
      }
    }
    return bucket;
  }

  Map<String, dynamic> toJson() => {
        'total_runtime_seconds': totalRuntimeSeconds,
        'extra_battle_count': extraBattleCount,
        'task_runs': taskRuns.map(
          (key, value) => MapEntry(
            key,
            value.map((run) => run.toJson()).toList(),
          ),
        ),
      };
}

class _LocalRunEntry {
  _LocalRunEntry({
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.battleCount,
  });

  final DateTime startTime;
  final DateTime endTime;
  final double durationSeconds;
  final int battleCount;

  static _LocalRunEntry? fromJson(Map<String, dynamic> json) {
    final start = DateTime.tryParse((json['start'] ?? '').toString());
    final end = DateTime.tryParse((json['end'] ?? '').toString());
    if (start == null || end == null) {
      return null;
    }
    return _LocalRunEntry(
      startTime: start,
      endTime: end,
      durationSeconds: (json['duration'] as num?)?.toDouble() ?? 0.0,
      battleCount: (json['battles'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'start': startTime.toIso8601String(),
        'end': endTime.toIso8601String(),
        'duration': durationSeconds,
        'battles': battleCount,
      };
}
