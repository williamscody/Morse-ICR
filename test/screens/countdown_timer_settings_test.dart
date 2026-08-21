import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/screens/countdown_timer_settings.dart';
import 'package:morse_icr/training/countdown_timer_config.dart';
import 'package:morse_icr/training/countdown_timer_store.dart';

class _FakeCountdownTimerStore implements CountdownTimerStore {
  _FakeCountdownTimerStore([this.saved = const CountdownTimerConfig()]);

  CountdownTimerConfig saved;

  @override
  Future<CountdownTimerConfig> load() async => saved;

  @override
  Future<void> save(CountdownTimerConfig config) async {
    saved = config;
  }
}

/// Holds the eventual push() result so callers can both drive the pushed
/// screen (tapping through it via [tester]) and read what it returns once
/// popped, without the awkward inline-closure gymnastics a plain `await
/// push()` would require alongside further interaction.
class _PushedConfig {
  CountdownTimerConfig? value;
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  Future<_PushedConfig> pushSettings(
    WidgetTester tester,
    CountdownTimerStore store,
  ) async {
    final pushed = _PushedConfig();
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              pushed.value = await Navigator.of(context)
                  .push<CountdownTimerConfig>(
                    MaterialPageRoute(
                      builder: (_) => CountdownTimerSettings(store: store),
                    ),
                  );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return pushed;
  }

  testWidgets('shows "Not set" for every memory and Off selected when '
      'nothing was previously saved', (tester) async {
    await tester.pumpWidget(
      wrap(CountdownTimerSettings(store: _FakeCountdownTimerStore())),
    );
    await tester.pump();

    expect(find.text('Not set'), findsNWidgets(3));
    final offRadio = tester.widget<RadioListTile<int?>>(
      find.byType(RadioListTile<int?>),
    );
    expect(offRadio.value, isNull);
  });

  testWidgets('pre-populates each memory\'s stored duration', (tester) async {
    await tester.pumpWidget(
      wrap(
        CountdownTimerSettings(
          store: _FakeCountdownTimerStore(
            const CountdownTimerConfig(
              slotSeconds: [300, null, 90],
              selectedSlot: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('05:00'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
  });

  testWidgets(
    'entering a value via Edit and Save persists it into that memory on '
    'Done, and selecting that memory persists it as the active timer',
    (tester) async {
      final store = _FakeCountdownTimerStore();
      final pushed = await pushSettings(tester, store);

      await tester.tap(find.widgetWithText(TextButton, 'Edit').first);
      await tester.pumpAndSettle();

      final minutesField = find.byType(TextField).first;
      await tester.enterText(minutesField, '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('05:00'), findsOneWidget);

      // Storing a value doesn't itself make it the active timer -- that's
      // a separate tap, same as any other now-populated memory.
      await tester.tap(find.text('Memory 1'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(store.saved.slotSeconds[0], 5 * 60);
      expect(store.saved.selectedSlot, 0);
      expect(pushed.value?.slotSeconds[0], 5 * 60);
    },
  );

  testWidgets('Clear in the edit dialog blanks that memory and deselects it '
      'if it was active', (tester) async {
    final store = _FakeCountdownTimerStore(
      const CountdownTimerConfig(
        slotSeconds: [300, null, null],
        selectedSlot: 0,
      ),
    );
    await pushSettings(tester, store);

    await tester.tap(find.widgetWithText(TextButton, 'Edit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Not set'), findsNWidgets(3));

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(store.saved.slotSeconds[0], isNull);
    expect(store.saved.selectedSlot, isNull);
  });

  testWidgets('Cancel in the edit dialog discards the edit', (tester) async {
    final store = _FakeCountdownTimerStore(
      const CountdownTimerConfig(slotSeconds: [300, null, null]),
    );
    await pushSettings(tester, store);

    await tester.tap(find.widgetWithText(TextButton, 'Edit').first);
    await tester.pumpAndSettle();
    final addButtons = find.byIcon(Icons.add_circle_outline);
    await tester.tap(addButtons.first);
    await tester.pump();
    // Scoped to the dialog: the settings screen's own top-level Cancel
    // button, still in the tree behind the dialog overlay, shares the
    // same text and would otherwise make this an ambiguous match.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('05:00'), findsOneWidget);
  });

  testWidgets('backing out via the top-level Cancel leaves the persisted '
      'config untouched, even after edits made within the screen', (
    tester,
  ) async {
    final store = _FakeCountdownTimerStore(
      const CountdownTimerConfig(
        slotSeconds: [300, null, null],
        selectedSlot: 0,
      ),
    );
    final pushed = await pushSettings(tester, store);

    // Edit memory 2, saving it into the working copy, but never tap Done.
    await tester.tap(find.widgetWithText(TextButton, 'Edit').at(1));
    await tester.pumpAndSettle();
    final addButtons = find.byIcon(Icons.add_circle_outline);
    await tester.tap(addButtons.first);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel')); // top-level Cancel
    await tester.pumpAndSettle();

    expect(store.saved.slotSeconds, [300, null, null]);
    expect(store.saved.selectedSlot, 0);
    expect(pushed.value, isNull);
  });

  testWidgets('a memory with nothing stored cannot be selected as the '
      'active timer', (tester) async {
    await tester.pumpWidget(
      wrap(CountdownTimerSettings(store: _FakeCountdownTimerStore())),
    );
    await tester.pump();

    // RadioListTile ("Off") also builds a ListTile internally, so this
    // is scoped to the 3 explicit "Memory N" rows rather than byType.
    for (var i = 1; i <= 3; i++) {
      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Memory $i'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.onTap, isNull, reason: 'Memory $i');
    }
  });
}
