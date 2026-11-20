import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/common/models/config_drag_payload.dart';
import 'package:oasx/modules/common/widgets/styled_typography_text.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/translation/i18n_content.dart';

/// Slim vertical configuration rail pinned to the far left of the desktop workbench.
class DesktopConfigRail extends StatelessWidget {
  const DesktopConfigRail({
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 60,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Obx(() {
                final scripts = controller.visibleScripts;
                final activeName = controller.activeScriptName.value;
                final isLinkMode = controller.isLinkModeEnabled.value;
                if (scripts.isEmpty) {
                  return Center(
                    child: Icon(
                      Icons.inbox_outlined,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: scripts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final script = scripts[index];
                    final isActive = script.name == activeName;
                    final isLinked =
                        isLinkMode && controller.isScriptLinked(script.name);
                    return _ConfigRailItem(
                      controller: controller,
                      script: script,
                      isActive: isActive,
                      isLinked: isLinked,
                      onTap: () => onActivateScript(script.name),
                      onTogglePower: (enable) =>
                          onTogglePower(script.name, enable),
                      onRename: () => onRenameScript(script.name),
                      onDelete: () => onDeleteScript(script.name),
                    );
                  },
                );
              }),
            ),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.55),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RailActionButton(
                    icon: Icons.add_rounded,
                    tooltip: '新增配置',
                    loading: loadingAddScript,
                    onPressed: onAddScriptTap,
                  ),
                  _RailActionButton(
                    icon: Icons.refresh_rounded,
                    tooltip: '刷新',
                    loading: refreshingScripts,
                    onPressed: onRefreshScriptsTap,
                  ),
                  Obx(() {
                    final currentFilter = controller.stateFilter.value;
                    final isLinkMode = controller.isLinkModeEnabled.value;
                    return PopupMenuButton<String>(
                      tooltip: '筛选与联动',
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.tune_rounded,
                        size: 19,
                        color: currentFilter != HomeScriptStateFilter.all ||
                                isLinkMode
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'all':
                            controller
                                .setStateFilterValue(HomeScriptStateFilter.all);
                            break;
                          case 'running':
                            controller.setStateFilterValue(
                                HomeScriptStateFilter.running);
                            break;
                          case 'abnormal':
                            controller.setStateFilterValue(
                                HomeScriptStateFilter.abnormal);
                            break;
                          case 'stopped':
                            controller.setStateFilterValue(
                                HomeScriptStateFilter.stopped);
                            break;
                          case 'link':
                            controller.toggleLinkMode();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        CheckedPopupMenuItem<String>(
                          value: 'all',
                          checked: currentFilter == HomeScriptStateFilter.all,
                          child: const Text('全部配置'),
                        ),
                        CheckedPopupMenuItem<String>(
                          value: 'running',
                          checked:
                              currentFilter == HomeScriptStateFilter.running,
                          child: const Text('仅看运行中'),
                        ),
                        CheckedPopupMenuItem<String>(
                          value: 'abnormal',
                          checked:
                              currentFilter == HomeScriptStateFilter.abnormal,
                          child: const Text('仅看异常'),
                        ),
                        CheckedPopupMenuItem<String>(
                          value: 'stopped',
                          checked:
                              currentFilter == HomeScriptStateFilter.stopped,
                          child: const Text('仅看已停止'),
                        ),
                        const PopupMenuDivider(),
                        CheckedPopupMenuItem<String>(
                          value: 'link',
                          checked: isLinkMode,
                          child: const Text('多配置联动模式'),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigRailItem extends StatelessWidget {
  const _ConfigRailItem({
    required this.controller,
    required this.script,
    required this.isActive,
    required this.isLinked,
    required this.onTap,
    required this.onTogglePower,
    required this.onRename,
    required this.onDelete,
  });

  final HomeDashboardController controller;
  final ScriptModel script;
  final bool isActive;
  final bool isLinked;
  final VoidCallback onTap;
  final ValueChanged<bool> onTogglePower;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return DragTarget<ConfigDragPayload>(
      onWillAcceptWithDetails: (details) => details.data.canDropOn(script.name),
      onAcceptWithDetails: (details) {
        controller.acceptConfigDrag(
          payload: details.data,
          destinationConfig: script.name,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isDropHover = candidateData.isNotEmpty;
        return Obx(() {
          final state = script.state.value;
          final isRunning = state == ScriptState.running;
          final isPendingCopy = controller.isDragCopyPendingFor(script.name);

          final bgColor = isDropHover
              ? scheme.primary.withValues(alpha: 0.22)
              : isActive
                  ? scheme.primary.withValues(alpha: isDark ? 0.24 : 0.12)
                  : Colors.transparent;
          final stateColor = switch (state) {
            ScriptState.running => const Color(0xFF16A34A),
            ScriptState.warning => const Color(0xFFF59E0B),
            ScriptState.updating => const Color(0xFF3B82F6),
            ScriptState.inactive => scheme.onSurfaceVariant,
          };

          return GestureDetector(
            onSecondaryTapDown: (details) =>
                _showContextMenu(context, details.globalPosition),
            onLongPress: () {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null) {
                final pos = box.localToGlobal(box.size.bottomLeft(Offset.zero));
                _showContextMenu(context, pos);
              }
            },
            child: Material(
              color: bgColor,
              child: InkWell(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: isActive ? scheme.primary : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPendingCopy)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 1.8),
                        )
                      else
                        Tooltip(
                          message: isRunning ? I18n.stop.tr : I18n.run.tr,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => onTogglePower(!isRunning),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.power_settings_new_rounded,
                                size: 18,
                                color: stateColor,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      StyledTypographyText(
                        script.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w500,
                          color: isActive ? scheme.primary : null,
                        ),
                      ),
                      if (isLinked)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.link_rounded,
                            size: 12,
                            color: scheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset globalPos) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) {
      return;
    }
    final isLinkMode = controller.isLinkModeEnabled.value;
    final isLinked = controller.isScriptLinked(script.name);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        if (isLinkMode)
          PopupMenuItem<String>(
            value: 'toggle_link',
            child: Text(isLinked ? '移出联动列表' : '加入联动列表'),
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
    );
    switch (selected) {
      case 'toggle_link':
        controller.setScriptLinked(script.name, !isLinked);
        break;
      case 'rename':
        onRename();
        break;
      case 'delete':
        onDelete();
        break;
    }
  }
}

class _RailActionButton extends StatelessWidget {
  const _RailActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.loading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 19),
      ),
    );
  }
}
