import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;

// Resolutions with a ratio other than 2 between levels (Swiss LV95 grid):
// 2.5 -> 2 -> 1.5 -> 1 m/px from zoom 22.
const _resolutions = <double>[
  4000, 3750, 3500, 3250, 3000, 2750, 2500, 2250, 2000, 1750, //
  1500, 1250, 1000, 750, 650, 500, 250, 100, 50, 20, //
  10, 5, 2.5, 2, 1.5, 1, 0.5, 0.25, 0.1,
];

final _customCrs = Proj4Crs.fromFactory(
  code: 'TEST:CUSTOM',
  proj4Projection: proj4.Projection.get('EPSG:3857')!,
  resolutions: _resolutions,
);

const _center = LatLng(46.5, 6.6);

/// Two fingers around [c], [scale] times their initial 100 px apart and
/// rotated by [degrees].
List<Offset> _fingers(Offset c, double scale, double degrees) {
  final a = degrees * math.pi / 180;
  final v = Offset(math.cos(a), math.sin(a)) * 50 * scale;
  return [c - v, c + v];
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
  group('pinch zoom', () {
    testWidgets('doubles the scale when the ratio between levels is not 2',
        (tester) async {
      final controller = await _pumpMap(tester, crs: _customCrs, zoom: 22);
      await _pinch(tester, [(1.5, 0), (2, 0)]);
      expect(
        _customCrs.scale(controller.camera.zoom) / _customCrs.scale(22),
        closeTo(2, 1e-3),
      );
    });

    testWidgets('adds one level in EPSG:3857', (tester) async {
      final controller =
          await _pumpMap(tester, crs: const Epsg3857(), zoom: 10);
      await _pinch(tester, [(1.5, 0), (2, 0)]);
      expect(controller.camera.zoom, closeTo(11, 1e-3));
    });
  });

  testWidgets('a small rotation across ±180° does not win the gesture race',
      (tester) async {
    final controller = await _pumpMap(
      tester,
      crs: const Epsg3857(),
      zoom: 10,
      options: const InteractionOptions(enableMultiFingerGestureRace: true),
    );
    // The line between the fingers starts at 180°.
    await _pinch(tester, [(1.2, 2), (1.4, 4)]);
    expect(controller.camera.rotation, 0);
  });
}
