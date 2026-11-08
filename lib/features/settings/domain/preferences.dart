import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'preferences.freezed.dart';

@Freezed()
sealed class Preferences with _$Preferences {
  const factory Preferences({
    @Default(ThemeMode.system) ThemeMode themeMode,
    // Por id; un complemento nuevo empieza activo.
    @Default(<String>{}) Set<String> disabledPlugins,
  }) = _Preferences;
}
