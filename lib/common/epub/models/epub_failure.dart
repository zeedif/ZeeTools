import 'package:freezed_annotation/freezed_annotation.dart';

part 'epub_failure.freezed.dart';

@Freezed()
sealed class EpubFailure with _$EpubFailure {
  const factory EpubFailure.fileNotFound(String path) = _FileNotFound;
  const factory EpubFailure.invalidContainer(String details) = _InvalidContainer;
  const factory EpubFailure.containerXmlMissing() = _ContainerXmlMissing;
  const factory EpubFailure.opfMissing(String opfPath) = _OpfMissing;
  const factory EpubFailure.encodingError({
    required String archivePath,
    required String details,
  }) = _EncodingError;
  const factory EpubFailure.writeError(String details) = _WriteError;
  const factory EpubFailure.invalidRegex(String pattern, String details) = _InvalidRegex;
  const factory EpubFailure.unexpected(String details) = _Unexpected;
}
