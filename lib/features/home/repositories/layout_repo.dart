import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LayoutRepository {
  double getSidebarWidth();
  bool getPreferSidePanel();
  Future<void> saveSidebarWidth(double width);
  Future<void> savePreferSidePanel(bool prefer);
}

class LayoutRepositoryImpl(final SharedPreferences _prefs) implements LayoutRepository {
  @override
  double getSidebarWidth() => _prefs.getDouble('layout_sidebar_width') ?? 90.0;

  @override
  bool getPreferSidePanel() => _prefs.getBool('layout_prefer_side_panel') ?? true;

  @override
  Future<void> saveSidebarWidth(double width) async {
    await _prefs.setDouble('layout_sidebar_width', width);
  }

  @override
  Future<void> savePreferSidePanel(bool prefer) async {
    await _prefs.setBool('layout_prefer_side_panel', prefer);
  }
}
