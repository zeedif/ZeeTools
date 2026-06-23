import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'preferences.freezed.dart';

@Freezed()
sealed class Preferences with _$Preferences {
  const factory Preferences({
    @Default(ThemeMode.system) ThemeMode themeMode,
  }) = _Preferences;
}
