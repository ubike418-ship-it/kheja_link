import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide preferences that outlive a screen: the light/dark choice, the
/// door (tenant or landlord) chosen, and which tours have been seen.
///
/// There is no "system" option by design — the app is light or dark, and you
/// flip it by double-tapping anywhere in the app rather than hunting for a
/// toggle icon.
class AppState extends ChangeNotifier {
  AppState._();

  static final AppState instance = AppState._();

  static const _kTheme = 'kheja.theme';
  static const _kRole = 'kheja.chosen_role';
  static String _kTutorial(String role) => 'kheja.onboarding_completed.$role';

  ThemeMode _themeMode = ThemeMode.light;
  bool _loaded = false;

  /// Roles whose first-run tutorial this device has finished or skipped:
  /// 'tenant', 'landlord'. Stored per role, so switching to landlord later
  /// still shows the landlord tour once.
  final Set<String> _toured = {};

  /// Bumped when someone asks to see the tutorial again from their account.
  /// The home screens listen for it.
  int _tutorialRequest = 0;
  String? _tutorialRequestRole;

  /// Which door the person came in through: 'seeker' (tenant) or 'landlord'.
  /// Null until they choose. The database role on their account is still the
  /// source of truth once they sign in — this only decides what a signed-out
  /// visitor sees and which sign-in screen to offer.
  String? _chosenRole;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  bool get isLoaded => _loaded;
  String? get chosenRole => _chosenRole;
  bool get hasChosenRole => _chosenRole != null;
  bool get choseLandlord => _chosenRole == 'landlord';

  bool hasToured(String role) => _toured.contains(role);
  int get tutorialRequest => _tutorialRequest;
  String? get tutorialRequestRole => _tutorialRequestRole;

  /// Records that [role]'s tutorial is done on this device.
  Future<void> markToured(String role) async {
    if (_toured.add(role)) notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kTutorial(role), true);
    } catch (_) {}
  }

  /// "Show me around again", from the account screen.
  void requestTutorial(String role) {
    _tutorialRequestRole = role;
    _tutorialRequest++;
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _themeMode =
          (prefs.getString(_kTheme) == 'dark') ? ThemeMode.dark : ThemeMode.light;
      _chosenRole = prefs.getString(_kRole);
      for (final role in const ['tenant', 'landlord']) {
        if (prefs.getBool(_kTutorial(role)) ?? false) _toured.add(role);
      }
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

  Future<void> setChosenRole(String? role) async {
    _chosenRole = role;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (role == null) {
        await prefs.remove(_kRole);
      } else {
        await prefs.setString(_kRole, role);
      }
    } catch (_) {}
  }
}
