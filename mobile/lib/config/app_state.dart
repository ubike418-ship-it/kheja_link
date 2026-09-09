import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide preferences that outlive a screen: the light/dark choice and
/// whether we have already asked for permissions.
///
/// There is no "system" option by design — the app is light or dark, and you
/// flip it by double-tapping anywhere on the home header rather than hunting
/// for a toggle icon.
class AppState extends ChangeNotifier {
  AppState._();

  static final AppState instance = AppState._();

  static const _kTheme = 'kheja.theme';
  static const _kOnboarded = 'kheja.permissions_asked';

  ThemeMode _themeMode = ThemeMode.light;
  bool _permissionsAsked = false;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  bool get permissionsAsked => _permissionsAsked;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _themeMode =
          (prefs.getString(_kTheme) == 'dark') ? ThemeMode.dark : ThemeMode.light;
      _permissionsAsked = prefs.getBool(_kOnboarded) ?? false;
    } catch (_) {
      // First run on a device with no store yet — defaults are fine.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTheme, isDark ? 'dark' : 'light');
    } catch (_) {
      // Not worth surfacing; the choice simply will not survive a restart.
    }
  }

  Future<void> markPermissionsAsked() async {
    _permissionsAsked = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOnboarded, true);
    } catch (_) {}
  }
}
