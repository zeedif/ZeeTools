import 'package:flutter/material.dart';

import '../../../../../common/epub/models/epub_manifest_item.dart';
import '../../../domain/match_result.dart';
import '../../cubit/search_replace_cubit.dart';

class MatchListWidget extends StatefulWidget {
  const MatchListWidget({
    super.key,
    required this.results,
    required this.totalMatches,
    required this.replacePattern,
    required this.cubit,
    this.alwaysShowEpubHeader = false,
  });

  final List<EpubSearchResult> results;
  final int totalMatches;
  final String replacePattern;
  final SearchReplaceCubit cubit;
  // true en vista multi-epub: siempre muestra el nombre del EPUB sobre sus resultados.
  final bool alwaysShowEpubHeader;

  @override
  State<MatchListWidget> createState() => _MatchListWidgetState();
}

class _MatchListWidgetState extends State<MatchListWidget> {
  final _collapsedEpubs = <String>{};
  final _collapsedFiles = <String>{};
  bool _allExpanded = true;

  String _fileKey(String epubPath, String archivePath) => '$epubPath::$archivePath';

  void _toggleAll() {
    setState(() {
      if (_allExpanded) {
        _collapsedEpubs.addAll(widget.results.map((r) => r.epubPath));
        _collapsedFiles.addAll([
          for (final r in widget.results)
            for (final fr in r.fileResults) _fileKey(r.epubPath, fr.file.archivePath),
        ]);
      } else {
        _collapsedEpubs.clear();
        _collapsedFiles.clear();
      }
      _allExpanded = !_allExpanded;
    });
  }

  void _toggleEpub(String epubPath) {
    setState(() {
      if (!_collapsedEpubs.add(epubPath)) _collapsedEpubs.remove(epubPath);
    });
  }

  void _toggleFile(String key) {
    setState(() {
      if (!_collapsedFiles.add(key)) _collapsedFiles.remove(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fileCount = widget.results.fold(0, (s, r) => s + r.fileResults.length);
    final epubCount = widget.results.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryBar(
          totalMatches: widget.totalMatches,
          fileCount: fileCount,
          epubCount: epubCount,
          showEpubCount: widget.alwaysShowEpubHeader,
          allExpanded: _allExpanded,
          onToggleAll: _toggleAll,
        ),
        Expanded(
          child: ListView.builder(
            itemCount: widget.results.length,
            itemBuilder: (ctx, i) {
              final result = widget.results[i];
              return _EpubSection(
                result: result,
                replacePattern: widget.replacePattern,
                cubit: widget.cubit,
                showEpubHeader: widget.alwaysShowEpubHeader,
                collapsed: _collapsedEpubs.contains(result.epubPath),
                onToggle: () => _toggleEpub(result.epubPath),
                isFileCollapsed: (archivePath) => _collapsedFiles.contains(_fileKey(result.epubPath, archivePath)),
                onToggleFile: (archivePath) => _toggleFile(_fileKey(result.epubPath, archivePath)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.totalMatches,
    required this.fileCount,
    required this.epubCount,
    required this.showEpubCount,
    required this.allExpanded,
    required this.onToggleAll,
  });
  final int totalMatches;
  final int fileCount;
  final int epubCount;
  final bool showEpubCount;
  final bool allExpanded;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final epubLabel = showEpubCount && epubCount > 0 ? ' en $epubCount EPUB${epubCount == 1 ? '' : 's'}' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: cs.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$totalMatches coincidencia${totalMatches == 1 ? '' : 's'} '
              'en $fileCount archivo${fileCount == 1 ? '' : 's'}$epubLabel',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          IconButton(
            icon: Icon(allExpanded ? Icons.unfold_less : Icons.unfold_more, size: 18),
            tooltip: allExpanded ? 'Colapsar todo' : 'Expandir todo',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            onPressed: onToggleAll,
          ),
        ],
      ),
    );
  }
}

class _EpubSection extends StatelessWidget {
  const _EpubSection({
    required this.result,
    required this.replacePattern,
    required this.cubit,
    required this.showEpubHeader,
    required this.collapsed,
    required this.onToggle,
    required this.isFileCollapsed,
    required this.onToggleFile,
  });
  final EpubSearchResult result;
  final String replacePattern;
  final SearchReplaceCubit cubit;
  final bool showEpubHeader;
  final bool collapsed;
  final VoidCallback onToggle;
  final bool Function(String archivePath) isFileCollapsed;
  final void Function(String archivePath) onToggleFile;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final expanded = !collapsed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showEpubHeader)
          InkWell(
            onTap: onToggle,
            child: Container(
              color: cs.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 16,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.menu_book_outlined, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      result.displayName,
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${result.totalMatches}',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (!showEpubHeader || expanded)
          ...result.fileResults.map(
            (fr) => _FileSection(
              fileResult: fr,
              replacePattern: replacePattern,
              cubit: cubit,
              collapsed: isFileCollapsed(fr.file.archivePath),
              onToggle: () => onToggleFile(fr.file.archivePath),
            ),
          ),
        Divider(height: 1, color: cs.outlineVariant.withAlpha(60)),
      ],
    );
  }
}

class _FileSection extends StatelessWidget {
  const _FileSection({
    required this.fileResult,
    required this.replacePattern,
    required this.cubit,
    required this.collapsed,
    required this.onToggle,
  });
  final FileSearchResult fileResult;
  final String replacePattern;
  final SearchReplaceCubit cubit;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final item = fileResult.file;
    final count = fileResult.matchCount;
    final expanded = !collapsed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.href.split('/').last,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          ...fileResult.matches.map(
            (match) => _MatchRow(
              file: item,
              match: match,
              fileResult: fileResult,
              replacePattern: replacePattern,
              cubit: cubit,
            ),
          ),
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.file,
    required this.match,
    required this.fileResult,
    required this.replacePattern,
    required this.cubit,
  });

  final EpubManifestItem file;
  final MatchResult match;
  final FileSearchResult fileResult;
  final String replacePattern;
  final SearchReplaceCubit cubit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final matchStart = match.matchStartInLine;
    final matchEnd = matchStart + match.matchText.length;
    final line = match.lineContent;
    final before = matchStart < line.length ? line.substring(0, matchStart.clamp(0, line.length)) : '';
    final highlighted = matchStart < line.length && matchEnd <= line.length ? line.substring(matchStart, matchEnd) : match.matchText;
    final after = matchEnd < line.length ? line.substring(matchEnd) : '';

    return Padding(
      padding: const EdgeInsets.only(left: 32, right: 8, bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '${match.lineNumber}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: before,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                  WidgetSpan(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        highlighted,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  TextSpan(
                    text: after,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (replacePattern.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.find_replace, size: 14),
              tooltip: 'Reemplazar esta coincidencia',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              onPressed: () => cubit.replaceSingle(fileResult, match),
            ),
        ],
      ),
    );
  }
}
