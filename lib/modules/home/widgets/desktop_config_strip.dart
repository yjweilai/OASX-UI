import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/common/models/config_drag_payload.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/translation/i18n_content.dart';

/// Top horizontal configuration strip for the desktop bento workbench.
class DesktopConfigStrip extends StatefulWidget {
  const DesktopConfigStrip({
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
  State<DesktopConfigStrip> createState() => _DesktopConfigStripState();
}

class _DesktopConfigStripState extends State<DesktopConfigStrip> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final target =
        (position.pixels + delta).clamp(0.0, position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          _StripIconButton(
            icon: Icons.chevron_left_rounded,
            tooltip: '向左滚动',
            onPressed: () => _scrollBy(-220),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Obx(() {
              final scripts = widget.controller.visibleScripts;
              final activeName = widget.controller.activeScriptName.value;
              final isLinkMode = widget.controller.isLinkModeEnabled.value;
              if (scripts.isEmpty) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    I18n.homeNoScriptSelected.tr,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                );
              }
              return ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                itemCount: scripts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final script = scripts[index];
                  final isActive = script.name == activeName;
                  final isLinked =
                      isLinkMode && widget.controller.isScriptLinked(script.name);
                  return _ConfigStripPill(
                    controller: widget.controller,
                    script: script,
                    isActive: isActive,
                    isLinked: isLinked,
                    onTap: () => widget.onActivateScript(script.name),
                    onTogglePower: (enable) =>
                        widget.onTogglePower(script.name, enable),
                    onRename: () => widget.onRenameScript(script.name),
                    onDelete: () => widget.onDeleteScript(script.name),
                  );
                },
              );
            }),
          ),
          const SizedBox(width: 4),
          _StripIconButton(
            icon: Icons.chevron_right_rounded,
            tooltip: '向右滚动',
            onPressed: () => _scrollBy(220),
          ),
          const SizedBox(width: 6),
          _StripIconButton(
            icon: Icons.add_rounded,
            tooltip: '新增配置',
            loading: widget.loadingAddScript,
            onPressed: widget.onAddScriptTap,
          ),
          _StripIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '刷新',
            loading: widget.refreshingScripts,
            onPressed: widget.onRefreshScriptsTap,
          ),
          Obx(() {
            final currentFilter = widget.controller.stateFilter.value;
            final isLinkMode = widget.controller.isLinkModeEnabled.value;
            return PopupMenuButton<String>(
              tooltip: '筛选与联动',
              icon: Icon(
                Icons.tune_rounded,
                size: 20,
                color: currentFilter != HomeScriptStateFilter.all || isLinkMode
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'all':
                    widget.controller
                        .setStateFilterValue(HomeScriptStateFilter.all);
                    break;
                  case 'running':
                    widget.controller
                        .setStateFilterValue(HomeScriptStateFilter.running);
                    break;
                  case 'abnormal':
                    widget.controller
                        .setStateFilterValue(HomeScriptStateFilter.abnormal);
                    break;
                  case 'stopped':
                    widget.controller
                        .setStateFilterValue(HomeScriptStateFilter.stopped);
                    break;
                  case 'link':
                    widget.controller.toggleLinkMode();
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
                  checked: currentFilter == HomeScriptStateFilter.running,
                  child: const Text('仅看运行中'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'abnormal',
                  checked: currentFilter == HomeScriptStateFilter.abnormal,
                  child: const Text('仅看异常'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'stopped',
                  checked: currentFilter == HomeScriptStateFilter.stopped,
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
    );
  }
}

class _ConfigStripPill extends StatelessWidget {
  const _ConfigStripPill({
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
      onWillAcceptWithDetails: (details) =>
          details.data.canDropOn(script.name),
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
              ? scheme.primary.withValues(alpha: 0.16)
              : isActive
                  ? scheme.primary.withValues(alpha: isDark ? 0.22 : 0.10)
                  : (theme.cardTheme.color ?? (isDark ? const Color(0xFF22242A) : Colors.white));
          final borderColor = isDropHover
              ? scheme.primary
              : isActive
                  ? scheme.primary.withValues(alpha: 0.45)
                  : (isDark
                      ? const Color(0xFF32353E)
                      : const Color(0xFFE3E6EE));
          final dotColor = switch (state) {
            ScriptState.running => const Color(0xFF22C55E),
            ScriptState.warning => const Color(0xFFF59E0B),
            ScriptState.updating => const Color(0xFF3B82F6),
            ScriptState.inactive => scheme.outline.withValues(alpha: 0.55),
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
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPendingCopy)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.8),
                        )
                      else
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                            boxShadow: isRunning
                                ? [
                                    BoxShadow(
                                      color: dotColor.withValues(alpha: 0.45),
                                      blurRadius: 5,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        script.name,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w500,
                          color: isActive ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                      if (isLinked) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.link_rounded,
                          size: 14,
                          color: scheme.primary,
                        ),
                      ],
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          tooltip: isRunning ? I18n.stop.tr : I18n.run.tr,
                          color: isRunning
                              ? const Color(0xFFDC2626)
                              : scheme.onSurfaceVariant,
                          onPressed: () => onTogglePower(!isRunning),
                          icon: const Icon(Icons.power_settings_new_rounded),
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

class _StripIconButton extends StatelessWidget {
  const _StripIconButton({
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
      width: 34,
      height: 34,
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
