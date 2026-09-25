import 'package:freezed_annotation/freezed_annotation.dart';

part 'search_options.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
sealed class SearchOptions with _$SearchOptions {
  const SearchOptions._();

  const factory SearchOptions({
    required String pattern,
    @Default(false) bool isRegex,
    @Default(true) bool isCaseSensitive,
    @Default([]) List<String> selectedFileIds,
  }) = _SearchOptions;

  RegExp? buildRegExp() {
    if (pattern.isEmpty) return null;
    final source = isRegex ? pattern : RegExp.escape(pattern);
    return RegExp(
      source,
      caseSensitive: isCaseSensitive,
      multiLine: true,
      dotAll: false,
      unicode: true,
    );
  }

  String? validate() {
    if (pattern.isEmpty) return 'El patrón no puede estar vacío';
    if (isRegex) {
      try {
        buildRegExp();
      } on FormatException catch (e) {
        return 'Regex inválido: ${e.message}';
      }
    }
    return null;
  }
}
