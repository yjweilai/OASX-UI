import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/modules/common/models/storage_key.dart';
import 'package:oasx/modules/common/widgets/styled_typography_text.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/controllers/statistics_controller.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/modules/home/models/home_workbench_layout.dart';
import 'package:oasx/modules/home/widgets/desktop_config_rail.dart';
import 'package:oasx/modules/home/widgets/game_preview_widget.dart';
import 'package:oasx/service/game_preview_service.dart';
import 'package:oasx/modules/home/widgets/log_center_panel.dart';
import 'package:oasx/modules/home/widgets/statistics_panel.dart';
import 'package:oasx/modules/home/widgets/task_catalog_panel.dart';
import 'package:oasx/modules/home/widgets/task_parameter_panel.dart';
import 'package:oasx/modules/home/widgets/task_status_row.dart';
import 'package:oasx/modules/log/script_log_controller.dart';
import 'package:oasx/translation/i18n_content.dart';

/// Desktop minimalist sharp-bordered workbench:
/// Far-left vertical config rail + 3 resizable columns
/// (Left: Active Config + Game Preview + Flat Catalog;
///  Middle: Separate Running / Pending / Waiting cards with borderless rows;
///  Right: Full-height Log / Statistics card) + slide-over parameter drawer.
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
  static const double _kGap = 10;
  static const double _kResizerWidth = 10;
  static const double _kMinLeftColumnWidth = 84;
  static const double _kMinColumnWidth = 210;
  static const double _kDefaultLeftRatio = 0.08;
  static const double _kDefaultMiddleRatio = 0.36;
  static const String _kColumnRatiosStorageKey = 'bento_column_ratios_v2';

  final GlobalKey<LogCenterPanelState> _logPanelKey =
      GlobalKey<LogCenterPanelState>();
  final TextEditingController _taskSearchController = TextEditingController();
  final Set<String> _hiddenTaskIds = <String>{};
  final GetStorage _storage = GetStorage();

  String _taskSearchQuery = '';
  String _logLevelFilter = 'ALL';
  int _catalogReloadTick = 0;
  bool _showCatalogSearch = false;

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

  @override
  void dispose() {
    _taskSearchController.dispose();
    super.dispose();
  }

  void _loadColumnRatios() {
    final raw = _storage.read(_kColumnRatiosStorageKey);
    if (raw == null) {
      return;
    }
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is List && decoded.length >= 2) {
        final left = (decoded[0] as num).toDouble();
        final middle = (decoded[1] as num).toDouble();
        final right = 1.0 - left - middle;
        if (left >= 0.06 && middle >= 0.15 && right >= 0.15) {
          _leftRatio = left;
          _middleRatio = middle;
        }
      }
    } catch (_) {}
  }

  void _saveColumnRatios() {
    _storage.write(
      _kColumnRatiosStorageKey,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Far-left vertical config rail
                DesktopConfigRail(
                  controller: widget.controller,
                  loadingAddScript: widget.loadingAddScript,
                  refreshingScripts: widget.refreshingScripts,
                  onAddScriptTap: widget.onAddScriptTap,
                  onRefreshScriptsTap: widget.onRefreshScriptsTap,
                  onActivateScript: (name) async {
                    setState(() {
                      _taskSearchQuery = '';
                      _taskSearchController.clear();
                      _hiddenTaskIds.clear();
                    });
                    await widget.onActivateScript(name);
                  },
                  onTogglePower: widget.onTogglePower,
                  onRenameScript: widget.onRenameScript,
                  onDeleteScript: widget.onDeleteScript,
                  onToggleFloatingPreview: (name) {
                    if (Get.isRegistered<GamePreviewService>()) {
                      Get.find<GamePreviewService>()
                          .toggleFloatingPreview(name);
                    }
                  },
                ),
                const SizedBox(width: _kGap),
                // Main 3 resizable columns
                Expanded(
                  child: Obx(() {
                    final script = widget.controller.activeScriptModel;
                    if (script == null) {
                      return Card(
                        shape: _sharpCardShape(context),
                        child: Center(
                          child: Text(I18n.homeNoScriptSelected.tr),
                        ),
                      );
                    }
                    return _buildResizableColumns(context, script);
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
            const Positioned.fill(
              child: FloatingGamePreviewLayer(),
            ),
          ],
        );
      },
    );
  }

  RoundedRectangleBorder _sharpCardShape(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65)),
    );
  }

  Widget _buildResizableColumns(BuildContext context, ScriptModel script) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final usableWidth =
            (totalWidth - _kResizerWidth * 2).clamp(300.0, double.infinity);
        final minLeftRatio =
            (_kMinLeftColumnWidth / usableWidth).clamp(0.06, 0.24).toDouble();
        final minRatio =
            (_kMinColumnWidth / usableWidth).clamp(0.16, 0.32).toDouble();

        final safeLeft =
            _leftRatio.clamp(minLeftRatio, 1.0 - minRatio * 2).toDouble();
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
            // Left column: Full-height slim minimalist Catalog sidebar
            SizedBox(
              width: leftWidth,
              child: _buildCatalogCard(context, script),
            ),
            _BentoColumnResizer(
              width: _kResizerWidth,
              onDragUpdate: (deltaDx) {
                final deltaRatio = deltaDx / usableWidth;
                final maxLeft = 1.0 - safeRight - minRatio;
                final nextLeft = (safeLeft + deltaRatio)
                    .clamp(minLeftRatio, maxLeft)
                    .toDouble();
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
            // Middle column: 3 separate sharp-bordered boxes (Running / Pending / Waiting)
            SizedBox(
              width: middleWidth,
              child: _buildMiddleTaskBuckets(context, script),
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
            // Right column: Single full-height sharp-bordered Log / Statistics card
            SizedBox(
              width: rightWidth,
              child: _buildRightLogStatsCard(context, script),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCatalogCard(BuildContext context, ScriptModel script) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    return Card(
      shape: _sharpCardShape(context),
      child: Column(
        children: [
          Obx(() {
            final isOverviewActive =
                widget.controller.activeTaskName.value.trim().isEmpty;
            return InkWell(
              onTap: () {
                if (!isOverviewActive) {
                  widget.onCloseTaskDrawer();
                }
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: isOverviewActive ? fg : Colors.transparent,
                      width: 2,
                    ),
                    bottom: BorderSide(
                      color: fg.withValues(alpha: 0.14),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: StyledTypographyText(
                        '总览',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 13,
                          fontWeight: isOverviewActive
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: fg,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: _showCatalogSearch ? '隐藏搜索' : '搜索任务',
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _showCatalogSearch = !_showCatalogSearch;
                          });
                        },
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: Center(
                            child: Icon(
                              Icons.search_rounded,
                              size: 14,
                              color: _showCatalogSearch
                                  ? fg
                                  : fg.withValues(alpha: 0.72),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: '刷新',
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _catalogReloadTick++;
                          });
                        },
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: Center(
                            child: Icon(
                              Icons.refresh_rounded,
                              size: 14,
                              color: fg.withValues(alpha: 0.72),
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: TaskCatalogPanel(
                key: ValueKey<String>(
                  'desktop-catalog-${script.name}-$_catalogReloadTick',
                ),
                controller: widget.controller,
                scriptModel: script,
                inlineParameters: false,
                flatStyle: true,
                showToolbar: _showCatalogSearch,
                onOpenTask: (taskName) => widget.onOpenTask(
                  taskName,
                  HomeTaskParameterEntrySource.overview,
                ),
                onQuickRun: widget.onQuickRun,
                onQuickWait: widget.onQuickWait,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiddleTaskBuckets(BuildContext context, ScriptModel script) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Obx(() {
      final dragPayload = widget.controller.activeDragPayload.value;
      final runningTasks = <TaskStatusViewData>[];
      final pendingTasks = <TaskStatusViewData>[];
      final waitingTasks = <TaskStatusViewData>[];

      final runningName = script.runningTask.value.taskName.value.trim();
      if (runningName.isNotEmpty) {
        final item = TaskStatusViewData(
          rowId: 'running::$runningName',
          name: runningName,
          type: TaskStatusType.running,
          timeText: script.runningTask.value.nextRun.value.trim(),
        );
        if (!_hiddenTaskIds.contains(item.rowId) && _matchesTaskQuery(item)) {
          runningTasks.add(item);
        }
      }

      for (final entry in script.pendingTaskList.indexed) {
        final name = entry.$2.taskName.value.trim();
        if (name.isEmpty) continue;
        final timeText = entry.$2.nextRun.value.trim();
        final item = TaskStatusViewData(
          rowId: 'pending::${entry.$1}::$name::$timeText',
          name: name,
          type: TaskStatusType.pending,
          timeText: timeText,
        );
        if (!_hiddenTaskIds.contains(item.rowId) && _matchesTaskQuery(item)) {
          pendingTasks.add(item);
        }
      }

      for (final entry in script.waitingTaskList.indexed) {
        final name = entry.$2.taskName.value.trim();
        if (name.isEmpty) continue;
        final timeText = entry.$2.nextRun.value.trim();
        final item = TaskStatusViewData(
          rowId: 'waiting::${entry.$1}::$name::$timeText',
          name: name,
          type: TaskStatusType.waiting,
          timeText: timeText,
        );
        if (!_hiddenTaskIds.contains(item.rowId) && _matchesTaskQuery(item)) {
          waitingTasks.add(item);
        }
      }

      Widget buildRow(TaskStatusViewData task) {
        final swipeDisabled = script.state.value == ScriptState.running &&
            task.type == TaskStatusType.running;
        return TaskStatusRow(
          key: ValueKey(task.rowId),
          controller: widget.controller,
          sourceScriptName: script.name,
          task: task,
          flatStyle: true,
          canQuickSchedule:
              widget.controller.canQuickScheduleTask(script, task.name),
          onSetNextRun: widget.onSetNextRun,
          onQuickRun: widget.onQuickRun,
          onQuickWait: widget.onQuickWait,
          onEditTask: (taskName) => widget.onOpenTask(
            taskName,
            HomeTaskParameterEntrySource.tasks,
          ),
          onDisableTask: (taskName) => widget.controller.toggleTaskEnabled(
            scriptName: script.name,
            taskName: taskName,
            enable: false,
          ),
          onDismissed: (rowId) => setState(() {
            _hiddenTaskIds.add(rowId);
          }),
          dragEnabled: widget.controller.canUseDesktopDragCopy,
          swipeEnabled: !swipeDisabled,
          activeDragPayload: dragPayload,
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Box 1: 运行中
          Card(
            shape: _sharpCardShape(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      StyledTypographyText(
                        '运行中',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      StyledTypographyText(
                        '${runningTasks.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Divider(
                    height: 12,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  if (runningTasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: StyledTypographyText(
                        '暂无运行中任务',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (int i = 0; i < runningTasks.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      buildRow(runningTasks[i]),
                    ],
                ],
              ),
            ),
          ),
          const SizedBox(height: _kGap),
          // Box 2: 队列中
          Card(
            shape: _sharpCardShape(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      StyledTypographyText(
                        '队列中',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      StyledTypographyText(
                        '${pendingTasks.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Divider(
                    height: 12,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  if (pendingTasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: StyledTypographyText(
                        '暂无队列中任务',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: pendingTasks.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                        itemBuilder: (_, index) => buildRow(pendingTasks[index]),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: _kGap),
          // Box 3: 等待中 (Expanded to fill remaining height)
          Expanded(
            child: Card(
              shape: _sharpCardShape(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        StyledTypographyText(
                          '等待中',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        StyledTypographyText(
                          '${waitingTasks.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 30,
                            child: TextField(
                              controller: _taskSearchController,
                              style: theme.textTheme.bodySmall,
                              decoration: InputDecoration(
                                isDense: true,
                                prefixIcon:
                                    const Icon(Icons.search_rounded, size: 15),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                hintText: I18n.taskSearchHint.tr,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                border: const OutlineInputBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              onChanged: (value) => setState(() {
                                _taskSearchQuery = value.trim().toLowerCase();
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Divider(
                      height: 12,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    Expanded(
                      child: waitingTasks.isEmpty
                          ? Center(
                              child: StyledTypographyText(
                                _taskSearchQuery.isEmpty
                                    ? I18n.homeNoTask.tr
                                    : I18n.taskNotFound.tr,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.separated(
                              key: const PageStorageKey<String>(
                                'home-waiting-tasks-flat',
                              ),
                              padding: EdgeInsets.zero,
                              itemCount: waitingTasks.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.4),
                              ),
                              itemBuilder: (_, index) =>
                                  buildRow(waitingTasks[index]),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  bool _matchesTaskQuery(TaskStatusViewData task) {
    if (_taskSearchQuery.isEmpty) {
      return true;
    }
    final localized = task.name.tr.toLowerCase();
    final original = task.name.toLowerCase();
    return localized.contains(_taskSearchQuery) ||
        original.contains(_taskSearchQuery);
  }

  Widget _buildRightLogStatsCard(BuildContext context, ScriptModel script) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statsController = _statsController;

    return Card(
      shape: _sharpCardShape(context),
      child: Obx(() {
        final rightTab = widget.controller.activeWorkbenchSidebarTab.value;
        final isLogs = rightTab != HomeWorkbenchTab.stats;
        final logController =
            Get.isRegistered<ScriptLogController>(tag: script.name)
                ? Get.find<ScriptLogController>(tag: script.name)
                : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Unified compact header toolbar (auto-wraps cleanly when narrow)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Row(
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  if (isLogs) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SegmentButton(
                          label: '信息',
                          selected: _logLevelFilter != 'ERROR_GROUP',
                          onTap: () => setState(() {
                            _logLevelFilter = 'ALL';
                          }),
                        ),
                        const SizedBox(width: 4),
                        _SegmentButton(
                          label: '错误',
                          selected: _logLevelFilter == 'ERROR_GROUP',
                          onTap: () => setState(() {
                            _logLevelFilter = 'ERROR_GROUP';
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    PopupMenuButton<String>(
                      tooltip: '日志级别筛选',
                      initialValue: _logLevelFilter,
                      onSelected: (value) => setState(() {
                        _logLevelFilter = value;
                      }),
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(value: 'ALL', child: Text('ALL')),
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
                        color:
                            _logLevelFilter == 'ALL' ? null : scheme.primary,
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
                        icon: const Icon(Icons.content_copy_rounded, size: 17),
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
                        icon:
                            const Icon(Icons.delete_outline_rounded, size: 18),
                      ),
                    ),
                  ] else ...[
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
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
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
                            '清空本地统计',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      );
                    }),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
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
                    ],
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
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
          ],
        );
      }),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.65),
                ),
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
                                child: StyledTypographyText(
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
                ),
              ),
            ),
          ),
        ),
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
    final fg = theme.colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? fg : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: StyledTypographyText(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? fg : fg.withValues(alpha: 0.65),
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
    final fg = theme.colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? fg : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: StyledTypographyText(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? fg : fg.withValues(alpha: 0.65),
            ),
          ),
        ),
      ),
    );
  }
}
