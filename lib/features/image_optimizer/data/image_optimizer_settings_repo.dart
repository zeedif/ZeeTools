import 'package:shared_preferences/shared_preferences.dart';

import '../domain/image_format.dart';
import '../domain/optimization_options.dart';

// Preferencias del optimizador persistidas en shared_preferences.
abstract interface class ImageOptimizerSettingsRepository {
  List<ImageFormat> getAllowedFormats();
  Future<void> saveAllowedFormats(List<ImageFormat> formats);
  QualityMode getQualityMode();
  Future<void> saveQualityMode(QualityMode mode);
  bool getAllowConversion();
  Future<void> saveAllowConversion(bool value);
  bool getRecursive();
  Future<void> saveRecursive(bool value);
}

class ImageOptimizerSettingsRepositoryImpl(final SharedPreferences _prefs) implements ImageOptimizerSettingsRepository {
  static const _allowedFormatsKey = 'image_optimizer_allowed_formats';
  static const _qualityModeKey = 'image_optimizer_quality_mode';
  static const _recursiveKey = 'image_optimizer_recursive';
  static const _allowConversionKey = 'image_optimizer_allow_conversion';

  @override
  List<ImageFormat> getAllowedFormats() {
    final stored = _prefs.getStringList(_allowedFormatsKey);
    if (stored == null) return ImageFormat.defaultOutputs;
    return ImageFormat.outputs.where((f) => stored.contains(f.name)).toList();
  }

  @override
  Future<void> saveAllowedFormats(List<ImageFormat> formats) => _prefs.setStringList(_allowedFormatsKey, formats.map((f) => f.name).toList());

  @override
  QualityMode getQualityMode() => QualityMode.values.asNameMap()[_prefs.getString(_qualityModeKey)] ?? QualityMode.lossless;

  @override
  Future<void> saveQualityMode(QualityMode mode) => _prefs.setString(_qualityModeKey, mode.name);

  @override
  bool getAllowConversion() => _prefs.getBool(_allowConversionKey) ?? true;

  @override
  Future<void> saveAllowConversion(bool value) => _prefs.setBool(_allowConversionKey, value);

  @override
  bool getRecursive() => _prefs.getBool(_recursiveKey) ?? false;

  @override
  Future<void> saveRecursive(bool value) => _prefs.setBool(_recursiveKey, value);
}
