import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taza_niyet/core/theme/app_theme.dart';
import 'package:taza_niyet/core/widgets/app_button.dart';

Widget _wrap(Widget child, {Brightness b = Brightness.light}) =>
    MaterialApp(theme: buildTheme(b), home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('нажатие вызывает onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(AppButton(label: 'Записаться', onPressed: () => taps++)));
    await tester.tap(find.text('Записаться'));
    expect(taps, 1);
  });

  testWidgets('неактивная кнопка полупрозрачная (38%)', (tester) async {
    await tester.pumpWidget(_wrap(const AppButton(label: 'Записаться', onPressed: null)));
    final opacity = tester.widget<AnimatedOpacity>(
      find.descendant(of: find.byType(AppButton), matching: find.byType(AnimatedOpacity)),
    );
    expect(opacity.opacity, 0.38);
  });

  testWidgets('в загрузке показывает индикатор и не нажимается', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(AppButton(label: 'Записаться', loading: true, onPressed: () => taps++)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(AppButton));
    expect(taps, 0);
  });

  testWidgets('высота кнопки не меньше 48 (зона нажатия)', (tester) async {
    await tester.pumpWidget(_wrap(AppButton(label: 'OK', onPressed: () {}, expand: false)));
    expect(tester.getSize(find.byType(AppButton)).height, greaterThanOrEqualTo(48));
  });

  testWidgets('тёмная тема собирается', (tester) async {
    await tester.pumpWidget(_wrap(AppButton(label: 'OK', onPressed: () {}), b: Brightness.dark));
    expect(find.text('OK'), findsOneWidget);
  });
}
