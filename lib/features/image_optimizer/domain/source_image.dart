import 'package:freezed_annotation/freezed_annotation.dart';

import 'image_format.dart';

part 'source_image.freezed.dart';

@Freezed()
sealed class SourceImage with _$SourceImage {
  const SourceImage._();

  const factory SourceImage({
    required String path,
    required int size,
    ImageFormat? format,
  }) = _SourceImage;

  String get displayName => path.split(RegExp(r'[/\\]')).last;
}

enum ImageSessionKind { images, epubs }

class ScanResult {
  const ScanResult({required this.images, required this.epubs});

  final List<String> images;
  final List<String> epubs;

  bool get isEmpty => images.isEmpty && epubs.isEmpty;
}
