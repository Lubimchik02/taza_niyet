import 'package:flutter_test/flutter_test.dart';
import 'package:taza_niyet/core/widgets/leaf.dart';
import 'package:taza_niyet/features/splash/leaf_fall.dart';

void main() {
  group('падение листа', () {
    test('начинается в исходной точке и лежит горизонтально', () {
      final p = leafFallPose(0);
      expect(p.dx, closeTo(0, 1e-9));
      expect(p.dy, closeTo(0, 1e-9));
      expect(p.rot, closeTo(45, 1e-9));
    });

    test('заканчивается на земле, лёжа (не встаёт дыбом)', () {
      final p = leafFallPose(1);
      expect(p.dx, closeTo(kFallDx, 1e-6));
      expect(p.dy, closeTo(kFallDy, 1e-6));
      expect(p.rot, closeTo(45, 1e-6));
    });

    test('в полёте наклон не больше ±30° от горизонтали', () {
      for (var i = 0; i <= 100; i++) {
        final r = leafFallPose(i / 100).rot;
        expect((r - 45).abs(), lessThanOrEqualTo(30));
      }
    });

    test('лист опускается, а не взлетает вверх выше старта', () {
      for (var i = 1; i <= 100; i++) {
        expect(leafFallPose(i / 100).dy, greaterThan(-20));
      }
    });
  });

  test('путь фирменного листа разбирается', () {
    final path = parseSvgPath(kLeafPathData);
    final b = path.getBounds();
    expect(b.left, greaterThanOrEqualTo(3));
    expect(b.right, lessThanOrEqualTo(97));
    expect(b.width, greaterThan(80));
  });
}
