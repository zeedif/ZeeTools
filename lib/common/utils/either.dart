import 'package:freezed_annotation/freezed_annotation.dart';

part 'either.freezed.dart';

@Freezed()
sealed class Either<L, R> with _$Either<L, R> {
  const factory Either.left(L value) = Left<L, R>;
  const factory Either.right(R value) = Right<L, R>;
}

extension EitherX<L, R> on Either<L, R> {
  bool get isLeft => this is Left<L, R>;
  bool get isRight => this is Right<L, R>;

  T fold<T>(T Function(L) onLeft, T Function(R) onRight) => when(
    left: (v) => onLeft(v),
    right: (v) => onRight(v),
  );

  Either<L, T> map<T>(T Function(R) f) => fold(Either.left, (r) => Either.right(f(r)));

  // Devuelve el valor Right o el resultado de recover si es Left.
  R getOrElse(R Function(L) recover) => fold(recover, (r) => r);
}
