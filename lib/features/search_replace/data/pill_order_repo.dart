import 'package:shared_preferences/shared_preferences.dart';

import '../domain/file_selection_profile.dart';

abstract interface class PillOrderRepository {
  List<FileSelectionProfile> getOrder();
  Future<void> saveOrder(List<FileSelectionProfile> order);
  bool getGroupFilesByPillOrder();
  Future<void> saveGroupFilesByPillOrder(bool value);
  bool getSortAscending();
  Future<void> saveSortAscending(bool value);
}

class PillOrderRepositoryImpl(final SharedPreferences _prefs) implements PillOrderRepository {
  static const _key = 'search_replace_pill_order';
  static const _groupByPillOrderKey = 'search_replace_group_files_by_pill_order';
  static const _sortAscendingKey = 'search_replace_sort_ascending';
  static const _defaultOrder = [
    FileSelectionProfile.xhtml,
    FileSelectionProfile.css,
    FileSelectionProfile.xml,
    FileSelectionProfile.js,
  ];

  @override
  List<FileSelectionProfile> getOrder() {
    final stored = _prefs.getStringList(_key);
    if (stored == null) return _defaultOrder;

    final remaining = {for (final p in _defaultOrder) p.name: p};
    final restored = stored.map(remaining.remove).whereType<FileSelectionProfile>().toList();
    return [...restored, ...remaining.values];
  }

  @override
  Future<void> saveOrder(List<FileSelectionProfile> order) async {
    await _prefs.setStringList(_key, order.map((p) => p.name).toList());
  }

  @override
  bool getGroupFilesByPillOrder() => _prefs.getBool(_groupByPillOrderKey) ?? false;

  @override
  Future<void> saveGroupFilesByPillOrder(bool value) => _prefs.setBool(_groupByPillOrderKey, value);

  @override
  bool getSortAscending() => _prefs.getBool(_sortAscendingKey) ?? true;

  @override
  Future<void> saveSortAscending(bool value) => _prefs.setBool(_sortAscendingKey, value);
}
