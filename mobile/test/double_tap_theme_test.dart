import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kheja_link/config/app_state.dart';
import 'package:kheja_link/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<int> pumpApp(WidgetTester tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DoubleTapThemeToggle(
          child: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(onPressed: () => taps++, child: const Text('Button')),
                  const SizedBox(height: 200, width: 200),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return taps;
  }

  testWidgets('a double tap anywhere switches light and dark', (tester) async {
    await pumpApp(tester);
    final before = AppState.instance.isDark;

    await tester.tapAt(const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(42, 41));
    await tester.pump();
    expect(AppState.instance.isDark, !before);

    await tester.pump(const Duration(seconds: 1));
    await tester.tapAt(const Offset(300, 500));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(300, 500));
    await tester.pump();
    expect(AppState.instance.isDark, before, reason: 'and back again');
  });

  testWidgets('a single tap does not switch, and buttons still work at once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DoubleTapThemeToggle(
          child: Scaffold(
            body: Center(child: ElevatedButton(onPressed: () => taps++, child: const Text('Button'))),
          ),
        ),
      ),
    );
    final before = AppState.instance.isDark;
    await tester.tap(find.text('Button'));
    await tester.pump();
    expect(taps, 1, reason: 'the button responds on the first tap, with no delay');
    await tester.pump(const Duration(seconds: 1));
    expect(AppState.instance.isDark, before);
  });

  testWidgets('two slow taps, or a drag, do not switch', (tester) async {
    await pumpApp(tester);
    final before = AppState.instance.isDark;

    // The switch times taps on the real clock, so wait in real time.
    await tester.tapAt(const Offset(40, 40));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.tapAt(const Offset(40, 40));
    await tester.pump();
    expect(AppState.instance.isDark, before, reason: 'too slow');

    await tester.pump(const Duration(seconds: 1));
    await tester.dragFrom(const Offset(40, 40), const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.dragFrom(const Offset(40, 40), const Offset(0, 120));
    await tester.pump();
    expect(AppState.instance.isDark, before, reason: 'drags are scrolling, not taps');
  });
}
