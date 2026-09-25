part of 'search_replace_cubit.dart';

@Freezed(makeCollectionsUnmodifiable: false)
sealed class SearchReplaceState with _$SearchReplaceState {
  const factory SearchReplaceState.idle() = _Idle;

  const factory SearchReplaceState.loading(String message) = _Loading;

  const factory SearchReplaceState.ready({
    required List<LoadedEpub> epubs,
    // null = vista de sesión (multi si >1, individual si 1)
    // set  = vista individual forzada para ese índice
    int? focusedEpubIndex,
    @Default('') String searchPattern,
    @Default('') String replacePattern,
    @Default(false) bool isRegexMode,
    @Default(true) bool isCaseSensitive,
    String? patternError,
    @Default([]) List<EpubSearchResult> results,
    @Default(0) int totalMatches,
    @Default(false) bool isProcessing,
    int? lastReplacedCount,
    String? errorMessage,
    @Default(false) bool isSaved,
  }) = _Ready;

  const factory SearchReplaceState.failure(String message) = _Failure;
}

extension SearchReplaceStateX on SearchReplaceState {
  bool get isReadyState => this is _Ready;
}
