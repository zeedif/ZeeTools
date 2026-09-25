import 'package:freezed_annotation/freezed_annotation.dart';

part 'epub_source.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
sealed class EpubSource with _$EpubSource {
  const factory EpubSource.files(List<String> paths) = _Files;
  const factory EpubSource.directory(
    String path, {
    @Default(false) bool recursive,
  }) = _Directory;
}
