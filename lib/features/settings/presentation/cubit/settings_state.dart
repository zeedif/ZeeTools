import 'package:freezed_annotation/freezed_annotation.dart';
import '../../core/models/preferences.dart';

part 'settings_state.freezed.dart';

@Freezed()
sealed class SettingsState with _$SettingsState {
  const factory SettingsState({
    @Default(Preferences()) Preferences preferences,
  }) = _SettingsState;
}
