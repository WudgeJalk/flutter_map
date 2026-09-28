import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _center = LatLng(46.5, 6.6);

/// Two fingers around [c], [scale] times their initial 100 px apart and
/// rotated by [degrees].
List<Offset> _fingers(Offset c, double scale, double degrees) {
  final a = degrees * math.pi / 180;
  final v = Offset(math.cos(a), math.sin(a)) * 50 * scale;
  // Pointer 1 on the right: the line between the fingers starts at 0°.
  return [c + v, c - v];
}

Future<MapController> _pumpMap(
  WidgetTester tester, {
  required Crs crs,
  required double zoom,
  InteractionOptions options = const InteractionOptions(),
}) async {
  final controller = MapController();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: FlutterMap(
            mapController: controller,
            options: MapOptions(
              crs: crs,
              initialCenter: _center,
              initialZoom: zoom,
              minZoom: 8,
              maxZoom: 28,
              interactionOptions: options,
            ),
            children: const [],
          ),
        ),
      ),
    ),
  );
  return controller;
}

/// Pinches/rotates through [steps] of (scale, degrees); [onStep] runs after
/// each step.
Future<void> _pinch(
  WidgetTester tester,
  List<(double, double)> steps, {
  void Function(int)? onStep,
}) async {
  final c = tester.getCenter(find.byType(FlutterMap));
  final start = _fingers(c, 1, 0);
  final g1 = await tester.startGesture(start[0], pointer: 1);
  final g2 = await tester.startGesture(start[1], pointer: 2);
  await tester.pump();
  for (var i = 0; i < steps.length; i++) {
    final p = _fingers(c, steps[i].$1, steps[i].$2);
    await g1.moveTo(p[0]);
    await g2.moveTo(p[1]);
    await tester.pump();
    onStep?.call(i);
  }
  await g1.up();
  await g2.up();
  await tester.pumpAndSettle();
  // Let the double tap timer expire.
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('rotation dead zone (15°)', () {
    const options = InteractionOptions(rotationDeadZone: 15);

    testWidgets('10°: zoom applies, rotation does not', (tester) async {
      final controller = await _pumpMap(tester,
          crs: const Epsg3857(), zoom: 10, options: options);
      await _pinch(tester, [(1.5, 5), (2, 10)]);
      expect(controller.camera.zoom, closeTo(11, 1e-3));
      expect(controller.camera.rotation, 0);
    });

    testWidgets('25° -> 10°, then 30° -> 15°, without a jump', (tester) async {
      final controller = await _pumpMap(tester,
          crs: const Epsg3857(), zoom: 10, options: options);
      final rotations = <double>[];
      await _pinch(
        tester,
        [(1.2, 10), (1.4, 25), (1.6, 30)],
        onStep: (_) => rotations.add(controller.camera.rotation),
      );
      expect(rotations[0], 0);
      expect(rotations[1], closeTo(10, 1e-6));
      expect(rotations[2], closeTo(15, 1e-6));
    });

    testWidgets('defaults to 0: rotation applies at once', (tester) async {
      final controller =
          await _pumpMap(tester, crs: const Epsg3857(), zoom: 10);
      await _pinch(tester, [(1.5, 10)]);
      expect(controller.camera.rotation, closeTo(10, 1e-6));
    });
  });
}
