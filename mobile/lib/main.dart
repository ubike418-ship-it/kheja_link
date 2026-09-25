import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_state.dart';
import 'config/supabase_config.dart';
import 'config/theme.dart';
import 'screens/splash_screen.dart';
import 'services/kheja_api.dart';

/// Single Supabase-backed API instance for the whole app.
late final KhejaApi khejaApi;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A missing .env should produce a readable screen, not a blank one.
  String? startupError;
  try {
    await dotenv.load(fileName: '.env', isOptional: true);
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
    khejaApi = KhejaApi(Supabase.instance.client);
  } catch (error) {
    startupError = error.toString();
  }

  runApp(KhejaApp(startupError: startupError));
}

class KhejaApp extends StatelessWidget {
  const KhejaApp({super.key, this.startupError});

  final String? startupError;

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app when the light/dark choice changes, which is what
    // makes the double-tap toggle feel instant.
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'Kheja_Link',
          debugShowCheckedModeBanner: false,
          theme: buildKhejaTheme(Brightness.light),
          darkTheme: buildKhejaTheme(Brightness.dark),
          // Light or dark only — never "system". You flip it by double-tapping
          // anywhere in the app rather than hunting for a toggle icon.
          themeMode: AppState.instance.themeMode,
          builder: (context, child) => DoubleTapThemeToggle(child: child ?? const SizedBox()),
          home: startupError == null
              ? const SplashScreen()
              : _ConfigErrorScreen(message: startupError!),
        );
      },
    );
  }
}

class _ConfigErrorScreen extends StatelessWidget {
  const _ConfigErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.settings_rounded, size: 56, color: KhejaColors.zinc400),
              const SizedBox(height: 24),
              Text(
                'Kheja_Link is not configured',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Copy .env.example to .env and add your Supabase URL and anon key, '
                'then restart the app.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: KhejaColors.zinc500),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: KhejaColors.zinc400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Double-tap anywhere in the app to switch between light and dark.
///
/// Built on raw pointer events rather than a GestureDetector, so it never
/// joins the gesture arena: buttons, lists and sheets respond exactly as fast
/// as before, and a single tap is never delayed waiting to see if a second one
/// follows. Two quick, short, nearby taps flip the theme. It stays out of the
/// way while typing, where a double tap selects a word, and ignores drags and
/// multi-finger touches.
class DoubleTapThemeToggle extends StatefulWidget {
  const DoubleTapThemeToggle({super.key, required this.child});

  final Widget child;

  @override
  State<DoubleTapThemeToggle> createState() => _DoubleTapThemeToggleState();
}

class _DoubleTapThemeToggleState extends State<DoubleTapThemeToggle> {
  static const _maxTapDuration = Duration(milliseconds: 250);
  static const _maxGap = Duration(milliseconds: 320);
  static const _maxSlop = 18.0;
  static const _maxDistance = 48.0;

  int _pointers = 0;
  Offset? _downAt;
  DateTime? _downTime;
  Offset? _lastTapAt;
  DateTime? _lastTapTime;

  bool get _typing => FocusManager.instance.primaryFocus?.context?.widget is EditableText;

  void _reset() {
    _downAt = null;
    _downTime = null;
    _lastTapAt = null;
    _lastTapTime = null;
  }

  void _onDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers > 1) {
      _reset();
      return;
    }
    _downAt = e.position;
    _downTime = DateTime.now();
  }

  void _onUp(PointerUpEvent e) {
    _pointers = _pointers > 0 ? _pointers - 1 : 0;
    final downAt = _downAt;
    final downTime = _downTime;
    _downAt = null;
    _downTime = null;
    if (downAt == null || downTime == null) return;

    final now = DateTime.now();
    final isTap = now.difference(downTime) <= _maxTapDuration &&
        (e.position - downAt).distance <= _maxSlop;
    if (!isTap || _typing) {
      _lastTapAt = null;
      _lastTapTime = null;
      return;
    }

    final lastAt = _lastTapAt;
    final lastTime = _lastTapTime;
    if (lastAt != null &&
        lastTime != null &&
        now.difference(lastTime) <= _maxGap &&
        (e.position - lastAt).distance <= _maxDistance) {
      _reset();
      HapticFeedback.selectionClick();
      AppState.instance.toggleTheme();
    } else {
      _lastTapAt = e.position;
      _lastTapTime = now;
    }
  }

  void _onCancel(PointerCancelEvent e) {
    _pointers = _pointers > 0 ? _pointers - 1 : 0;
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: widget.child,
    );
  }
}
