import 'package:freezed_annotation/freezed_annotation.dart';

import 'image_format.dart';

part 'optimization_outcome.freezed.dart';

@Freezed()
sealed class OptimizationOutcome with _$OptimizationOutcome {
  const OptimizationOutcome._();

  const factory OptimizationOutcome.optimized({
    required ImageFormat sourceFormat,
    required int originalSize,
    required int newSize,
    required ImageFormat format,
    required String method,
    required String resultPath,
    double? score,
    @Default(false) bool alphaRemoved,
  }) = OptimizedOutcome;

  const factory OptimizationOutcome.unchanged({required int size}) = UnchangedOutcome;

  const factory OptimizationOutcome.skipped(String reason) = SkippedOutcome;

  const factory OptimizationOutcome.failed(String message) = FailedOutcome;
}
