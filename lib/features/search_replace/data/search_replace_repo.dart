import '../../../common/epub/models/epub_failure.dart';
import '../../../common/epub/models/loaded_epub.dart';
import '../../../common/epub/repositories/epub_repo.dart';
import '../../../common/utils/either.dart';
import '../domain/match_result.dart';
import '../domain/search_options.dart';

abstract interface class SearchReplaceRepository {
  Future<Either<EpubFailure, List<EpubSearchResult>>> search(
    SearchOptions options,
    List<LoadedEpub> epubs,
  );

  Future<Either<EpubFailure, int>> replaceAll(
    SearchOptions options,
    String replacement,
    List<LoadedEpub> epubs,
  );

  Future<Either<EpubFailure, bool>> replaceSingle(
    SearchOptions options,
    FileSearchResult fileResult,
    MatchResult match,
    String replacement,
  );
}

class SearchReplaceRepositoryImpl implements SearchReplaceRepository {
  SearchReplaceRepositoryImpl(this._epubRepo);

  final EpubRepository _epubRepo;

  @override
  Future<Either<EpubFailure, List<EpubSearchResult>>> search(
    SearchOptions options,
    List<LoadedEpub> epubs,
  ) async {
    RegExp regex;
    try {
      regex = options.buildRegExp()!;
    } on FormatException catch (e) {
      return Either.left(EpubFailure.invalidRegex(options.pattern, e.message));
    }

    final results = <EpubSearchResult>[];

    for (final epub in epubs) {
      // Cada EPUB conoce sus propios archivos activos según su modo implícito/explícito.
      final targets = epub.activeFiles;
      if (targets.isEmpty) continue;

      final fileResults = <FileSearchResult>[];
      for (final item in targets) {
        final readResult = await _epubRepo.readTextFile(epub.path, item.archivePath);

        final failure = readResult.mapOrNull(left: (l) => l.value);
        if (failure != null) return Either.left(failure);

        final content = readResult.getOrElse((_) => '');
        final matches = _findMatches(content, regex);
        if (matches.isNotEmpty) {
          fileResults.add(
            FileSearchResult(
              epubPath: epub.path,
              file: item,
              matches: matches,
            ),
          );
        }
      }

      if (fileResults.isNotEmpty) {
        results.add(EpubSearchResult(epubPath: epub.path, fileResults: fileResults));
      }
    }

    return Either.right(results);
  }

  @override
  Future<Either<EpubFailure, int>> replaceAll(
    SearchOptions options,
    String replacement,
    List<LoadedEpub> epubs,
  ) async {
    RegExp regex;
    try {
      regex = options.buildRegExp()!;
    } on FormatException catch (e) {
      return Either.left(EpubFailure.invalidRegex(options.pattern, e.message));
    }

    var totalReplaced = 0;

    for (final epub in epubs) {
      final targets = epub.activeFiles;
      if (targets.isEmpty) continue;

      for (final item in targets) {
        final readResult = await _epubRepo.readTextFile(epub.path, item.archivePath);

        final failure = readResult.mapOrNull(left: (l) => l.value);
        if (failure != null) return Either.left(failure);

        final content = readResult.getOrElse((_) => '');
        final count = regex.allMatches(content).length;
        if (count == 0) continue;

        final modified = content.replaceAll(regex, replacement);
        final writeResult = await _epubRepo.writeTextFile(epub.path, item.archivePath, modified);
        final writeFailure = writeResult.mapOrNull(left: (l) => l.value);
        if (writeFailure != null) return Either.left(writeFailure);

        totalReplaced += count;
      }
    }

    return Either.right(totalReplaced);
  }

  @override
  Future<Either<EpubFailure, bool>> replaceSingle(
    SearchOptions options,
    FileSearchResult fileResult,
    MatchResult match,
    String replacement,
  ) async {
    RegExp regex;
    try {
      regex = options.buildRegExp()!;
    } on FormatException catch (e) {
      return Either.left(EpubFailure.invalidRegex(options.pattern, e.message));
    }

    final readResult = await _epubRepo.readTextFile(
      fileResult.epubPath,
      fileResult.file.archivePath,
    );
    final failure = readResult.mapOrNull(left: (l) => l.value);
    if (failure != null) return Either.left(failure);

    final content = readResult.getOrElse((_) => '');

    RegExpMatch? target;
    for (final m in regex.allMatches(content)) {
      if (m.start == match.startOffset && m.end == match.endOffset) {
        target = m;
        break;
      }
    }
    if (target == null) return const Either.right(false);

    final modified = content.replaceRange(
      target.start,
      target.end,
      _expandReplacement(replacement, target),
    );
    final writeResult = await _epubRepo.writeTextFile(
      fileResult.epubPath,
      fileResult.file.archivePath,
      modified,
    );
    final writeFailure = writeResult.mapOrNull(left: (l) => l.value);
    if (writeFailure != null) return Either.left(writeFailure);

    return const Either.right(true);
  }

  List<MatchResult> _findMatches(String content, RegExp regex) {
    final lineStarts = _lineStarts(content);
    return regex.allMatches(content).map((m) {
      final (line, col, lineContent, matchStart) = _location(content, m.start, lineStarts);
      return MatchResult(
        startOffset: m.start,
        endOffset: m.end,
        matchText: m.group(0) ?? '',
        lineNumber: line,
        columnOffset: col,
        lineContent: lineContent,
        matchStartInLine: matchStart,
      );
    }).toList();
  }

  List<int> _lineStarts(String content) {
    final starts = <int>[0];
    for (var i = 0; i < content.length; i++) {
      if (content[i] == '\n') starts.add(i + 1);
    }
    return starts;
  }

  (int, int, String, int) _location(String content, int offset, List<int> lineStarts) {
    var lo = 0;
    var hi = lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final lineStart = lineStarts[lo];
    final lineEnd = lo + 1 < lineStarts.length ? lineStarts[lo + 1] - 1 : content.length;
    return (lo + 1, offset - lineStart, content.substring(lineStart, lineEnd), offset - lineStart);
  }

  String _expandReplacement(String template, RegExpMatch match) {
    final buf = StringBuffer();
    var i = 0;
    while (i < template.length) {
      if (template[i] == r'$' && i + 1 < template.length) {
        final next = template[i + 1];
        if (next == r'$') {
          buf.write(r'$');
          i += 2;
        } else if (next == '{') {
          final close = template.indexOf('}', i + 2);
          if (close < 0) {
            buf.write(template[i]);
            i++;
          } else {
            final key = template.substring(i + 2, close);
            final idx = int.tryParse(key);
            buf.write(idx != null ? match.group(idx) ?? '' : match.namedGroup(key) ?? '');
            i = close + 1;
          }
        } else if (RegExp(r'[0-9]').hasMatch(next)) {
          buf.write(match.group(int.parse(next)) ?? '');
          i += 2;
        } else {
          buf.write(template[i]);
          i++;
        }
      } else {
        buf.write(template[i]);
        i++;
      }
    }
    return buf.toString();
  }
}
