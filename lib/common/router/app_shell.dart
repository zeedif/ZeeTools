import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/inject_dependencies.dart';
import '/features/home/data/layout_repo.dart';
import '../widgets/speed_dial.dart';

class AppShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
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

              return SpeedDialFab(actions: actions);
            },
          ),
        );
      },
    );
  }
}
