import 'package:shared_preferences/shared_preferences.dart';

import '../domain/file_selection_profile.dart';

// Estado de la pantalla de búsqueda y reemplazo persistido en shared_preferences:
// orden/agrupación de los pills de archivo y las opciones de búsqueda.
abstract interface class SearchReplaceSettingsRepository {
  List<FileSelectionProfile> getOrder();
  Future<void> saveOrder(List<FileSelectionProfile> order);
  bool getGroupFilesByPillOrder();
  Future<void> saveGroupFilesByPillOrder(bool value);
  bool getSortAscending();
  Future<void> saveSortAscending(bool value);
  bool getIsRegexMode();
  Future<void> saveIsRegexMode(bool value);
  bool getIsCaseSensitive();
  Future<void> saveIsCaseSensitive(bool value);
  bool getIsWholeWord();
  Future<void> saveIsWholeWord(bool value);
  bool getPreserveCase();
  Future<void> savePreserveCase(bool value);
}

class SearchReplaceSettingsRepositoryImpl(final SharedPreferences _prefs) implements SearchReplaceSettingsRepository {
  static const _orderKey = 'search_replace_pill_order';
  static const _groupByPillOrderKey = 'search_replace_group_files_by_pill_order';
  static const _sortAscendingKey = 'search_replace_sort_ascending';
  static const _isRegexModeKey = 'search_replace_is_regex_mode';
  static const _isCaseSensitiveKey = 'search_replace_is_case_sensitive';
  static const _isWholeWordKey = 'search_replace_is_whole_word';
  static const _preserveCaseKey = 'search_replace_preserve_case';
  static const _defaultOrder = [
    FileSelectionProfile.xhtml,
    FileSelectionProfile.css,
    FileSelectionProfile.xml,
    FileSelectionProfile.js,
  ];

  @override
  List<FileSelectionProfile> getOrder() {
    final stored = _prefs.getStringList(_orderKey);
    if (stored == null) return _defaultOrder;

    final remaining = {for (final p in _defaultOrder) p.name: p};
    final restored = stored.map(remaining.remove).whereType<FileSelectionProfile>().toList();
    return [...restored, ...remaining.values];
  }

  @override
  Future<void> saveOrder(List<FileSelectionProfile> order) async {
    await _prefs.setStringList(_orderKey, order.map((p) => p.name).toList());
  }

  @override
  bool getGroupFilesByPillOrder() => _prefs.getBool(_groupByPillOrderKey) ?? false;

  @override
  Future<void> saveGroupFilesByPillOrder(bool value) => _prefs.setBool(_groupByPillOrderKey, value);

  @override
  bool getSortAscending() => _prefs.getBool(_sortAscendingKey) ?? true;

  @override
  Future<void> saveSortAscending(bool value) => _prefs.setBool(_sortAscendingKey, value);

  @override
  bool getIsRegexMode() => _prefs.getBool(_isRegexModeKey) ?? false;

  @override
  Future<void> saveIsRegexMode(bool value) => _prefs.setBool(_isRegexModeKey, value);

  @override
  bool getIsCaseSensitive() => _prefs.getBool(_isCaseSensitiveKey) ?? false;

  @override
  Future<void> saveIsCaseSensitive(bool value) => _prefs.setBool(_isCaseSensitiveKey, value);

  @override
  bool getIsWholeWord() => _prefs.getBool(_isWholeWordKey) ?? false;

  @override
  Future<void> saveIsWholeWord(bool value) => _prefs.setBool(_isWholeWordKey, value);

  @override
  bool getPreserveCase() => _prefs.getBool(_preserveCaseKey) ?? false;

  @override
  Future<void> savePreserveCase(bool value) => _prefs.setBool(_preserveCaseKey, value);
}
