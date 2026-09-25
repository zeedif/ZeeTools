import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '/inject_dependencies.dart';
import '/common/epub/models/epub_source.dart';
import '/common/epub/models/loaded_epub.dart';
import '/common/widgets/speed_dial.dart';
import '../cubit/search_replace_cubit.dart';
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
  void dispose() {
    // TODO: lograr que se limpie antes de cerrar los elementos.
    // Diferir la limpieza al siguiente frame — el árbol está bloqueado durante dispose.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fabNotifier.value = [];
    });
    super.dispose();
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
          actions: [_AppBarActions(state: state)],
        ),
        body:
            state.mapOrNull(
              idle: (_) => _IdlePane(onLoad: context.read<SearchReplaceCubit>().loadSources),
              loading: (s) => _LoadingPane(message: s.message),
              failure: (s) => _FailurePane(message: s.message),
            ) ??
            _ReadyPane(state: state),
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

class _AppBarActions extends StatelessWidget {
  const _AppBarActions({required this.state});
  final SearchReplaceState state;

  @override
  Widget build(BuildContext context) {
    return state.mapOrNull(
          ready: (s) {
            final cubit = context.read<SearchReplaceCubit>();
            final isMultiView = s.epubs.length > 1 && s.focusedEpubIndex == null;
            final epubIndex = s.focusedEpubIndex ?? (s.epubs.length == 1 ? 0 : null);
            final singleEpub = epubIndex != null ? s.epubs[epubIndex] : null;

            return Row(
              children: [
                if (s.isProcessing)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (isMultiView)
                  IconButton(
                    icon: const Icon(Icons.save_outlined),
                    tooltip: 'Guardar todos',
                    onPressed: s.isProcessing ? null : () => cubit.save(),
                  )
                else if (singleEpub != null) ...[
                  IconButton(
                    icon: const Icon(Icons.save_outlined),
                    tooltip: 'Guardar',
                    onPressed: s.isProcessing ? null : () => cubit.save(epubIndex: epubIndex),
                  ),
                  IconButton(
                    icon: const Icon(Icons.save_as_outlined),
                    tooltip: 'Guardar como…',
                    onPressed: s.isProcessing
                        ? null
                        : () async {
                            final bytes = await cubit.encodeForExport(singleEpub.path);
                            if (bytes == null || !context.mounted) return;
                            final uri = await FilePicker.saveFile(
                              dialogTitle: 'Guardar EPUB como',
                              fileName: singleEpub.displayName,
                              bytes: bytes,
                              windowsOptions: const WindowsOptions(lockParentWindow: true),
                              linuxOptions: const LinuxOptions(lockParentWindow: true),
                            );
                            if (uri != null && context.mounted) {
                              cubit.markSaved();
                            }
                          },
                  ),
                ],
              ],
            );
          },
        ) ??
        const SizedBox.shrink();
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
      children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(message)],
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
          const Text('Ningún EPUB cargado'),
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

class _ReadyPane extends StatelessWidget {
  const _ReadyPane({required this.state});
  final SearchReplaceState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SearchReplaceCubit>();
    return state.mapOrNull(
          ready: (s) {
            if (s.focusedEpubIndex != null) {
              return _SingleEpubView(
                epub: s.epubs[s.focusedEpubIndex!],
                epubIndex: s.focusedEpubIndex!,
                state: state,
                cubit: cubit,
                showBack: true,
              );
            }
            if (s.epubs.length == 1) {
              return _SingleEpubView(
                epub: s.epubs.first,
                epubIndex: 0,
                state: state,
                cubit: cubit,
                showBack: false,
              );
            }
            return _MultiEpubView(state: state, cubit: cubit);
          },
        ) ??
        const SizedBox.shrink();
  }
}

// ── Vista individual ──────────────────────────────────────────────────────────

class _SingleEpubView extends StatelessWidget {
  const _SingleEpubView({
    required this.epub,
    required this.epubIndex,
    required this.state,
    required this.cubit,
    required this.showBack,
  });

  final LoadedEpub epub;
  final int epubIndex;
  final SearchReplaceState state;
  final SearchReplaceCubit cubit;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return state.mapOrNull(
          ready: (s) => Column(
            children: [
              if (showBack)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: Text('Volver · ${s.epubs.length} EPUBs'),
                    style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                    onPressed: cubit.unfocusEpub,
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: FileSelectorWidget(
                        files: epub.textFiles,
                        selectedIds: epub.selectedFileIds, // List<String>? — nullable
                        onSelectionChanged: (ids) => cubit.changeEpubFileSelection(epubIndex, ids),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _SearchPanel(state: state, cubit: cubit, alwaysShowEpubHeader: false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ) ??
        const SizedBox.shrink();
  }
}

// ── Vista multi ───────────────────────────────────────────────────────────────

class _MultiEpubView extends StatelessWidget {
  const _MultiEpubView({required this.state, required this.cubit});
  final SearchReplaceState state;
  final SearchReplaceCubit cubit;

  @override
  Widget build(BuildContext context) {
    return state.mapOrNull(
          ready: (s) => Row(
            children: [
              SizedBox(
                width: 220,
                child: EpubListWidget(epubs: s.epubs, cubit: cubit),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _SearchPanel(state: state, cubit: cubit, alwaysShowEpubHeader: true),
              ),
            ],
          ),
        ) ??
        const SizedBox.shrink();
  }
}

// ── Panel de búsqueda (compartido) ────────────────────────────────────────────

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.state,
    required this.cubit,
    required this.alwaysShowEpubHeader,
  });
  final SearchReplaceState state;
  final SearchReplaceCubit cubit;
  final bool alwaysShowEpubHeader;

  @override
  Widget build(BuildContext context) {
    return state.mapOrNull(
          ready: (s) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: _SearchForm(state: state, cubit: cubit),
              ),
              const Divider(height: 1),
              Expanded(
                child: s.results.isEmpty && !s.isProcessing
                    ? Center(
                        child: Text(
                          s.searchPattern.isEmpty ? 'Introduce un patrón de búsqueda' : 'Sin resultados',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      )
                    : MatchListWidget(
                        results: s.results,
                        totalMatches: s.totalMatches,
                        replacePattern: s.replacePattern,
                        cubit: cubit,
                        alwaysShowEpubHeader: alwaysShowEpubHeader,
                      ),
              ),
            ],
          ),
        ) ??
        const SizedBox.shrink();
  }
}

class _SearchForm extends StatelessWidget {
  const _SearchForm({required this.state, required this.cubit});
  final SearchReplaceState state;
  final SearchReplaceCubit cubit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return state.mapOrNull(
          ready: (s) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RegexTextField(
                label: 'Buscar',
                isRegexMode: s.isRegexMode,
                errorText: s.patternError,
                initialValue: s.searchPattern,
                hintText: s.isRegexMode ? r'(\w+)\s+\1' : 'Texto a buscar…',
                onChanged: cubit.changePattern,
                suffixIcons: [
                  _ToggleChip(label: '.*', active: s.isRegexMode, tooltip: 'Modo Regex', onTap: cubit.toggleRegexMode),
                  _ToggleChip(label: 'Aa', active: s.isCaseSensitive, tooltip: 'Distinguir mayúsculas', onTap: cubit.toggleCaseSensitivity),
                ],
              ),
              const SizedBox(height: 10),
              RegexTextField(
                label: 'Reemplazar',
                isRegexMode: false,
                initialValue: s.replacePattern,
                hintText: r'Usa $1, ${nombre} para grupos; $$ para $ literal',
                onChanged: cubit.changeReplacement,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Buscar'),
                    onPressed: s.patternError != null || s.searchPattern.isEmpty || s.isProcessing ? null : cubit.executeSearch,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.find_replace_rounded, size: 18),
                    label: const Text('Reemplazar todo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error.withAlpha(100)),
                    ),
                    onPressed: s.patternError != null || s.searchPattern.isEmpty || s.isProcessing || s.results.isEmpty ? null : cubit.replaceAll,
                  ),
                ],
              ),
            ],
          ),
        ) ??
        const SizedBox.shrink();
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.label, required this.active, required this.tooltip, required this.onTap});
  final String label;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: active ? cs.primary : cs.outlineVariant),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
