import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/preferences_repo.dart';
import 'settings_state.dart';

class SettingsCubit(this._repository) extends Cubit<SettingsState> {
  final PreferencesRepository _repository;

  this : super(SettingsState(preferences: _repository.getPreferences()));

  Future<void> changeTheme(ThemeMode mode) async {
    await _repository.saveThemeMode(mode);
    emit(
      state.copyWith(
        preferences: state.preferences.copyWith(themeMode: mode),
      ),
    );
  }
}
