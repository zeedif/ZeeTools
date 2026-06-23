import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '/inject_dependencies.dart';
import '../../repositories/layout_repo.dart';
import '../models/speed_dial_action.dart';

class LayoutView extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const LayoutView({super.key, required this.navigationShell});

  @override
  State<LayoutView> createState() => _LayoutViewState();
}

class _LayoutViewState extends State<LayoutView> {
  final _repo = getIt<LayoutRepository>();
  late final _widthNotifier = ValueNotifier<double>(_repo.getSidebarWidth());
  late final _sidePanelNotifier = ValueNotifier<bool>(_repo.getPreferSidePanel());

  @override
  void dispose() {
    _widthNotifier.dispose();
    _sidePanelNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size(:width, :shortestSide) = MediaQuery.sizeOf(context);
    final isCompact = width < 600 || shortestSide < 480;

    return ValueListenableBuilder<bool>(
      valueListenable: _sidePanelNotifier,
      builder: (context, preferSidePanel, _) {
        final showSidePanel = !isCompact && preferSidePanel;

        return Scaffold(
          body: Row(
            children: [
              if (showSidePanel)
                ValueListenableBuilder<double>(
                  valueListenable: _widthNotifier,
                  builder: (context, currentWidth, _) {
                    final isExtended = currentWidth >= 168;

                    return Row(
                      children: [
                        SizedBox(
                          width: currentWidth,
                          child: NavigationRail(
                            selectedIndex: widget.navigationShell.currentIndex,
                            onDestinationSelected: (index) => widget.navigationShell.goBranch(
                              index,
                              initialLocation: index == widget.navigationShell.currentIndex,
                            ),
                            extended: isExtended,
                            labelType: isExtended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                            scrollable: true,
                            destinations: const [
                              NavigationRailDestination(
                                icon: Icon(Icons.handyman_outlined),
                                selectedIcon: Icon(Icons.handyman),
                                label: Text('Herramientas'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.settings_outlined),
                                selectedIcon: Icon(Icons.settings),
                                label: Text('Ajustes'),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragUpdate: (details) {
                            _widthNotifier.value = (_widthNotifier.value + details.delta.dx).clamp(96.0, 252.0);
                          },
                          onHorizontalDragEnd: (_) => _repo.saveSidebarWidth(_widthNotifier.value),
                          onHorizontalDragCancel: () => _repo.saveSidebarWidth(_widthNotifier.value),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeLeftRight,
                            child: Container(
                              width: 4,
                              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              Expanded(child: widget.navigationShell),
            ],
          ),
          bottomNavigationBar: showSidePanel
              ? null
              : NavigationBar(
                  selectedIndex: widget.navigationShell.currentIndex,
                  onDestinationSelected: (index) => widget.navigationShell.goBranch(
                    index,
                    initialLocation: index == widget.navigationShell.currentIndex,
                  ),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.handyman_outlined),
                      selectedIcon: Icon(Icons.handyman),
                      label: 'Herramientas',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: 'Ajustes',
                    ),
                  ],
                ),
          floatingActionButton: ValueListenableBuilder<List<SpeedDialAction>>(
            valueListenable: getIt<ValueNotifier<List<SpeedDialAction>>>(),
            builder: (context, extraActions, _) {
              final actions = <SpeedDialAction>[
                if (!isCompact)
                  SpeedDialAction(
                    icon: preferSidePanel ? Icons.subtitles : Icons.view_sidebar,
                    label: preferSidePanel ? 'Cambiar a diseño inferior' : 'Cambiar a diseño lateral',
                    onPressed: () {
                      final newVal = !preferSidePanel;
                      _sidePanelNotifier.value = newVal;
                      _repo.savePreferSidePanel(newVal);
                    },
                  ),
                ...extraActions,
              ];

              if (isCompact && actions.isEmpty) return const SizedBox.shrink();

              return _SpeedDial(actions: actions);
            },
          ),
        );
      },
    );
  }
}

class _SpeedDial extends StatefulWidget {
  final List<SpeedDialAction> actions;

  const _SpeedDial({required this.actions});

  @override
  State<_SpeedDial> createState() => _SpeedDialState();
}

class _SpeedDialState extends State<_SpeedDial> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_controller.isDismissed) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  Widget _buildAnimatedItem(Widget child, int index, int total) {
    // Items closest to the FAB (highest index) animate first when opening.
    final double start = total > 1 ? (total - 1 - index) / total * 0.4 : 0.0;
    final double end = (start + 0.6).clamp(0.0, 1.0);

    final curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutBack),
    );

    // SizeTransition collapses height to zero when closed so items take no space.
    // bottomRight alignment keeps content right-aligned as height grows.
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      ),
      alignment: Alignment.bottomRight,
      child: FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.7, end: 1.0).animate(curve),
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow(SpeedDialAction action) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Card(
          elevation: 2,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: InkWell(
            onTap: () {
              _toggle();
              action.onPressed();
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                action.label,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Right padding compensates for size difference: (56 - 40) / 2 = 8
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: FloatingActionButton.small(
            heroTag: null,
            onPressed: () {
              _toggle();
              action.onPressed();
            },
            child: Icon(action.icon),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.actions.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // AnimatedBuilder ensures IgnorePointer re-evaluates on every animation tick.
        AnimatedBuilder(
          animation: _controller,
          builder: (_, child) => IgnorePointer(
            ignoring: _controller.isDismissed,
            child: child,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(
              total,
              (i) => _buildAnimatedItem(_buildActionRow(widget.actions[i]), i, total),
            ),
          ),
        ),
        FloatingActionButton(
          onPressed: _toggle,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, _) => Transform.rotate(
              angle: _controller.value * (math.pi * 0.75),
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ],
    );
  }
}
