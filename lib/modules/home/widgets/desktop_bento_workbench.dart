import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/modules/common/models/storage_key.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/controllers/statistics_controller.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/modules/home/models/home_workbench_layout.dart';
import 'package:oasx/modules/home/widgets/desktop_config_strip.dart';
import 'package:oasx/modules/home/widgets/game_preview_widget.dart';
import 'package:oasx/modules/home/widgets/log_center_panel.dart';
import 'package:oasx/modules/home/widgets/statistics_panel.dart';
import 'package:oasx/modules/home/widgets/task_catalog_panel.dart';
import 'package:oasx/modules/home/widgets/task_date_distribution_card.dart';
import 'package:oasx/modules/home/widgets/task_parameter_panel.dart';
import 'package:oasx/modules/home/widgets/task_status_panel.dart';
import 'package:oasx/modules/home/widgets/task_status_row.dart';
import 'package:oasx/modules/log/script_log_controller.dart';
import 'package:oasx/translation/i18n_content.dart';

/// Desktop three-column bento workbench with resizable columns,
/// top config strip, and slide-over task parameter drawer.
class DesktopBentoWorkbench extends StatefulWidget {
  const DesktopBentoWorkbench({
    super.key,
    required this.controller,
    required this.loadingAddScript,
    required this.refreshingScripts,
    required this.onAddScriptTap,
    required this.onRefreshScriptsTap,
    required this.onActivateScript,
    required this.onTogglePower,
    required this.onRenameScript,
    required this.onDeleteScript,
    required this.onOpenTask,
    required this.onCloseTaskDrawer,
    required this.onSetNextRun,
    required this.onQuickRun,
    required this.onQuickWait,
  });

  final HomeDashboardController controller;
  final bool loadingAddScript;
  final bool refreshingScripts;
  final VoidCallback onAddScriptTap;
  final VoidCallback onRefreshScriptsTap;
  final Future<void> Function(String scriptName) onActivateScript;
  final Future<void> Function(String scriptName, bool enable) onTogglePower;
  final Future<void> Function(String scriptName) onRenameScript;
  final Future<void> Function(String scriptName) onDeleteScript;
  final Future<void> Function(
    String taskName,
    HomeTaskParameterEntrySource source,
  ) onOpenTask;
  final Future<void> Function() onCloseTaskDrawer;
  final Future<void> Function(String taskName, String nextRun) onSetNextRun;
  final Future<void> Function(String taskName) onQuickRun;
  final Future<void> Function(String taskName) onQuickWait;

  @override
  State<DesktopBentoWorkbench> createState() => _DesktopBentoWorkbenchState();
}

class _DesktopBentoWorkbenchState extends State<DesktopBentoWorkbench> {
  static const double _kTopRowHeight = 156;
  static const double _kGap = 12;
  static const double _kResizerWidth = 12;
  static const double _kMinColumnWidth = 240;
  static const double _kDefaultLeftRatio = 0.31;
  static const double _kDefaultMiddleRatio = 0.34;

  final GlobalKey<LogCenterPanelState> _logPanelKey =
      GlobalKey<LogCenterPanelState>();
  final GetStorage _storage = GetStorage();

  DateTime? _selectedDateFilter;
  TaskStatusType? _taskTypeFilter;
  String _logLevelFilter = 'ALL';
  int _catalogReloadTick = 0;

  double _leftRatio = _kDefaultLeftRatio;
  double _middleRatio = _kDefaultMiddleRatio;

  HomeStatisticsController? get _statsController =>
      Get.isRegistered<HomeStatisticsController>()
          ? Get.find<HomeStatisticsController>()
          : null;

  @override
  void initState() {
    super.initState();
    _loadColumnRatios();
  }

  void _loadColumnRatios() {
    final raw = _storage.read(StorageKey.bentoColumnRatios.name);
    if (raw == null) {
      return;
    }
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is List && decoded.length >= 2) {
        final left = (decoded[0] as num).toDouble();
        final middle = (decoded[1] as num).toDouble();
        final right = 1.0 - left - middle;
        if (left >= 0.15 && middle >= 0.15 && right >= 0.15) {
          _leftRatio = left;
          _middleRatio = middle;
        }
      }
    } catch (_) {}
  }

  void _saveColumnRatios() {
    _storage.write(
      StorageKey.bentoColumnRatios.name,
      jsonEncode([_leftRatio, _middleRatio]),
    );
  }

  void _resetColumnRatios() {
    setState(() {
      _leftRatio = _kDefaultLeftRatio;
      _middleRatio = _kDefaultMiddleRatio;
    });
    _saveColumnRatios();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.workbenchLayoutMode.value !=
        HomeWorkbenchLayoutMode.threePane) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.controller
              .setWorkbenchLayoutMode(HomeWorkbenchLayoutMode.threePane);
        }
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final drawerWidth =
            (constraints.maxWidth * 0.42).clamp(420.0, 560.0).toDouble();

        return Stack(
          children: [
            Column(
              children: [
                DesktopConfigStrip(
                  controller: widget.controller,
                  loadingAddScript: widget.loadingAddScript,
                  refreshingScripts: widget.refreshingScripts,
                  onAddScriptTap: widget.onAddScriptTap,
                  onRefreshScriptsTap: widget.onRefreshScriptsTap,
                  onActivateScript: (name) async {
                    setState(() {
                      _selectedDateFilter = null;
                      _taskTypeFilter = null;
                    });
                    await widget.onActivateScript(name);
                  },
                  onTogglePower: widget.onTogglePower,
                  onRenameScript: widget.onRenameScript,
                  onDeleteScript: widget.onDeleteScript,
                ),
                const SizedBox(height: _kGap),
                Expanded(
                  child: Obx(() {
                    final script = widget.controller.activeScriptModel;
                    if (script == null) {
                      return Card(
                        child: Center(
                          child: Text(I18n.homeNoScriptSelected.tr),
                        ),
                      );
                    }
                    return _buildResizableBentoColumns(context, script);
                  }),
                ),
              ],
            ),
            Obx(() {
              final activeTask = widget.controller.activeTaskName.value.trim();
              final script = widget.controller.activeScriptModel;
              final isOpen = activeTask.isNotEmpty && script != null;
              return _buildSlideOverDrawer(
                context: context,
                isOpen: isOpen,
                drawerWidth: drawerWidth,
                script: script,
                taskName: activeTask,
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildResizableBentoColumns(BuildContext context, ScriptModel script) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final usableWidth =
            (totalWidth - _kResizerWidth * 2).clamp(300.0, double.infinity);
        final minRatio =
            (_kMinColumnWidth / usableWidth).clamp(0.16, 0.32).toDouble();

        final safeLeft =
            _leftRatio.clamp(minRatio, 1.0 - minRatio * 2).toDouble();
        final safeMiddle = _middleRatio
            .clamp(minRatio, 1.0 - safeLeft - minRatio)
            .toDouble();
        final safeRight = (1.0 - safeLeft - safeMiddle).clamp(minRatio, 1.0);

        final leftWidth = usableWidth * safeLeft;
        final middleWidth = usableWidth * safeMiddle;
        final rightWidth = usableWidth * safeRight;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left column: Active config summary + Task catalog ("总览")
            SizedBox(
              width: leftWidth,
              child: Column(
                children: [
                  SizedBox(
                    height: _kTopRowHeight,
                    child: _buildActiveConfigSummaryCard(context, script),
                  ),
                  const SizedBox(height: _kGap),
                  Expanded(
                    child: _buildCatalogCard(context, script),
                  ),
                ],
              ),
            ),
            _BentoColumnResizer(
              width: _kResizerWidth,
              onDragUpdate: (deltaDx) {
                final deltaRatio = deltaDx / usableWidth;
                final maxLeft = 1.0 - safeRight - minRatio;
                final nextLeft =
                    (safeLeft + deltaRatio).clamp(minRatio, maxLeft).toDouble();
                final actualDelta = nextLeft - safeLeft;
                final nextMiddle = (safeMiddle - actualDelta)
                    .clamp(minRatio, 1.0 - nextLeft - minRatio)
                    .toDouble();
                setState(() {
                  _leftRatio = nextLeft;
                  _middleRatio = nextMiddle;
                });
              },
              onDragEnd: _saveColumnRatios,
              onDoubleTap: _resetColumnRatios,
            ),
            // Middle column: 7-day task distribution + Task queue ("任务")
            SizedBox(
              width: middleWidth,
              child: Column(
                children: [
                  SizedBox(
                    height: _kTopRowHeight,
                    child: TaskDateDistributionCard(
                      scriptModel: script,
                      selectedDate: _selectedDateFilter,
                      onSelectDate: (date) => setState(() {
                        _selectedDateFilter = date;
                      }),
                    ),
                  ),
                  const SizedBox(height: _kGap),
                  Expanded(
                    child: _buildTaskQueueCard(context, script),
                  ),
                ],
              ),
            ),
            _BentoColumnResizer(
              width: _kResizerWidth,
              onDragUpdate: (deltaDx) {
                final deltaRatio = deltaDx / usableWidth;
                final maxMiddle = 1.0 - safeLeft - minRatio;
                final nextMiddle = (safeMiddle + deltaRatio)
                    .clamp(minRatio, maxMiddle)
                    .toDouble();
                setState(() {
                  _leftRatio = safeLeft;
                  _middleRatio = nextMiddle;
                });
              },
              onDragEnd: _saveColumnRatios,
              onDoubleTap: _resetColumnRatios,
            ),
            // Right column: Log/Stats header toolbar + Content card
            SizedBox(
              width: rightWidth,
              child: Obx(() {
                final rightTab =
                    widget.controller.activeWorkbenchSidebarTab.value;
                final isLogs = rightTab != HomeWorkbenchTab.stats;
                return Column(
                  children: [
                    SizedBox(
                      height: _kTopRowHeight,
                      child: _buildRightControlCard(context, script, isLogs),
                    ),
                    const SizedBox(height: _kGap),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: isLogs
                              ? LogCenterPanel(
                                  key: _logPanelKey,
                                  scriptName: script.name,
                                  embedded: true,
                                  showToolbar: false,
                                  externalLevelFilter: _logLevelFilter,
                                )
                              : const ScriptStatisticsPanel(),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActiveConfigSummaryCard(
    BuildContext context,
    ScriptModel script,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statsController = _statsController;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Obx(() {
          final isRunning = script.state.value == ScriptState.running;
          final isLinkMode = widget.controller.isLinkModeEnabled.value;
          final runningTaskName =
              script.runningTask.value.taskName.value.trim();
          final stats = statsController?.statistics.value;
          final hasStats = stats != null && stats.scriptName == script.name;

          final runtimeText = hasStats
              ? _formatCompactDuration(stats.totalRuntimeSeconds)
              : '--';
          final runCountText = hasStats ? '${stats.totalTaskRunCount}' : '--';
          final battleCountText = hasStats ? '${stats.totalBattleCount}' : '--';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      script.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      tooltip: isRunning ? '快速停止' : '快速启动',
                      onPressed: () =>
                          widget.onTogglePower(script.name, !isRunning),
                      icon: const Icon(Icons.bolt_rounded),
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      tooltip: isLinkMode ? '关闭多配置联动' : '开启多配置联动',
                      color: isLinkMode ? scheme.primary : null,
                      onPressed: widget.controller.toggleLinkMode,
                      icon: const Icon(Icons.link_rounded),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: isRunning
                          ? const Color(0xFFC62828)
                          : const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: () =>
                        widget.onTogglePower(script.name, !isRunning),
                    child: Text(
                      isRunning ? '停止运行' : '开始运行',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    isRunning
                        ? Icons.bolt_rounded
                        : Icons.pause_circle_outline_rounded,
                    size: 15,
                    color: isRunning
                        ? const Color(0xFF22C55E)
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      runningTaskName.isNotEmpty
                          ? runningTaskName.tr
                          : (isRunning ? '运行中' : '空闲中'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '调整计划',
                    onSelected: (value) async {
                      switch (value) {
                        case 'refresh_stats':
                          await statsController?.refreshStatistics();
                          break;
                        case 'reset_columns':
                          _resetColumnRatios();
                          break;
                        case 'rename':
                          await widget.onRenameScript(script.name);
                          break;
                        case 'delete':
                          await widget.onDeleteScript(script.name);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'refresh_stats',
                        child: Text('刷新统计数据'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'reset_columns',
                        child: Text('重置三栏默认宽度'),
                      ),
                      PopupMenuItem<String>(
                        value: 'rename',
                        child: Text(I18n.rename.tr),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text(I18n.delete.tr),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '调整计划',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Divider(
                height: 12,
                color: scheme.outlineVariant.withValues(alpha: 0.55),
              ),
              Row(
                children: [
                  _MetricTile(label: '今日运行', value: runtimeText),
                  _MetricTile(label: '任务次数', value: runCountText),
                  _MetricTile(label: '战斗场次', value: battleCountText),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildCatalogCard(BuildContext context, ScriptModel script) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  '总览',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: '刷新',
                    onPressed: () {
                      setState(() {
                        _catalogReloadTick++;
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TaskCatalogPanel(
                key: ValueKey<String>(
                  'desktop-catalog-${script.name}-$_catalogReloadTick',
                ),
                controller: widget.controller,
                scriptModel: script,
                inlineParameters: false,
                onOpenTask: (taskName) => widget.onOpenTask(
                  taskName,
                  HomeTaskParameterEntrySource.overview,
                ),
                onQuickRun: widget.onQuickRun,
                onQuickWait: widget.onQuickWait,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskQueueCard(BuildContext context, ScriptModel script) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  '任务',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _TaskFilterToggleButton(
                  icon: Icons.bolt_rounded,
                  tooltip: '仅看运行中任务',
                  selected: _taskTypeFilter == TaskStatusType.running,
                  accentColor: const Color(0xFF16A34A),
                  onTap: () => setState(() {
                    _taskTypeFilter =
                        _taskTypeFilter == TaskStatusType.running
                            ? null
                            : TaskStatusType.running;
                  }),
                ),
                const SizedBox(width: 6),
                _TaskFilterToggleButton(
                  icon: Icons.schedule_rounded,
                  tooltip: '仅看等待中任务',
                  selected: _taskTypeFilter == TaskStatusType.waiting,
                  accentColor: scheme.primary,
                  onTap: () => setState(() {
                    _taskTypeFilter =
                        _taskTypeFilter == TaskStatusType.waiting
                            ? null
                            : TaskStatusType.waiting;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TaskStatusPanel(
                controller: widget.controller,
                scriptModel: script,
                selectedDateFilter: _selectedDateFilter,
                typeFilter: _taskTypeFilter,
                canQuickScheduleTask: (taskName) =>
                    widget.controller.canQuickScheduleTask(script, taskName),
                onSetNextRun: widget.onSetNextRun,
                onQuickRun: widget.onQuickRun,
                onQuickWait: widget.onQuickWait,
                onEditTask: (taskName) => widget.onOpenTask(
                  taskName,
                  HomeTaskParameterEntrySource.tasks,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightControlCard(
    BuildContext context,
    ScriptModel script,
    bool isLogs,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final logController = Get.isRegistered<ScriptLogController>(tag: script.name)
        ? Get.find<ScriptLogController>(tag: script.name)
        : null;
    final statsController = _statsController;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left: embedded live game screen preview
            Expanded(
              flex: 52,
              child: GamePreviewThumbnail(scriptName: script.name),
            ),
            const SizedBox(width: 10),
            // Right: stacked Log/Stats tabs, Info/Error toggle, and actions
            Expanded(
              flex: 48,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RightTabPill(
                          label: I18n.log.tr,
                          selected: isLogs,
                          onTap: () => widget.controller
                              .setActiveWorkbenchSidebarTabValue(
                                  HomeWorkbenchTab.logs),
                        ),
                        const SizedBox(width: 6),
                        _RightTabPill(
                          label: I18n.homeStatsTab.tr,
                          selected: !isLogs,
                          onTap: () => widget.controller
                              .setActiveWorkbenchSidebarTabValue(
                                  HomeWorkbenchTab.stats),
                        ),
                      ],
                    ),
                  ),
                  if (isLogs) ...[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.10)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.55),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SegmentButton(
                              label: '信息',
                              selected: _logLevelFilter != 'ERROR_GROUP',
                              onTap: () => setState(() {
                                _logLevelFilter = 'ALL';
                              }),
                            ),
                            _SegmentButton(
                              label: '错误',
                              selected: _logLevelFilter == 'ERROR_GROUP',
                              onTap: () => setState(() {
                                _logLevelFilter = 'ERROR_GROUP';
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PopupMenuButton<String>(
                            tooltip: '日志级别筛选',
                            initialValue: _logLevelFilter,
                            onSelected: (value) => setState(() {
                              _logLevelFilter = value;
                            }),
                            itemBuilder: (context) => const [
                              PopupMenuItem<String>(
                                  value: 'ALL', child: Text('ALL')),
                              PopupMenuItem<String>(
                                  value: 'INFO', child: Text('INFO')),
                              PopupMenuItem<String>(
                                  value: 'WARNING', child: Text('WARNING')),
                              PopupMenuItem<String>(
                                  value: 'ERROR', child: Text('ERROR')),
                              PopupMenuItem<String>(
                                  value: 'CRITICAL', child: Text('CRITICAL')),
                            ],
                            icon: Icon(
                              Icons.filter_list_rounded,
                              size: 18,
                              color: _logLevelFilter == 'ALL'
                                  ? null
                                  : scheme.primary,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 30,
                              height: 30,
                            ),
                          ),
                          if (logController != null)
                            Obx(() {
                              final autoScroll = logController.autoScroll.value;
                              return SizedBox(
                                width: 30,
                                height: 30,
                                child: IconButton(
                                  tooltip: I18n.homeLogAutoScroll.tr,
                                  padding: EdgeInsets.zero,
                                  onPressed: logController.toggleAutoScroll,
                                  icon: Icon(
                                    autoScroll
                                        ? Icons.bolt_rounded
                                        : Icons.flash_off_rounded,
                                    size: 18,
                                    color: autoScroll ? scheme.primary : null,
                                  ),
                                ),
                              );
                            })
                          else
                            const SizedBox(
                              width: 30,
                              height: 30,
                              child: IconButton(
                                onPressed: null,
                                padding: EdgeInsets.zero,
                                icon: Icon(Icons.bolt_rounded, size: 18),
                              ),
                            ),
                          SizedBox(
                            width: 30,
                            height: 30,
                            child: IconButton(
                              tooltip: I18n.copy.tr,
                              padding: EdgeInsets.zero,
                              onPressed: () =>
                                  _logPanelKey.currentState?.copyVisibleLogs(),
                              icon: const Icon(Icons.content_copy_rounded,
                                  size: 17),
                            ),
                          ),
                          SizedBox(
                            width: 30,
                            height: 30,
                            child: IconButton(
                              tooltip: I18n.clearLog.tr,
                              padding: EdgeInsets.zero,
                              onPressed: () =>
                                  _logPanelKey.currentState?.clearLogs(),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Obx(() {
                      final dateKey =
                          statsController?.selectedDateKey.value ?? '';
                      final loading =
                          (statsController?.datesLoading.value ?? false) ||
                              (statsController?.statisticsLoading.value ??
                                  false);
                      final isLocal =
                          statsController?.isLocalFallback.value ?? false;
                      final subtitle = loading
                          ? I18n.homeStatsLoadingMessage.tr
                          : (dateKey.isNotEmpty
                              ? '$dateKey${isLocal ? ' · 本地' : ''}'
                              : '统计概览');
                      return Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      );
                    }),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Obx(() {
                            final isLocal =
                                statsController?.isLocalFallback.value ?? false;
                            if (!isLocal || statsController == null) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                ),
                                onPressed: () => _confirmClearLocalStats(
                                    context, statsController),
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 14),
                                label: const Text(
                                  '清空',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            );
                          }),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                            onPressed: statsController == null
                                ? null
                                : () => statsController.refreshStatistics(),
                            icon: const Icon(Icons.refresh_rounded, size: 14),
                            label: const Text(
                              '刷新',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlideOverDrawer({
    required BuildContext context,
    required bool isOpen,
    required double drawerWidth,
    required ScriptModel? script,
    required String taskName,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return IgnorePointer(
      ignoring: !isOpen,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: isOpen ? () => widget.onCloseTaskDrawer() : null,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isOpen ? 1 : 0,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.28),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            right: isOpen ? 0 : -drawerWidth - 24,
            width: drawerWidth,
            child: Material(
              elevation: 16,
              color: isDark ? const Color(0xFF1F2127) : Colors.white,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: isOpen && script != null
                  ? Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 18,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  taskName.tr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: I18n.cancel.tr,
                                onPressed: () => widget.onCloseTaskDrawer(),
                                icon: const Icon(Icons.close_rounded, size: 20),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: TaskParameterPanel(
                              controller: widget.controller,
                              scriptModel: script,
                              showHeader: false,
                              onBack: widget.onCloseTaskDrawer,
                            ),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _confirmClearLocalStats(
    BuildContext context,
    HomeStatisticsController statsController,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空本地统计'),
        content: const Text('确定要清空当前配置的全部本地统计记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(I18n.cancel.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(I18n.confirm.tr),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      statsController.clearLocalStatistics();
    }
  }

  String _formatCompactDuration(double seconds) {
    if (seconds <= 0) {
      return '0m';
    }
    final duration = Duration(seconds: seconds.round());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m';
    }
    return '${duration.inSeconds}s';
  }
}

class _BentoColumnResizer extends StatefulWidget {
  const _BentoColumnResizer({
    required this.width,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDoubleTap,
  });

  final double width;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDoubleTap;

  @override
  State<_BentoColumnResizer> createState() => _BentoColumnResizerState();
}

class _BentoColumnResizerState extends State<_BentoColumnResizer> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _hovered || _dragging;
    return Tooltip(
      message: '拖动调整列宽（双击重置）',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: widget.onDoubleTap,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (details) =>
              widget.onDragUpdate(details.delta.dx),
          onHorizontalDragEnd: (_) {
            setState(() => _dragging = false);
            widget.onDragEnd();
          },
          onHorizontalDragCancel: () {
            setState(() => _dragging = false);
            widget.onDragEnd();
          },
          child: SizedBox(
            width: widget.width,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: active ? 4 : 2,
                height: active ? 56 : 28,
                decoration: BoxDecoration(
                  color: active
                      ? scheme.primary.withValues(alpha: 0.75)
                      : scheme.outlineVariant.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RightTabPill extends StatelessWidget {
  const _RightTabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: isDark ? 0.24 : 0.12)
          : (isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.05)),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.4)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? Colors.white.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.85))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _TaskFilterToggleButton extends StatelessWidget {
  const _TaskFilterToggleButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: isDark ? 0.28 : 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? accentColor.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: isDark ? 0.42 : 0.32),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                    offset: const Offset(0, 2),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Icon(
              icon,
              size: 18,
              color: selected ? accentColor : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
