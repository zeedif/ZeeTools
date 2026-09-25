import 'package:freezed_annotation/freezed_annotation.dart';

part 'search_options.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
sealed class SearchOptions with _$SearchOptions {
  const SearchOptions._();

  const factory SearchOptions({
    required String pattern,
    @Default(false) bool isRegex,
    @Default(false) bool isCaseSensitive,
    @Default(false) bool isWholeWord,
    @Default([]) List<String> selectedFileIds,
  }) = _SearchOptions;

  RegExp? buildRegExp() {
    if (pattern.isEmpty) return null;
    var source = isRegex ? pattern : RegExp.escape(pattern);
    if (isWholeWord) source = _wrapWholeWord(source);
    return RegExp(
      source,
      caseSensitive: isCaseSensitive,
      multiLine: true,
      dotAll: false,
      unicode: true,
    );
  }

  // \b solo funciona como frontera junto a un carácter de palabra; se omite en
  // el extremo que no lo sea.
  String _wrapWholeWord(String source) {
    if (source.isEmpty) return source;
    final wordChar = RegExp(r'\w');
    var result = source;
    if (wordChar.hasMatch(result[0])) result = '\\b$result';
    if (wordChar.hasMatch(result[result.length - 1])) result = '$result\\b';
    return result;
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
