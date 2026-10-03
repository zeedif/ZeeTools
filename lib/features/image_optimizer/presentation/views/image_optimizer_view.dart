import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '/inject_dependencies.dart';
import '/common/epub/models/epub_manifest_item.dart';
import '/common/epub/models/loaded_epub.dart';
import '/common/widgets/resizable_split_panel.dart';
import '/common/widgets/speed_dial.dart';
import '../../domain/image_format.dart';
import '../../domain/image_job.dart';
import '../../domain/source_image.dart';
import '../cubit/image_optimizer_cubit.dart';
import 'widgets/epub_image_selector.dart';
import 'widgets/epub_list_panel.dart';
import 'widgets/epub_results_widget.dart';
import 'widgets/image_list_widget.dart';
import 'widgets/options_bar.dart';

const _pickerExtensions = ['epub', ...ImageFormat.inputExtensions];

class ImageOptimizerView extends StatelessWidget {
  const ImageOptimizerView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ImageOptimizerCubit>(),
      child: const _ImageOptimizerContent(),
    );
  }
}

class _ImageOptimizerContent extends StatefulWidget {
  const _ImageOptimizerContent();

  @override
  State<_ImageOptimizerContent> createState() => _ImageOptimizerContentState();
}

class _ImageOptimizerContentState extends State<_ImageOptimizerContent> {
  final _fabNotifier = getIt<ValueNotifier<List<SpeedDialAction>>>();
  bool _dragging = false;
  ImageOptimizerMessage? _lastMessage;

  @override
  void dispose() {
    // Diferir la limpieza al siguiente frame — el árbol está bloqueado durante dispose.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fabNotifier.value = [];
    });
    super.dispose();
  }

  void _updateFab(ImageOptimizerState state) {
    _fabNotifier.value =
        state.mapOrNull(
          ready: (_) => [
            SpeedDialAction(icon: Icons.file_open_outlined, label: 'Añadir archivos…', onPressed: _pickFiles),
            SpeedDialAction(icon: Icons.folder_outlined, label: 'Añadir de una carpeta…', onPressed: () => _pickDirectory(recursive: false)),
            SpeedDialAction(icon: Icons.folder_copy_outlined, label: 'Añadir de carpeta y subcarpetas…', onPressed: () => _pickDirectory(recursive: true)),
          ],
        ) ??
        [];
  }

  Future<void> _pickFiles() async {
    final paths = (await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _pickerExtensions,
      dialogTitle: 'Seleccionar imágenes o EPUBs',
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    )).map((f) => f.path).whereType<String>().toList();
    if (paths.isNotEmpty) await _handleIncoming(paths);
  }

  Future<void> _pickDirectory({bool? recursive}) async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Seleccionar carpeta con imágenes o EPUBs',
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    );
    if (path != null) await _handleIncoming([path], recursive: recursive);
  }

  // EPUBs e imágenes no se mezclan en una misma sesión.
  Future<void> _handleIncoming(List<String> paths, {bool? recursive}) async {
    final cubit = context.read<ImageOptimizerCubit>();
    final scan = await cubit.scan(paths, recursive: recursive);
    if (!mounted) return;
    if (scan.isEmpty) {
      _showSnackBar('No se encontraron imágenes ni EPUBs.');
      return;
    }

    ImageSessionKind? kind;
    if (scan.epubs.isNotEmpty && scan.images.isNotEmpty) {
      kind = await _askKind(scan);
    } else {
      kind = scan.epubs.isNotEmpty ? ImageSessionKind.epubs : ImageSessionKind.images;
    }
    if (kind == null || !mounted) return;

    final current = cubit.sessionKind;
    if (current != null && current != kind && !await _confirmSwitch(current, kind)) return;
    await cubit.open(kind, kind == ImageSessionKind.epubs ? scan.epubs : scan.images);
  }

  Future<ImageSessionKind?> _askKind(ScanResult scan) => showDialog<ImageSessionKind>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Con qué quieres trabajar?'),
      content: Text(
        'Se encontraron ${scan.epubs.length} EPUB${scan.epubs.length == 1 ? '' : 's'} y '
        '${scan.images.length} imagen${scan.images.length == 1 ? '' : 'es'}. '
        'Una sesión trabaja solo con EPUBs o solo con imágenes sueltas.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(ctx, ImageSessionKind.images), child: Text('Imágenes (${scan.images.length})')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ImageSessionKind.epubs), child: Text('EPUBs (${scan.epubs.length})')),
      ],
    ),
  );

  Future<bool> _confirmSwitch(ImageSessionKind from, ImageSessionKind to) async {
    String name(ImageSessionKind k) => k == ImageSessionKind.epubs ? 'EPUBs' : 'imágenes sueltas';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cambiar a ${name(to)}'),
        content: Text('La sesión actual trabaja con ${name(from)}. Si continúas se cerrará y se perderán los cambios sin guardar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Seguir con ${name(from)}')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Cambiar a ${name(to)}')),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _showSnackBar(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        content: Text(text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocConsumer<ImageOptimizerCubit, ImageOptimizerState>(
      listener: (context, state) {
        _updateFab(state);
        final message = state.mapOrNull(ready: (s) => s.message);
        if (message != null && message != _lastMessage) {
          _lastMessage = message;
          _showSnackBar(message.text, isError: message.isError);
        }
      },
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: const Text('Optimizador de Imágenes'),
          actions: [_AppBarActions(onSaveImagesInPlace: _saveImagesInPlace, onSaveImagesToFolder: _saveImagesToFolder)],
        ),
        body: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (details) {
            setState(() => _dragging = false);
            _handleIncoming(details.files.map((f) => f.path).toList());
          },
          child: Stack(
            children: [
              Positioned.fill(
                child:
                    state.mapOrNull(
                      idle: (_) => _IdlePane(onPickFiles: _pickFiles, onPickDirectory: () => _pickDirectory()),
                      loading: (s) => _LoadingPane(message: s.message),
                      failure: (s) => _FailurePane(message: s.message),
                    ) ??
                    const _ReadyPane(),
              ),
              if (_dragging)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.08),
                        border: Border.all(color: cs.primary, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'Suelta aquí imágenes, EPUBs o carpetas',
                          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveImagesInPlace() async {
    final cubit = context.read<ImageOptimizerCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reemplazar originales'),
        content: Text('Se sobrescribirán ${cubit.state.mapOrNull(ready: (s) => s.jobs.values.where((j) => j is DoneJob && !j.committed).length) ?? 0} imágenes con su versión optimizada. Si cambia el formato, el original se elimina y queda el archivo con la nueva extensión.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reemplazar')),
        ],
      ),
    );
    if (confirmed == true) await cubit.saveImagesInPlace();
  }

  Future<void> _saveImagesToFolder() async {
    final cubit = context.read<ImageOptimizerCubit>();
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Carpeta donde guardar las imágenes optimizadas',
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    );
    if (path != null && !cubit.isClosed) await cubit.saveImagesToFolder(path);
  }
}

// ── AppBar ───────────────────────────────────────────────────────────────────

typedef _AppBarData = ({
  ImageSessionKind kind,
  bool isProcessing,
  bool hasUnsavedImages,
  bool hasProcessedImages,
  bool isMultiView,
  LoadedEpub? singleEpub,
  int? epubIndex,
  Set<String> dirtyEpubs,
});

class _AppBarActions extends StatelessWidget {
  const _AppBarActions({required this.onSaveImagesInPlace, required this.onSaveImagesToFolder});

  final VoidCallback onSaveImagesInPlace;
  final VoidCallback onSaveImagesToFolder;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ImageOptimizerCubit>();
    return BlocSelector<ImageOptimizerCubit, ImageOptimizerState, _AppBarData?>(
      selector: (state) => state.mapOrNull(
        ready: (s) => (
          kind: s.kind,
          isProcessing: s.isProcessing,
          hasUnsavedImages: hasUnsavedResults(s.jobs),
          hasProcessedImages: s.images.any((i) => s.jobs[i.path] is DoneJob),
          isMultiView: s.epubs.length > 1 && s.focusedEpubIndex == null,
          singleEpub: s.focusedEpubIndex != null ? s.epubs[s.focusedEpubIndex!] : (s.epubs.length == 1 ? s.epubs.first : null),
          epubIndex: s.focusedEpubIndex ?? (s.epubs.length == 1 ? 0 : null),
          dirtyEpubs: s.dirtyEpubs,
        ),
      ),
      builder: (context, data) {
        if (data == null) return const SizedBox.shrink();
        final singleEpub = data.singleEpub;
        final busy = data.isProcessing;

        return Row(
          children: [
            if (busy)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (data.kind == ImageSessionKind.images) ...[
              IconButton(
                icon: const Icon(Icons.save_outlined),
                tooltip: 'Guardar (reemplazar originales)',
                onPressed: busy || !data.hasUnsavedImages ? null : onSaveImagesInPlace,
              ),
              IconButton(
                icon: const Icon(Icons.drive_folder_upload_outlined),
                tooltip: 'Guardar en carpeta…',
                onPressed: busy || !data.hasProcessedImages ? null : onSaveImagesToFolder,
              ),
            ] else if (data.isMultiView)
              IconButton(
                icon: const Icon(Icons.save_outlined),
                tooltip: 'Guardar todos',
                onPressed: busy || data.dirtyEpubs.isEmpty ? null : () => cubit.saveEpubs(),
              )
            else if (singleEpub != null) ...[
              IconButton(
                icon: const Icon(Icons.save_outlined),
                tooltip: 'Guardar',
                onPressed: busy || !data.dirtyEpubs.contains(singleEpub.path) ? null : () => cubit.saveEpubs(epubIndex: data.epubIndex),
              ),
              IconButton(
                icon: const Icon(Icons.save_as_outlined),
                tooltip: 'Guardar como…',
                onPressed: busy
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
                        if (uri != null && !cubit.isClosed) cubit.markExported();
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
              onPressed: () => context.read<ImageOptimizerCubit>().resetToIdle(),
              child: const Text('Volver al inicio'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdlePane extends StatefulWidget {
  const _IdlePane({required this.onPickFiles, required this.onPickDirectory});

  final VoidCallback onPickFiles;
  final VoidCallback onPickDirectory;

  @override
  State<_IdlePane> createState() => _IdlePaneState();
}

class _IdlePaneState extends State<_IdlePane> {
  late bool _recursive = context.read<ImageOptimizerCubit>().recursive;

  void _setRecursive(bool value) {
    setState(() => _recursive = value);
    context.read<ImageOptimizerCubit>().setRecursive(value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_size_select_large_outlined, size: 64, color: cs.outline),
            const SizedBox(height: 16),
            const Text('Arrastra aquí imágenes, EPUBs o carpetas', textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'JPEG, PNG, WebP, AVIF, JPEG XL, GIF estático, BMP y TIFF. Las animaciones se omiten.',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Abrir archivo(s)…'),
                  onPressed: widget.onPickFiles,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Abrir carpeta…'),
                  onPressed: widget.onPickDirectory,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(value: _recursive, onChanged: _setRecursive),
                const SizedBox(width: 8),
                Flexible(
                  child: GestureDetector(
                    onTap: () => _setRecursive(!_recursive),
                    child: Text('Incluir subcarpetas al abrir o arrastrar carpetas', style: tt.bodySmall),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Router de vistas ─────────────────────────────────────────────────────────

typedef _ReadyRouting = ({ImageSessionKind kind, int? focusedEpubIndex, int epubsLength});

class _ReadyPane extends StatelessWidget {
  const _ReadyPane();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ImageOptimizerCubit, ImageOptimizerState, _ReadyRouting?>(
      selector: (state) => state.mapOrNull(ready: (s) => (kind: s.kind, focusedEpubIndex: s.focusedEpubIndex, epubsLength: s.epubs.length)),
      builder: (context, routing) {
        if (routing == null) return const SizedBox.shrink();
        if (routing.kind == ImageSessionKind.images) return const _ImagesView();
        if (routing.focusedEpubIndex != null) return _SingleEpubView(epubIndex: routing.focusedEpubIndex!, showBack: true);
        if (routing.epubsLength == 1) return const _SingleEpubView(epubIndex: 0, showBack: false);
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

// ── Imágenes sueltas ─────────────────────────────────────────────────────────

typedef _ImagesData = ({List<SourceImage> images, Map<String, ImageJob> jobs, bool isProcessing});

class _ImagesView extends StatelessWidget {
  const _ImagesView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ImageOptimizerCubit>();
    return Column(
      children: [
        const OptionsBar(),
        const Divider(height: 1),
        Expanded(
          child: BlocSelector<ImageOptimizerCubit, ImageOptimizerState, _ImagesData?>(
            selector: (state) => state.mapOrNull(ready: (s) => (images: s.images, jobs: s.jobs, isProcessing: s.isProcessing)),
            builder: (context, data) {
              if (data == null) return const SizedBox.shrink();
              return ImageListWidget(images: data.images, jobs: data.jobs, isProcessing: data.isProcessing, onRemove: cubit.removeImage);
            },
          ),
        ),
      ],
    );
  }
}

// ── Un EPUB ──────────────────────────────────────────────────────────────────

typedef _SingleEpubData = ({LoadedEpub epub, List<EpubManifestItem> files, List<String>? selectedIds, Map<String, ImageJob> jobs, int epubsLength});

class _SingleEpubView extends StatelessWidget {
  const _SingleEpubView({required this.epubIndex, required this.showBack});

  final int epubIndex;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ImageOptimizerCubit>();
    return BlocSelector<ImageOptimizerCubit, ImageOptimizerState, _SingleEpubData?>(
      selector: (state) => state.mapOrNull(
        ready: (s) => epubIndex < s.epubs.length ? (epub: s.epubs[epubIndex], files: s.epubs[epubIndex].files, selectedIds: s.epubs[epubIndex].selectedFileIds, jobs: s.jobs, epubsLength: s.epubs.length) : null,
      ),
      builder: (context, data) {
        if (data == null) return const SizedBox.shrink();
        return Column(
          children: [
            if (showBack) _BackBar(label: 'Volver · ${data.epubsLength} EPUBs', onTap: cubit.unfocusEpub),
            Expanded(
              child: ResizableSplitPanel(
                initialWidth: 260,
                maxWidth: 420,
                panel: EpubImageSelector(
                  epubPath: data.epub.path,
                  files: data.files,
                  selectedIds: data.selectedIds,
                  jobs: data.jobs,
                  onSelectionChanged: (ids) => cubit.changeEpubFileSelection(epubIndex, ids),
                ),
                body: Column(
                  children: [
                    const OptionsBar(),
                    const Divider(height: 1),
                    Expanded(
                      child: EpubResultsWidget(epubs: [data.epub], jobs: data.jobs, showEpubHeader: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Varios EPUBs ─────────────────────────────────────────────────────────────

typedef _MultiEpubData = ({List<LoadedEpub> epubs, Map<String, ImageJob> jobs, Set<String> dirtyEpubs, bool isProcessing});

class _MultiEpubView extends StatelessWidget {
  const _MultiEpubView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ImageOptimizerCubit>();
    return BlocSelector<ImageOptimizerCubit, ImageOptimizerState, _MultiEpubData?>(
      selector: (state) => state.mapOrNull(ready: (s) => (epubs: s.epubs, jobs: s.jobs, dirtyEpubs: s.dirtyEpubs, isProcessing: s.isProcessing)),
      builder: (context, data) {
        if (data == null) return const SizedBox.shrink();
        return ResizableSplitPanel(
          initialWidth: 260,
          maxWidth: 420,
          panel: EpubListPanel(epubs: data.epubs, dirtyEpubs: data.dirtyEpubs, isProcessing: data.isProcessing, cubit: cubit),
          body: Column(
            children: [
              const OptionsBar(),
              const Divider(height: 1),
              Expanded(
                child: EpubResultsWidget(epubs: data.epubs, jobs: data.jobs, showEpubHeader: true),
              ),
            ],
          ),
        );
      },
    );
  }
}
