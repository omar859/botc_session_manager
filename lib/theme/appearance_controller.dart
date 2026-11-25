import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { dark, defaultTheme, white }

enum AppAccent {
  green('Green', 0xFF00C98A),
  orange('Orange', 0xFFFF8A3D),
  red('Red', 0xFFEF5350),
  blue('Blue', 0xFF4A90E2),
  yellow('Yellow', 0xFFF2C94C),
  cyan('Cyan', 0xFF24D6D0);

  const AppAccent(this.label, this.value);

  final String label;
  final int value;
}

class AppearanceController extends ChangeNotifier {
  static const _modeKey = 'appearance.themeMode';
  static const _accentKey = 'appearance.accent';

  AppThemeMode mode = AppThemeMode.defaultTheme;
  AppAccent accent = AppAccent.green;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getInt(_modeKey);
    final savedAccent = prefs.getInt(_accentKey);

    if (savedMode != null &&
        savedMode >= 0 &&
        savedMode < AppThemeMode.values.length) {
      mode = AppThemeMode.values[savedMode];
    }
    if (savedAccent != null &&
        savedAccent >= 0 &&
        savedAccent < AppAccent.values.length) {
      accent = AppAccent.values[savedAccent];
    }
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode value) async {
    if (mode == value) return;
    mode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_modeKey, value.index);
  }

  Future<void> setAccent(AppAccent value) async {
    if (accent == value) return;
    accent = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentKey, value.index);
  }
}
