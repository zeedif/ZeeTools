import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/date_display_format.dart';
import '../domain/preferences.dart';

abstract interface class PreferencesRepository {
  Preferences getPreferences();
  Future<void> saveThemeMode(ThemeMode mode);
  DateDisplayFormat getDateFormat();
  Future<void> saveDateFormat(DateDisplayFormat format);
  Future<void> saveDisabledPlugins(Set<String> ids);
}

class PreferencesRepositoryImpl(final SharedPreferences _prefs) implements PreferencesRepository {
  static const _themeKey = 'theme_mode';
  static const _dateFormatKey = 'date_format';
  static const _disabledPluginsKey = 'disabled_plugins';

  @override
  Preferences getPreferences() {
    final themeIndex = _prefs.getInt(_themeKey) ?? ThemeMode.system.index;
    return Preferences(
      themeMode: ThemeMode.values[themeIndex],
      disabledPlugins: {...?_prefs.getStringList(_disabledPluginsKey)},
    );
  }

  @override
  Future<void> saveDisabledPlugins(Set<String> ids) async {
    await _prefs.setStringList(_disabledPluginsKey, ids.toList()..sort());
  }

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    await _prefs.setInt(_themeKey, mode.index);
  }

  @override
  DateDisplayFormat getDateFormat() => DateDisplayFormat.values.where((f) => f.name == _prefs.getString(_dateFormatKey)).firstOrNull ?? DateDisplayFormat.iso;

  @override
  Future<void> saveDateFormat(DateDisplayFormat format) async {
    await _prefs.setString(_dateFormatKey, format.name);
  }
}
