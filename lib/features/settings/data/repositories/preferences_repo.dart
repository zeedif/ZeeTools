import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/preferences.dart';

abstract interface class PreferencesRepository {
  Preferences getPreferences();
  Future<void> saveThemeMode(ThemeMode mode);
}

class PreferencesRepositoryImpl(final SharedPreferences _prefs) implements PreferencesRepository {
  static const _themeKey = 'theme_mode';

  @override
  Preferences getPreferences() {
    final themeIndex = _prefs.getInt(_themeKey) ?? ThemeMode.system.index;
    return Preferences(
      themeMode: ThemeMode.values[themeIndex],
    );
  }

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    await _prefs.setInt(_themeKey, mode.index);
  }
}
