import 'image_format.dart';

enum QualityMode {
  lossless,
  // Con pérdida si SSIMULACRA2 ≥ [OptimizationOptions.threshold].
  visuallyLossless;

  String get label => switch (this) {
    QualityMode.lossless => 'Sin pérdida',
    QualityMode.visuallyLossless => 'Visualmente sin pérdida',
  };
}

class OptimizationOptions {
  const OptimizationOptions({required this.allowedFormats, required this.qualityMode, this.allowConversion = true, this.threshold = 90});

  // Destinos de conversión; el formato propio de cada imagen siempre está permitido.
  final Set<ImageFormat> allowedFormats;
  final bool allowConversion;
  final QualityMode qualityMode;
  final double threshold;
}
