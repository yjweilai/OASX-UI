import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/common/widgets/styled_typography_text.dart';
import 'package:oasx/service/game_preview_service.dart';

/// Renders all currently open multi-config floating game preview windows.
class FloatingGamePreviewLayer extends StatefulWidget {
  const FloatingGamePreviewLayer({super.key});

  @override
  State<FloatingGamePreviewLayer> createState() =>
      _FloatingGamePreviewLayerState();
}

class _FloatingGamePreviewLayerState extends State<FloatingGamePreviewLayer> {
  final Map<String, Offset> _positions = <String, Offset>{};
  final Map<String, Size> _sizes = <String, Size>{};

  static const double _kDefaultWidth = 340;
  static const double _kDefaultHeight = 220;
  static const double _kMinWidth = 220;
  static const double _kMinHeight = 152;
  static const double _kMaxWidth = 860;
  static const double _kMaxHeight = 540;

  GamePreviewService get _service => Get.find<GamePreviewService>();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Size(constraints.maxWidth, constraints.maxHeight);
        return Obx(() {
          final openScripts = _service.openFloatingScripts.toList();
          if (openScripts.isEmpty) {
            return const SizedBox.shrink();
          }
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (int i = 0; i < openScripts.length; i++)
                _buildWindow(openScripts[i], i, bounds),
            ],
          );
        });
      },
    );
  }

  Widget _buildWindow(String scriptName, int index, Size bounds) {
    final size = _sizes.putIfAbsent(
      scriptName,
      () => const Size(_kDefaultWidth, _kDefaultHeight),
    );
    final rawPos = _positions.putIfAbsent(
      scriptName,
      () {
        final stagger = (index % 5) * 28.0;
        final x = (bounds.width - size.width - 24 - stagger)
            .clamp(12.0, (bounds.width - size.width - 8).clamp(12.0, double.infinity));
        final y = (bounds.height - size.height - 24 - stagger)
            .clamp(12.0, (bounds.height - size.height - 8).clamp(12.0, double.infinity));
        return Offset(x, y);
      },
    );

    final clampedWidth =
        size.width.clamp(_kMinWidth, bounds.width.clamp(_kMinWidth, _kMaxWidth));
    final clampedHeight = size.height
        .clamp(_kMinHeight, bounds.height.clamp(_kMinHeight, _kMaxHeight));
    final maxX = (bounds.width - clampedWidth - 6).clamp(6.0, double.infinity);
    final maxY = (bounds.height - clampedHeight - 6).clamp(6.0, double.infinity);
    final pos = Offset(
      rawPos.dx.clamp(6.0, maxX),
      rawPos.dy.clamp(6.0, maxY),
    );

    return Positioned(
      key: ValueKey<String>('floating-preview-$scriptName'),
      left: pos.dx,
      top: pos.dy,
      width: clampedWidth,
      height: clampedHeight,
      child: _FloatingGamePreviewWindow(
        scriptName: scriptName,
        onBringToFront: () => _service.bringFloatingToFront(scriptName),
        onDragDelta: (delta) {
          setState(() {
            final current = _positions[scriptName] ?? pos;
            _positions[scriptName] = Offset(
              (current.dx + delta.dx).clamp(6.0, maxX),
              (current.dy + delta.dy).clamp(6.0, maxY),
            );
          });
        },
        onResizeDelta: (delta) {
          setState(() {
            final current = _sizes[scriptName] ?? size;
            final nextW = (current.width + delta.dx).clamp(
              _kMinWidth,
              (bounds.width - pos.dx - 6).clamp(_kMinWidth, _kMaxWidth),
            );
            final nextH = (current.height + delta.dy).clamp(
              _kMinHeight,
              (bounds.height - pos.dy - 6).clamp(_kMinHeight, _kMaxHeight),
            );
            _sizes[scriptName] = Size(nextW, nextH);
          });
        },
        onClose: () => _service.closeFloatingPreview(scriptName),
      ),
    );
  }
}

class _FloatingGamePreviewWindow extends StatelessWidget {
  const _FloatingGamePreviewWindow({
    required this.scriptName,
    required this.onBringToFront,
    required this.onDragDelta,
    required this.onResizeDelta,
    required this.onClose,
  });

  final String scriptName;
  final VoidCallback onBringToFront;
  final ValueChanged<Offset> onDragDelta;
  final ValueChanged<Offset> onResizeDelta;
  final VoidCallback onClose;

  GamePreviewService get _service => Get.find<GamePreviewService>();

  @override
  Widget build(BuildContext context) {
    final session = _service.sessionFor(scriptName);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Listener(
      onPointerDown: (_) => onBringToFront(),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.45),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.42),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              // Draggable mini title bar
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => onBringToFront(),
                onPanUpdate: (details) => onDragDelta(details.delta),
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.16),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Obx(() {
                      final streaming = session.isStreaming.value;
                      final capturing = session.isCapturing.value;
                      return Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: streaming
                                  ? const Color(0xFF22C55E)
                                  : Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: StyledTypographyText(
                              '$scriptName · 画面预览',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          _FloatingTitleIcon(
                            icon: streaming
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            tooltip: streaming ? '暂停刷新' : '恢复刷新',
                            onTap: () =>
                                _service.toggleSessionPolling(scriptName),
                          ),
                          _FloatingTitleIcon(
                            icon: Icons.refresh_rounded,
                            tooltip: '立即抓帧',
                            spinning: capturing,
                            onTap: () => _service.captureSessionOnce(scriptName),
                          ),
                          _FloatingTitleIcon(
                            icon: Icons.tune_rounded,
                            tooltip: '绑定窗口 / 预览设置',
                            onTap: () => _openSettings(context),
                          ),
                          _FloatingTitleIcon(
                            icon: Icons.close_rounded,
                            tooltip: '关闭悬浮预览',
                            onTap: onClose,
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
              // Live frame area + bottom-right resize grip
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Obx(() {
                      final bytes = session.frameBytes.value;
                      final error = session.lastError.value;
                      final capturing = session.isCapturing.value;
                      if (bytes != null) {
                        return Container(
                          color: Colors.black,
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        );
                      }
                      if (error.isNotEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 22,
                                color: scheme.error,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                error,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                        color: Colors.white.withValues(alpha: 0.35),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.zero,
                                      ),
                                    ),
                                    onPressed: () =>
                                        _service.captureSessionOnce(scriptName),
                                    child: const Text(
                                      '重试',
                                      style: TextStyle(fontSize: 11.5),
                                    ),
                                  ),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                        color: Colors.white.withValues(alpha: 0.35),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.zero,
                                      ),
                                    ),
                                    onPressed: () => _openSettings(context),
                                    child: const Text(
                                      '选择窗口',
                                      style: TextStyle(fontSize: 11.5),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (capturing)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              )
                            else
                              const Icon(
                                Icons.tv_rounded,
                                size: 22,
                                color: Colors.white54,
                              ),
                            const SizedBox(height: 6),
                            Text(
                              capturing ? '正在获取画面...' : '已暂停预览',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    // Bottom-right subtle resize corner handle
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeUpLeftDownRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) => onBringToFront(),
                          onPanUpdate: (details) =>
                              onResizeDelta(details.delta),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CustomPaint(
                              painter: _ResizeGripPainter(
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _GamePreviewModalDialog(scriptName: scriptName),
    );
  }
}

class _FloatingTitleIcon extends StatelessWidget {
  const _FloatingTitleIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.spinning = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: spinning
                ? const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: Colors.white70,
                    ),
                  )
                : Icon(
                    icon,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ResizeGripPainter extends CustomPainter {
  const _ResizeGripPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width - 4, size.height - 1),
      Offset(size.width - 1, size.height - 4),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 9, size.height - 1),
      Offset(size.width - 1, size.height - 9),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ResizeGripPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Legacy embedded thumbnail kept for compatibility.
class GamePreviewThumbnail extends StatefulWidget {
  const GamePreviewThumbnail({
    super.key,
    required this.scriptName,
    this.squareBorder = false,
  });

  final String scriptName;
  final bool squareBorder;

  @override
  State<GamePreviewThumbnail> createState() => _GamePreviewThumbnailState();
}

class _GamePreviewThumbnailState extends State<GamePreviewThumbnail> {
  GamePreviewService get _service => Get.find<GamePreviewService>();

  @override
  void initState() {
    super.initState();
    unawaited(_service.bindScript(widget.scriptName));
  }

  @override
  void didUpdateWidget(covariant GamePreviewThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scriptName != widget.scriptName) {
      unawaited(_service.bindScript(widget.scriptName));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _service.openFloatingPreview(widget.scriptName),
      child: Container(
        decoration: BoxDecoration(
          borderRadius:
              widget.squareBorder ? BorderRadius.zero : BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: const Center(
          child: Text('点击打开悬浮画面预览', style: TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}

class _GamePreviewModalDialog extends StatefulWidget {
  const _GamePreviewModalDialog({required this.scriptName});

  final String scriptName;

  @override
  State<_GamePreviewModalDialog> createState() =>
      _GamePreviewModalDialogState();
}

class _GamePreviewModalDialogState extends State<_GamePreviewModalDialog> {
  late final TextEditingController _serialCtrl;
  late final TextEditingController _adbCtrl;
  late final TextEditingController _windowCtrl;

  GamePreviewService get _service => Get.find<GamePreviewService>();
  GamePreviewSession get _session => _service.sessionFor(widget.scriptName);

  @override
  void initState() {
    super.initState();
    _serialCtrl = TextEditingController(text: _session.serial.value);
    _adbCtrl = TextEditingController(text: _service.adbPath.value);
    _windowCtrl = TextEditingController(text: _session.windowTitle.value);
    if (_service.mode.value == GamePreviewMode.windowsWindow) {
      unawaited(_service.scanWindows());
    }
  }

  @override
  void dispose() {
    _serialCtrl.dispose();
    _adbCtrl.dispose();
    _windowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isWindows = !kIsWeb && Platform.isWindows;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.tv_rounded, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '画面预览设置 · ${widget.scriptName}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Mode & Interval row
              Obx(() {
                final currentMode = _service.mode.value;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('模拟器 (ADB)'),
                      selected: currentMode == GamePreviewMode.adb,
                      onSelected: (_) => _service.setMode(GamePreviewMode.adb),
                    ),
                    if (isWindows)
                      ChoiceChip(
                        label: const Text('桌面版窗口 (Windows)'),
                        selected: currentMode == GamePreviewMode.windowsWindow,
                        onSelected: (_) =>
                            _service.setMode(GamePreviewMode.windowsWindow),
                      ),
                    const SizedBox(width: 8),
                    const Text('刷新间隔：'),
                    DropdownButton<int>(
                      value: _service.intervalSeconds.value,
                      isDense: true,
                      items: const [1, 2, 3, 5, 10]
                          .map(
                            (sec) => DropdownMenuItem<int>(
                              value: sec,
                              child: Text('$sec 秒'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) _service.setIntervalSeconds(v);
                      },
                    ),
                  ],
                );
              }),
              const SizedBox(height: 12),
              Obx(() {
                final currentMode = _service.mode.value;
                if (currentMode == GamePreviewMode.adb) {
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _serialCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: '设备串口 (serial)',
                            hintText: '如 127.0.0.1:16384',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          onChanged: (v) => _service.setSerial(
                            v,
                            scriptName: widget.scriptName,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _adbCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'adb.exe 路径（留空自动查找）',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          onChanged: _service.setAdbPath,
                        ),
                      ),
                    ],
                  );
                }
                final windows = _service.availableWindows;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _windowCtrl,
                            decoration: InputDecoration(
                              isDense: true,
                              labelText:
                                  '为 ${widget.scriptName} 绑定的窗口标题（精确优先）',
                              hintText: '例如 ${widget.scriptName} 或 阴阳师',
                              border: const OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            onChanged: (v) => _service.setWindowTitle(
                              v,
                              scriptName: widget.scriptName,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _service.scanWindows,
                          icon: const Icon(Icons.search_rounded, size: 16),
                          label: const Text('扫描窗口'),
                        ),
                      ],
                    ),
                    if (windows.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: windows.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (_, idx) {
                            final title = windows[idx];
                            final selected =
                                _session.windowTitle.value == title;
                            return ActionChip(
                              label: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                              onPressed: () {
                                _windowCtrl.text = title;
                                _service.setWindowTitle(
                                  title,
                                  scriptName: widget.scriptName,
                                );
                                unawaited(
                                  _service.captureSessionOnce(widget.scriptName),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                );
              }),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Obx(() {
                    final bytes = _session.frameBytes.value;
                    final error = _session.lastError.value;
                    if (bytes != null) {
                      return InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Center(
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          error.isNotEmpty ? error : '点击下方「立即抓帧」测试当前绑定窗口',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        _service.captureSessionOnce(widget.scriptName),
                    icon: const Icon(Icons.camera_alt_outlined, size: 16),
                    label: const Text('立即抓帧'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
