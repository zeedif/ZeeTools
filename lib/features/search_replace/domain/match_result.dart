import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../common/epub/models/epub_manifest_item.dart';

part 'match_result.freezed.dart';

@Freezed()
sealed class MatchResult with _$MatchResult {
  const factory MatchResult({
    required int startOffset,
    required int endOffset,
    required String matchText,
    required int lineNumber,
    required int columnOffset,
    required String lineContent,
    required int matchStartInLine,
  }) = _MatchResult;
}

@Freezed(makeCollectionsUnmodifiable: false)
sealed class FileSearchResult with _$FileSearchResult {
  const FileSearchResult._();

  const factory FileSearchResult({
    required String epubPath,
    required EpubManifestItem file,
    required List<MatchResult> matches,
  }) = _FileSearchResult;

  int get matchCount => matches.length;
}

@Freezed(makeCollectionsUnmodifiable: false)
sealed class EpubSearchResult with _$EpubSearchResult {
  const EpubSearchResult._();

  const factory EpubSearchResult({
    required String epubPath,
    required List<FileSearchResult> fileResults,
  }) = _EpubSearchResult;

  String get displayName => epubPath.split(RegExp(r'[/\\]')).last;
  int get totalMatches => fileResults.fold(0, (s, r) => s + r.matchCount);
}
