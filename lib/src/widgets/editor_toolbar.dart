import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme.dart';
import 'layer_ui.dart';

/// The persistent bottom toolbar — the editor's home state, shown whenever
/// nothing is selected: six equal columns, a hairline icon over a word. The
/// slide strip above it carries "+ Slide"; selecting an element swaps both
/// for that element's contextual bar (see [ContextBarShell]).
class EditorToolbar extends StatelessWidget {
  final VoidCallback onLayout;
  final VoidCallback onText;
  final VoidCallback onPhoto;
  final VoidCallback onSticker;
  final VoidCallback onBackground;
  final VoidCallback onLayers;

  const EditorToolbar({
    super.key,
    required this.onLayout,
    required this.onText,
    required this.onPhoto,
    required this.onSticker,
    required this.onBackground,
    required this.onLayers,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: Row(
        children: [
          Expanded(
            child: ToolButton(
              icon: Symbols.title,
              label: 'Text',
              onTap: onText,
            ),
          ),
          Expanded(
            child: ToolButton(
              icon: Symbols.imagesmode,
              label: 'Photo',
              onTap: onPhoto,
            ),
          ),
          Expanded(
            child: ToolButton(
              icon: Symbols.grid_view,
              label: 'Layout',
              onTap: onLayout,
            ),
          ),
          Expanded(
            child: ToolButton(
              icon: Symbols.interests,
              label: 'Assets',
              onTap: onSticker,
            ),
          ),
          Expanded(
            child: ToolButton(
              icon: Symbols.format_paint,
              label: 'Colour',
              onTap: onBackground,
            ),
          ),
          Expanded(
            child: ToolButton(
              icon: Symbols.layers,
              label: 'Layers',
              onTap: onLayers,
            ),
          ),
        ],
      ),
    );
  }
}

/// A labeled hairline icon — the toolbar's building block.
class ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSpace.minTarget,
          minHeight: AppSpace.minTarget,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, weight: 200, color: context.colors.ink),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: AppType.sans(11.5, weight: FontWeight.w500, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frame shared by the contextual bars: an eyebrow naming what is selected
/// ("TEXT · TITLE"), the optional Duplicate / Delete actions and an
/// underlined Done that returns home — so the bottom bar never changes
/// silently. A hairline closes the header; [child] holds the controls.
class ContextBarShell extends StatelessWidget {
  final String title;
  final VoidCallback onDone;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final Widget? child;

  const ContextBarShell({
    super.key,
    required this.title,
    required this.onDone,
    this.onDuplicate,
    this.onDelete,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.paper,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ContextBarHeader(
            title: title,
            onDone: onDone,
            onDuplicate: onDuplicate,
            onDelete: onDelete,
          ),
          ?child,
        ],
      ),
    );
  }
}

/// The header row of every contextual bar (see [ContextBarShell]).
class ContextBarHeader extends StatelessWidget {
  final String title;
  final VoidCallback onDone;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  const ContextBarHeader({
    super.key,
    required this.title,
    required this.onDone,
    this.onDuplicate,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Eyebrow(title, size: 11.5, singleLine: true)),
              if (onDuplicate != null)
                _BarAction(label: 'Duplicate', onTap: onDuplicate!),
              if (onDelete != null)
                _BarAction(label: 'Delete', onTap: onDelete!),
              _BarAction(label: 'Done', onTap: onDone, primary: true),
            ],
          ),
          const Padding(padding: EdgeInsets.only(right: 8), child: Hairline()),
        ],
      ),
    );
  }
}

/// A text action in a bar header: 13/500, inkSoft; Done in ink, underlined.
/// The tooltip doubles as the accessible name and a stable test handle.
class _BarAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _BarAction({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = primary ? context.colors.ink : context.colors.inkSoft;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpace.minTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                widthFactor: 1,
                child: Container(
                  padding: const EdgeInsets.only(bottom: 2),
                  decoration: primary
                      ? BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: context.colors.ink),
                          ),
                        )
                      : null,
                  child: Text(
                    label,
                    style: AppType.sans(
                      13.5,
                      weight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
