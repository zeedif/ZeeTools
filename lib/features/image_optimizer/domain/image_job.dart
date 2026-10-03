import 'package:freezed_annotation/freezed_annotation.dart';

import 'optimization_outcome.dart';

part 'image_job.freezed.dart';

// [committed]: aplicado al EPUB en memoria o escrito en disco.
@Freezed()
sealed class ImageJob with _$ImageJob {
  const factory ImageJob.running() = RunningJob;

  const factory ImageJob.done(OptimizationOutcome outcome, {@Default(false) bool committed}) = DoneJob;
}
