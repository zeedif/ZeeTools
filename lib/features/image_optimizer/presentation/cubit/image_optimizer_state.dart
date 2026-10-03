part of 'image_optimizer_cubit.dart';

// Sin == propio: la vista lo muestra una vez por instancia.
class ImageOptimizerMessage {
  const ImageOptimizerMessage(this.text, {this.isError = false});

  final String text;
  final bool isError;
}

@Freezed(makeCollectionsUnmodifiable: false)
sealed class ImageOptimizerState with _$ImageOptimizerState {
  const factory ImageOptimizerState.idle() = _Idle;

  const factory ImageOptimizerState.loading(String message) = _Loading;

  const factory ImageOptimizerState.ready({
    required ImageSessionKind kind,
    @Default([]) List<SourceImage> images,
    @Default([]) List<LoadedEpub> epubs,
    // null = vista de sesión (multi si >1, individual si 1)
    // set  = vista individual forzada para ese índice
    int? focusedEpubIndex,
    required List<ImageFormat> allowedFormats,
    @Default(true) bool allowConversion,
    required QualityMode qualityMode,
    // Clave: ruta de la imagen o ImageOptimizerCubit.epubJobKey.
    @Default({}) Map<String, ImageJob> jobs,
    @Default({}) Set<String> dirtyEpubs,
    @Default(false) bool isProcessing,
    @Default(false) bool cancelRequested,
    @Default(0) int progressDone,
    @Default(0) int progressTotal,
    String? statusMessage,
    ImageOptimizerMessage? message,
  }) = _Ready;

  const factory ImageOptimizerState.failure(String message) = _Failure;
}

bool hasUnsavedResults(Map<String, ImageJob> jobs) => jobs.values.any((j) => j is DoneJob && !j.committed && j.outcome is OptimizedOutcome);
