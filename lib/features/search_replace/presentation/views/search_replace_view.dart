import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '/inject_dependencies.dart';
import '/common/epub/models/epub_manifest_item.dart';
import '/common/epub/models/epub_source.dart';
import '/common/epub/models/loaded_epub.dart';
import '/common/widgets/resizable_split_panel.dart';
import '/common/widgets/selection_pill.dart';
import '/common/widgets/speed_dial.dart';
import '/common/widgets/svg_icon.dart';
import '../cubit/search_replace_cubit.dart';
import '../../domain/file_selection_profile.dart';
import '../../domain/match_result.dart';
import 'widgets/epub_list_widget.dart';
import 'widgets/file_selector_widget.dart';
import 'widgets/match_list_widget.dart';
import 'widgets/regex_text_field.dart';

class SearchReplaceView extends StatelessWidget {
  const SearchReplaceView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SearchReplaceCubit>(),
      child: const _SearchReplaceContent(),
    );
  }
}

class _SearchReplaceContent extends StatefulWidget {
  const _SearchReplaceContent();

  @override
  State<_SearchReplaceContent> createState() => _SearchReplaceContentState();
}

class _SearchReplaceContentState extends State<_SearchReplaceContent> {
  final _fabNotifier = getIt<ValueNotifier<List<SpeedDialAction>>>();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleShortcut);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleShortcut);
    // TODO: lograr que se limpie antes de cerrar los elementos.
    // Diferir la limpieza al siguiente frame — el árbol está bloqueado durante dispose.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fabNotifier.value = [];
    });
    super.dispose();
  }

  // Mismos atajos que el widget de búsqueda de VS Code (Alt en Windows/Linux,
  // Cmd+Alt en macOS para los toggles; Ctrl+F es igual en las tres plataformas).
  bool _handleShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final cubit = context.read<SearchReplaceCubit>();
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.keyF && HardwareKeyboard.instance.isControlPressed) {
      cubit.focusSearchField();
      return true;
    }

    final altCombo = defaultTargetPlatform == TargetPlatform.macOS
        ? HardwareKeyboard.instance.isMetaPressed && HardwareKeyboard.instance.isAltPressed
        : HardwareKeyboard.instance.isAltPressed;
    if (!altCombo) return false;

    switch (key) {
      case LogicalKeyboardKey.keyC:
        cubit.toggleCaseSensitivity();
        return true;
      case LogicalKeyboardKey.keyW:
        cubit.toggleWholeWord();
        return true;
      case LogicalKeyboardKey.keyR:
        cubit.toggleRegexMode();
        return true;
      case LogicalKeyboardKey.keyP:
        cubit.togglePreserveCase();
        return true;
      default:
        return false;
    }
  }

  void _updateFab(SearchReplaceState state) {
    _fabNotifier.value =
        state.mapOrNull(
          ready: (_) => [
            SpeedDialAction(
              icon: Icons.file_open_outlined,
              label: 'Añadir archivos EPUB…',
              onPressed: _addFiles,
            ),
            SpeedDialAction(
              icon: Icons.folder_outlined,
              label: 'Añadir EPUBs de una carpeta…',
              onPressed: _addDirectory,
            ),
            SpeedDialAction(
              icon: Icons.folder_copy_outlined,
              label: 'Añadir EPUBs de carpeta y subcarpetas…',
              onPressed: _addDirectoryRecursive,
            ),
          ],
        ) ??
        [];
  }

  Future<void> _addFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      dialogTitle: 'Agregar EPUB(s)',
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    );
    final paths = files.map((f) => f.path).whereType<String>().toList();
    if (paths.isNotEmpty && mounted) {
      context.read<SearchReplaceCubit>().addSources(EpubSource.files(paths));
    }
  }

  Future<void> _addDirectory({bool recursive = false}) async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Agregar carpeta con EPUBs',
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    );
    if (path != null && mounted) {
      context.read<SearchReplaceCubit>().addSources(
        EpubSource.directory(path, recursive: recursive),
      );
    }
  }

  Future<void> _addDirectoryRecursive() => _addDirectory(recursive: true);

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SearchReplaceCubit, SearchReplaceState>(
      listener: (context, state) {
        _updateFab(state);
        _handleSnackbars(context, state);
      },
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: const Text('Búsqueda y Reemplazo'),
          actions: const [_AppBarActions()],
        ),
        body:
            state.mapOrNull(
              idle: (_) => _IdlePane(onLoad: context.read<SearchReplaceCubit>().loadSources),
              loading: (s) => _LoadingPane(message: s.message),
              failure: (s) => _FailurePane(message: s.message),
            ) ??
            const _ReadyPane(),
      ),
    );
  }

  void _handleSnackbars(BuildContext context, SearchReplaceState state) {
    state.mapOrNull(
      ready: (s) {
        if (s.isSaved) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('EPUB(s) guardado(s) correctamente')),
          );
        }
        if (s.lastReplacedCount != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${s.lastReplacedCount} reemplazo${s.lastReplacedCount == 1 ? '' : 's'} realizados',
              ),
            ),
          );
        }
        if (s.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Theme.of(context).colorScheme.error,
              content: Text(s.errorMessage!),
            ),
          );
        }
      },
    );
  }
}

// ── AppBar ───────────────────────────────────────────────────────────────────

typedef _AppBarData = ({bool isProcessing, bool isMultiView, LoadedEpub? singleEpub, int? epubIndex});

class _AppBarActions extends StatelessWidget {
  const _AppBarActions();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SearchReplaceCubit>();
    return BlocSelector<SearchReplaceCubit, SearchReplaceState, _AppBarData?>(
      selector: (state) => state.mapOrNull(
        ready: (s) => (
          isProcessing: s.isProcessing,
          isMultiView: s.epubs.length > 1 && s.focusedEpubIndex == null,
          singleEpub: s.focusedEpubIndex != null ? s.epubs[s.focusedEpubIndex!] : (s.epubs.length == 1 ? s.epubs.first : null),
          epubIndex: s.focusedEpubIndex ?? (s.epubs.length == 1 ? 0 : null),
        ),
      ),
      builder: (context, data) {
        if (data == null) return const SizedBox.shrink();
        final singleEpub = data.singleEpub;

        return Row(
          children: [
            if (data.isProcessing)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (data.isMultiView)
              IconButton(
                icon: const Icon(Icons.save_outlined),
                tooltip: 'Guardar todos',
                onPressed: data.isProcessing ? null : () => cubit.save(),
              )
            else if (singleEpub != null) ...[
              IconButton(
                icon: const Icon(Icons.save_outlined),
                tooltip: 'Guardar',
                onPressed: data.isProcessing ? null : () => cubit.save(epubIndex: data.epubIndex),
              ),
              IconButton(
                icon: const Icon(Icons.save_as_outlined),
                tooltip: 'Guardar como…',
                onPressed: data.isProcessing
                    ? null
                    : () async {
                        final bytes = await cubit.exportEpub(singleEpub);
                        if (bytes == null || cubit.isClosed) return;
                        final uri = await FilePicker.saveFile(
                          dialogTitle: 'Guardar EPUB como',
                          fileName: singleEpub.displayName,
                          bytes: bytes,
                          windowsOptions: const WindowsOptions(lockParentWindow: true),
                          linuxOptions: const LinuxOptions(lockParentWindow: true),
                        );
                        if (uri != null && !cubit.isClosed) cubit.markSaved();
                      },
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Panes ─────────────────────────────────────────────────────────────────────

class _LoadingPane extends StatelessWidget {
  const _LoadingPane({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _FailurePane extends StatelessWidget {
  const _FailurePane({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.error),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.read<SearchReplaceCubit>().resetToIdle(),
              child: const Text('Volver al inicio'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdlePane extends StatefulWidget {
  const _IdlePane({required this.onLoad});
  final ValueChanged<EpubSource> onLoad;

  @override
  State<_IdlePane> createState() => _IdlePaneState();
}

class _IdlePaneState extends State<_IdlePane> {
  bool _recursive = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_outlined, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          const Text('Ningún EPUB cargado', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Abrir archivo(s)…'),
                onPressed: () async {
                  final files = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['epub'],
                    dialogTitle: 'Seleccionar EPUB(s)',
                    windowsOptions: const WindowsOptions(lockParentWindow: true),
                    linuxOptions: const LinuxOptions(lockParentWindow: true),
                  );
                  final paths = files.map((f) => f.path).whereType<String>().toList();
                  if (paths.isNotEmpty) {
                    widget.onLoad(EpubSource.files(paths));
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Abrir directorio…'),
                onPressed: () async {
                  final path = await FilePicker.getDirectoryPath(
                    dialogTitle: 'Seleccionar carpeta con EPUBs',
                    windowsOptions: const WindowsOptions(lockParentWindow: true),
                    linuxOptions: const LinuxOptions(lockParentWindow: true),
                  );
                  if (path != null) {
                    widget.onLoad(EpubSource.directory(path, recursive: _recursive));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: _recursive, onChanged: (v) => setState(() => _recursive = v)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _recursive = !_recursive),
                child: Text('Incluir subcarpetas', style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Router de vistas ─────────────────────────────────────────────────────────
//
// A partir de aquí, cada widget lee del cubit lo que necesita mediante su
// propio BlocSelector en vez de recibir el SearchReplaceState completo por
// constructor: así cada uno se reconstruye solo cuando cambia el fragmento de
// estado que realmente usa, no cada vez que cambia cualquier otro campo
// (p. ej. teclear en el buscador ya no reconstruye el panel de archivos).

typedef _ReadyRouting = ({int? focusedEpubIndex, int epubsLength});

class _ReadyPane extends StatelessWidget {
  const _ReadyPane();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SearchReplaceCubit, SearchReplaceState, _ReadyRouting?>(
      selector: (state) => state.mapOrNull(ready: (s) => (focusedEpubIndex: s.focusedEpubIndex, epubsLength: s.epubs.length)),
      builder: (context, routing) {
        if (routing == null) return const SizedBox.shrink();
        if (routing.focusedEpubIndex != null) {
          return _SingleEpubView(epubIndex: routing.focusedEpubIndex!, showBack: true);
        }
        if (routing.epubsLength == 1) {
          return const _SingleEpubView(epubIndex: 0, showBack: false);
        }
        return const _MultiEpubView();
      },
    );
  }
}

// Material+InkWell rectangular a todo el ancho para que el ripple cubra la barra completa.
class _BackBar extends StatelessWidget {
  const _BackBar({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      child: SizedBox(
        width: double.infinity,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Vista individual ──────────────────────────────────────────────────────────

typedef _FileSelectorData = ({
  List<EpubManifestItem> files,
  List<String>? selectedIds,
  List<FileSelectionProfile> pillOrder,
  bool groupByPillOrder,
  bool sortAscending,
  int epubsLength,
});

class _SingleEpubView extends StatelessWidget {
  const _SingleEpubView({required this.epubIndex, required this.showBack});

  final int epubIndex;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SearchReplaceCubit>();
    return BlocSelector<SearchReplaceCubit, SearchReplaceState, _FileSelectorData?>(
      selector: (state) => state.mapOrNull(
        ready: (s) => (
          files: s.epubs[epubIndex].files,
          selectedIds: s.epubs[epubIndex].selectedFileIds,
          pillOrder: s.pillOrder,
          groupByPillOrder: s.groupFilesByPillOrder,
          sortAscending: s.sortAscending,
          epubsLength: s.epubs.length,
        ),
      ),
      builder: (context, data) {
        if (data == null) return const SizedBox.shrink();
        return Column(
          children: [
            if (showBack) _BackBar(label: 'Volver · ${data.epubsLength} EPUBs', onTap: cubit.unfocusEpub),
            Expanded(
              child: ResizableSplitPanel(
                maxWidth: 320,
                panel: FileSelectorWidget(
                  files: data.files,
                  selectedIds: data.selectedIds, // List<String>? — nullable
                  onSelectionChanged: (ids) => cubit.changeEpubFileSelection(epubIndex, ids),
                  pillOrder: data.pillOrder,
                  onReorderPills: cubit.reorderPills,
                  groupByPillOrder: data.groupByPillOrder,
                  onToggleGroupByPillOrder: cubit.toggleGroupFilesByPillOrder,
                  sortAscending: data.sortAscending,
                  onToggleSortAscending: cubit.toggleSortAscending,
                ),
                body: const _SearchPanel(alwaysShowEpubHeader: false),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Vista multi ───────────────────────────────────────────────────────────────

typedef _MultiEpubData = ({List<LoadedEpub> epubs, List<FileSelectionProfile> pillOrder, bool sortAscending});

class _MultiEpubView extends StatelessWidget {
  const _MultiEpubView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SearchReplaceCubit>();
    return BlocSelector<SearchReplaceCubit, SearchReplaceState, _MultiEpubData?>(
      selector: (state) => state.mapOrNull(ready: (s) => (epubs: s.epubs, pillOrder: s.pillOrder, sortAscending: s.sortAscending)),
      builder: (context, data) {
        if (data == null) return const SizedBox.shrink();
        return ResizableSplitPanel(
          maxWidth: 320,
          panel: EpubListWidget(epubs: data.epubs, pillOrder: data.pillOrder, sortAscending: data.sortAscending, cubit: cubit),
          body: const _SearchPanel(alwaysShowEpubHeader: true),
        );
      },
    );
  }
}

// ── Panel de búsqueda (compartido) ────────────────────────────────────────────

typedef _ResultsData = ({
  List<EpubSearchResult> results,
  int totalMatches,
  String replacePattern,
  bool isProcessing,
  String searchPattern,
  bool hasSearched,
});

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({required this.alwaysShowEpubHeader});
  final bool alwaysShowEpubHeader;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SearchReplaceCubit>();
    return Column(
      children: [
        const Padding(padding: EdgeInsets.all(16), child: _SearchForm()),
        const Divider(height: 1),
        Expanded(
          child: BlocSelector<SearchReplaceCubit, SearchReplaceState, _ResultsData?>(
            selector: (state) => state.mapOrNull(
              ready: (s) => (
                results: s.results,
                totalMatches: s.totalMatches,
                replacePattern: s.replacePattern,
                isProcessing: s.isProcessing,
                searchPattern: s.searchPattern,
                hasSearched: s.hasSearched,
              ),
            ),
            builder: (context, data) {
              if (data == null) return const SizedBox.shrink();
              if (data.results.isEmpty && !data.isProcessing) {
                final message = switch ((data.searchPattern.isEmpty, data.hasSearched)) {
                  (true, _) => 'Introduce un patrón de búsqueda',
                  (false, false) => 'Pulsa buscar (Ctrl+Enter) para ver coincidencias',
                  (false, true) => 'Sin resultados',
                };
                return Center(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                );
              }
              return MatchListWidget(
                results: data.results,
                totalMatches: data.totalMatches,
                replacePattern: data.replacePattern,
                cubit: cubit,
                alwaysShowEpubHeader: alwaysShowEpubHeader,
              );
            },
          ),
        ),
      ],
    );
  }
}

typedef _SearchFormData = ({
  String searchPattern,
  String replacePattern,
  bool isRegexMode,
  bool isCaseSensitive,
  bool isWholeWord,
  bool preserveCase,
  String? patternError,
  bool isProcessing,
  bool resultsEmpty,
});

class _SearchForm extends StatefulWidget {
  const _SearchForm();

  @override
  State<_SearchForm> createState() => _SearchFormState();
}

class _SearchFormState extends State<_SearchForm> {
  final _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SearchReplaceCubit>();
    final cs = Theme.of(context).colorScheme;
    return BlocListener<SearchReplaceCubit, SearchReplaceState>(
      listenWhen: (previous, current) => previous.mapOrNull(ready: (s) => s.focusSearchToken) != current.mapOrNull(ready: (s) => s.focusSearchToken),
      listener: (context, state) => _searchFocusNode.requestFocus(),
      child: BlocSelector<SearchReplaceCubit, SearchReplaceState, _SearchFormData?>(
        selector: (state) => state.mapOrNull(
          ready: (s) => (
            searchPattern: s.searchPattern,
            replacePattern: s.replacePattern,
            isRegexMode: s.isRegexMode,
            isCaseSensitive: s.isCaseSensitive,
            isWholeWord: s.isWholeWord,
            preserveCase: s.preserveCase,
            patternError: s.patternError,
            isProcessing: s.isProcessing,
            resultsEmpty: s.results.isEmpty,
          ),
        ),
        builder: (context, s) {
          if (s == null) return const SizedBox.shrink();
          final canSearch = s.patternError == null && s.searchPattern.isNotEmpty && !s.isProcessing;
          final canReplace = canSearch && !s.resultsEmpty;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RegexTextField(
                label: 'Buscar',
                focusNode: _searchFocusNode,
                isRegexMode: s.isRegexMode,
                errorText: s.patternError,
                initialValue: s.searchPattern,
                hintText: s.isRegexMode ? r'(\w+)\s+\1' : 'Texto a buscar…',
                onChanged: cubit.changePattern,
                onSubmit: canSearch ? cubit.executeSearch : null,
                suffixIcons: [
                  SelectionPill(
                    dense: true,
                    selected: s.isRegexMode,
                    tooltip: 'Modo Regex (Alt+R)',
                    onTap: cubit.toggleRegexMode,
                    child: const SvgIcon('assets/icons/regex.svg'),
                  ),
                  SelectionPill(
                    dense: true,
                    selected: s.isCaseSensitive,
                    tooltip: 'Coincidir mayúsculas y minúsculas (Alt+C)',
                    onTap: cubit.toggleCaseSensitivity,
                    child: const SvgIcon('assets/icons/case-sensitive.svg'),
                  ),
                  SelectionPill(
                    dense: true,
                    selected: s.isWholeWord,
                    tooltip: 'Solo palabras completas (Alt+W)',
                    onTap: cubit.toggleWholeWord,
                    child: const SvgIcon('assets/icons/whole-word.svg'),
                  ),
                  _SuffixIconButton(
                    icon: Icons.search,
                    tooltip: 'Buscar (Ctrl+F)',
                    onTap: canSearch ? cubit.executeSearch : null,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              RegexTextField(
                label: 'Reemplazar',
                isRegexMode: false,
                initialValue: s.replacePattern,
                hintText: r'Usa $1, ${nombre} para grupos; $$ para $ literal',
                onChanged: cubit.changeReplacement,
                onSubmit: canReplace ? cubit.replaceAll : null,
                suffixIcons: [
                  SelectionPill(
                    dense: true,
                    selected: s.preserveCase,
                    tooltip: 'Conservar mayúsculas/minúsculas (Alt+P)',
                    onTap: cubit.togglePreserveCase,
                    child: const SvgIcon('assets/icons/preserve-case.svg'),
                  ),
                  _SuffixIconButton(
                    icon: Icons.find_replace_rounded,
                    tooltip: 'Reemplazar todo',
                    color: cs.error,
                    onTap: canReplace ? cubit.replaceAll : null,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// Botón de acción para RegexTextField.suffixIcons.
class _SuffixIconButton extends StatelessWidget {
  const _SuffixIconButton({required this.icon, required this.tooltip, required this.onTap, this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = onTap != null ? (color ?? cs.onSurfaceVariant) : cs.outlineVariant;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Icon(icon, size: 18, color: tint),
        ),
      ),
    );
  }
}
