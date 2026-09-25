import 'package:freezed_annotation/freezed_annotation.dart';

part 'epub_manifest_item.freezed.dart';

@Freezed()
sealed class EpubManifestItem with _$EpubManifestItem {
  const factory EpubManifestItem({
    required String id,
    required String href,
    required String archivePath,
    required String mediaType,
    @Default('') String properties,
  }) = _EpubManifestItem;
}
