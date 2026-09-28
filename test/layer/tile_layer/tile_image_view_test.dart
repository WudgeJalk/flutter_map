import 'dart:async';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter/src/scheduler/ticker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_bounds/tile_bounds_at_zoom.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_image_view.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_range.dart';
import 'package:flutter_map/src/misc/bounds.dart';
import 'package:test/test.dart';

import '../../test_utils/test_tile_image.dart';

void main() {
  Map<TileCoordinates, TileImage> tileImagesMappingFrom(
          List<TileImage> tileImages) =>
      {for (final tileImage in tileImages) tileImage.coordinates: tileImage};

  DiscreteTileRange discreteTileRange(
    int x1,
    int y1,
    int x2,
    int y2, {
    required int zoom,
  }) =>
      DiscreteTileRange(
        zoom,
        IntegerBounds(Point(x1, y1), Point(x2, y2)),
      );

  group('staleTiles', () {
    test('tiles outside of the keep range are stale', () {
      const zoom = 10;
      final tileImages = tileImagesMappingFrom([
        MockTileImage(1, 1, zoom),
        MockTileImage(2, 1, zoom),
      ]);

      final removalState = TileImageView(
        tileImages: tileImages,
        positionCoordinates: Set<TileCoordinates>.from(tileImages.keys),
        visibleRange: discreteTileRange(2, 1, 3, 3, zoom: zoom),
        keepRange: discreteTileRange(2, 1, 3, 3, zoom: zoom),
        scaleAt: _scale3857,
      );
      expect(
        removalState.staleTiles,
        contains(const TileCoordinates(1, 1, zoom)),
      );
    });

    test('ancestor tile is not stale if a tile has not loaded yet', () {
      final tileImages = tileImagesMappingFrom([
        MockTileImage(0, 0, 0),
        MockTileImage(0, 0, 1, loadFinished: false, readyToDisplay: false),
      ]);
      final removalState = TileImageView(
        tileImages: tileImages,
        positionCoordinates: Set<TileCoordinates>.from(tileImages.keys),
        visibleRange: discreteTileRange(0, 0, 0, 0, zoom: 1),
        keepRange: discreteTileRange(0, 0, 0, 0, zoom: 1),
        scaleAt: _scale3857,
      );
      expect(
        removalState.staleTiles,
        isNot(contains(const TileCoordinates(0, 0, 0))),
      );
    });

    test('descendant tile is not stale if there is no loaded tile obscuring it',
        () {
      final tileImages = tileImagesMappingFrom([
        MockTileImage(0, 0, 0, loadFinished: false, readyToDisplay: false),
        MockTileImage(0, 0, 1, loadFinished: false, readyToDisplay: false),
        MockTileImage(0, 0, 2),
      ]);
      final removalState = TileImageView(
        tileImages: tileImages,
        positionCoordinates: Set<TileCoordinates>.from(tileImages.keys),
        visibleRange: discreteTileRange(0, 0, 0, 0, zoom: 1),
        keepRange: discreteTileRange(0, 0, 0, 0, zoom: 1),
        scaleAt: _scale3857,
      );
      expect(
        removalState.staleTiles,
        isNot(contains(const TileCoordinates(0, 0, 2))),
      );
    });

    test(
        'returned elements can be removed from the source collection in a for loop',
        () {
      const zoom = 10;
      final tileImages = tileImagesMappingFrom([
        MockTileImage(1, 1, zoom),
      ]);

      final removalState = TileImageView(
        tileImages: tileImages,
        positionCoordinates: Set<TileCoordinates>.from(tileImages.keys),
        visibleRange: discreteTileRange(2, 1, 3, 3, zoom: zoom),
        keepRange: discreteTileRange(2, 1, 3, 3, zoom: zoom),
        scaleAt: _scale3857,
      );
      expect(
        removalState.staleTiles,
        contains(const TileCoordinates(1, 1, zoom)),
      );
      // If an iterator over the original collection is returned then when
      // looping over that iterator and removing from the original collection
      // a concurrent modification exception is thrown. This ensures that the
      // returned collection is not an iterable over the original collection.
      for (final staleTile in removalState.staleTiles) {
        tileImages.remove(staleTile)!;
      }
    });
  });

  test('errorTilesOutsideOfKeepMargin', () {
    final tileImages = tileImagesMappingFrom([
      MockTileImage(1, 1, 1, loadError: true),
      MockTileImage(2, 1, 1),
      MockTileImage(1, 2, 1),
      MockTileImage(2, 2, 1, loadError: true),
    ]);
    final tileImageView = TileImageView(
      tileImages: tileImages,
      positionCoordinates: Set<TileCoordinates>.from(tileImages.keys),
      visibleRange: discreteTileRange(1, 2, 1, 2, zoom: 1),
      keepRange: discreteTileRange(1, 2, 2, 2, zoom: 1),
      scaleAt: _scale3857,
    );
    expect(
      tileImageView.errorTilesOutsideOfKeepMargin(),
      [const TileCoordinates(1, 1, 1)],
    );

    // If an iterator over the original collection is returned then when
    // looping over that iterator and removing from the original collection
    // a concurrent modification exception is thrown. This ensures that the
    // returned collection is not an iterable over the original collection.
    for (final coordinates in tileImageView.errorTilesOutsideOfKeepMargin()) {
      tileImages.remove(coordinates)!;
    }
  });

  group('renderTiles', () {
    test('%.retainChildren uses correct coordinates for z+2 fallback', () {
      // This test verifies that _retainChildren correctly calculates
      // descendant coordinates when recursing to z+2 level.
      // Using large coordinates (100, 200) to catch the bug where
      // i,j (0-1) was passed instead of 2*x+i, 2*y+j.
      const baseZoom = 10;
      final tileImages = tileImagesMappingFrom([
        // z=10 tile not ready
        MockTileImage(100, 200, baseZoom,
            loadFinished: false, readyToDisplay: false),
        // z=11 tiles don't exist
        // z=12 tile exists and is ready (this is what we want to fall back to)
        MockTileImage(400, 800, baseZoom + 2),
      ]);

      final tileImageView = TileImageView(
        tileImages: tileImages,
        positionCoordinates: Set<TileCoordinates>.from(tileImages.keys),
        visibleRange: discreteTileRange(100, 200, 100, 200, zoom: baseZoom),
        keepRange: discreteTileRange(100, 200, 100, 200, zoom: baseZoom),
        scaleAt: _scale3857,
      );

      final renderTiles = tileImageView.renderTiles.toList();
      expect(
        renderTiles,
        contains(const TileCoordinates(400, 800, baseZoom + 2)),
      );
    });
  });

  group('zoom levels with a ratio other than 2', () {
    // Scale ratio of 1.25 between two zoom levels (e.g. the Swiss LV95 grid).
    double scaleAt(int zoom) => pow(1.25, zoom).toDouble();
    // Target zoom 1, x 5..6: the footprint of tile (4, 0, 0) is x 5..6.
    final visible = discreteTileRange(5, 0, 6, 0, zoom: 1);

    TileImageView view(
      List<TileImage> tiles, {
      TileBoundsAtZoom? targetBounds,
    }) {
      final tileImages = tileImagesMappingFrom(tiles);
      return TileImageView(
        tileImages: tileImages,
        positionCoordinates: Set<TileCoordinates>.from(tileImages.keys),
        visibleRange: visible,
        keepRange: visible,
        scaleAt: scaleAt,
        targetBounds: targetBounds,
      );
    }

    const lower = TileCoordinates(4, 0, 0);

    test('a lower zoom tile is kept until its footprint is covered', () {
      final loading = view([
        MockTileImage(4, 0, 0),
        MockTileImage(5, 0, 1),
        MockTileImage(6, 0, 1, loadFinished: false, readyToDisplay: false),
      ]);
      expect(loading.renderTiles, contains(lower));
      expect(loading.staleTiles, isNot(contains(lower)));

      final loaded = view([
        MockTileImage(4, 0, 0),
        MockTileImage(5, 0, 1),
        MockTileImage(6, 0, 1),
      ]);
      expect(loaded.renderTiles, isNot(contains(lower)));
      expect(loaded.staleTiles, [lower]);
    });

    test('a higher zoom tile is kept while zooming out', () {
      final tileImages = tileImagesMappingFrom([
        MockTileImage(4, 0, 0, loadFinished: false, readyToDisplay: false),
        MockTileImage(5, 0, 1),
      ]);
      final range = discreteTileRange(4, 0, 4, 0, zoom: 0);
      final tileImageView = TileImageView(
        tileImages: tileImages,
        positionCoordinates: Set<TileCoordinates>.from(tileImages.keys),
        visibleRange: range,
        keepRange: range,
        scaleAt: scaleAt,
      );
      expect(
        tileImageView.renderTiles,
        contains(const TileCoordinates(5, 0, 1)),
      );
      expect(tileImageView.staleTiles, isEmpty);
    });

    test('a tile of another zoom outside of the footprint is not kept', () {
      // x 6 falls in the range, but its footprint is x 7..8 at zoom 1.
      final tileImageView = view([
        MockTileImage(6, 0, 0),
        MockTileImage(5, 0, 1, loadFinished: false, readyToDisplay: false),
      ]);
      expect(
        tileImageView.renderTiles,
        isNot(contains(const TileCoordinates(6, 0, 0))),
      );
      expect(tileImageView.staleTiles, [const TileCoordinates(6, 0, 0)]);
    });

    test('a tile of another zoom which is not ready is stale', () {
      final tileImageView = view([
        MockTileImage(4, 0, 0, loadFinished: false, readyToDisplay: false),
        MockTileImage(5, 0, 1, loadFinished: false, readyToDisplay: false),
      ]);
      expect(tileImageView.staleTiles, [lower]);
    });

    test('a target tile in error without error image keeps the fallback', () {
      final tileImageView = view([
        MockTileImage(4, 0, 0),
        MockTileImage(5, 0, 1),
        MockTileImage(6, 0, 1, loadError: true, readyToDisplay: false),
      ]);
      expect(tileImageView.renderTiles, contains(lower));
    });

    test('a lower zoom tile is clipped to the holes of a transparent layer',
        () {
      // Footprint of (4, 0, 0) at zoom 1: x 5..6, y 0..1. One target tile
      // failed (offline), three are ready: the fallback must only paint in
      // the failed cell, not under the ready ones (doubled overlay lines).
      final visible2d = discreteTileRange(5, 0, 6, 1, zoom: 1);
      final tileImages = tileImagesMappingFrom([
        MockTileImage(4, 0, 0),
        MockTileImage(5, 0, 1),
        MockTileImage(6, 0, 1),
        MockTileImage(5, 1, 1),
        MockTileImage(6, 1, 1, loadError: true),
      ]);
      final tileImageView = TileImageView(
        tileImages: tileImages,
        positionCoordinates: Set<TileCoordinates>.from(tileImages.keys),
        visibleRange: visible2d,
        keepRange: visible2d,
        scaleAt: scaleAt,
      );
      final render = {
        for (final (c, clip) in tileImageView.renderTilesWithClip) c: clip,
      };
      expect(render.keys, contains(lower));
      final clip = render[lower]!;
      expect(clip, hasLength(1));
      // Cell (6, 1) spans [4.8, 5.6] × [0.8, 1.6] in zoom 0 tile units.
      expect(clip.single.left, closeTo(0.8, 1e-9));
      expect(clip.single.top, closeTo(0.8, 1e-9));
      expect(clip.single.right, 1);
      expect(clip.single.bottom, 1);
      // Target tiles are never clipped.
      expect(render[const TileCoordinates(5, 0, 1)], isNull);
    });

    test('a lower zoom tile under holes only is not clipped', () {
      final loading = view([
        MockTileImage(4, 0, 0),
        MockTileImage(5, 0, 1, loadFinished: false, readyToDisplay: false),
        MockTileImage(6, 0, 1, loadFinished: false, readyToDisplay: false),
      ]);
      expect(loading.renderTilesWithClip, contains((lower, null)));
    });

    test('invalid target tiles keep nothing', () {
      final tileImageView = view(
        [MockTileImage(4, 0, 0)],
        targetBounds: DiscreteTileBoundsAtZoom(
          discreteTileRange(0, 0, 4, 0, zoom: 1),
        ),
      );
      expect(tileImageView.renderTiles, isEmpty);
      expect(tileImageView.staleTiles, [lower]);
    });

    test('one fallback level per hole, the closest (finer on a tie) first', () {
      // Target z22 x 5..6, y 0..1, not ready. z21 x 4..5, y 0..1 is ready
      // over all of it; the ready z23 tiles cover cell (5, 0) whole, cell (6, 0) in part
      // (z23 x 8 is missing) and nothing of row 1 (z23 y 2 is missing).
      final range = discreteTileRange(5, 0, 6, 1, zoom: 22);
      final tileImages = tileImagesMappingFrom([
        for (final c in range.coordinates)
          MockTileImage(c.x, c.y, 22,
              loadFinished: false, readyToDisplay: false),
        for (final (x, y) in const [(4, 0), (5, 0), (4, 1), (5, 1)])
          MockTileImage(x, y, 21),
        for (final (x, y) in const [(6, 0), (7, 0), (6, 1), (7, 1)])
          MockTileImage(x, y, 23),
      ]);
      final tileImageView = TileImageView(
        tileImages: tileImages,
        positionCoordinates: Set<TileCoordinates>.from(tileImages.keys),
        visibleRange: range,
        keepRange: range,
        scaleAt: scaleAt,
      );
      final render = tileImageView.renderTilesWithClip.toList();
      // Painted area of each fallback level, in z22 tile units.
      final painted = <int, List<Rect>>{};
      for (final (c, clip) in render) {
        if (c.z == 22) continue;
        final r = scaleAt(22) / scaleAt(c.z);
        for (final u in clip ?? const [Rect.fromLTRB(0, 0, 1, 1)]) {
          painted.putIfAbsent(c.z, () => []).add(Rect.fromLTRB(
              (c.x + u.left) * r,
              (c.y + u.top) * r,
              (c.x + u.right) * r,
              (c.y + u.bottom) * r));
        }
      }
      Set<int> levelsIn(int x, int y) {
        final cell =
            Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1).deflate(1e-6);
        return {
          for (final e in painted.entries)
            if (e.value.any((p) {
              final i = p.intersect(cell);
              return i.width > 1e-9 && i.height > 1e-9;
            }))
              e.key,
        };
      }

      expect(levelsIn(5, 0), {23}, reason: 'z23 covers it whole, and is finer');
      expect(levelsIn(6, 0), {21}, reason: 'z23 only covers part of it');
      expect(levelsIn(5, 1), {21});
      expect(levelsIn(6, 1), {21});
      // z23 (6, 1) is only under cells (5, 0) and (5, 1): kept for (5, 0).
      expect(
          render.map((t) => t.$1), contains(const TileCoordinates(6, 1, 23)));
      expect(tileImageView.staleTiles, isEmpty);
    });

    test('fallback levels are capped at z - 5 and z + 2', () {
      final range = discreteTileRange(5, 0, 5, 0, zoom: 10);
      final tileImages = tileImagesMappingFrom([
        MockTileImage(5, 0, 10, loadFinished: false, readyToDisplay: false),
        MockTileImage(1, 0, 4),
        MockTileImage(1, 0, 5),
        MockTileImage(9, 0, 13),
      ]);
      final tileImageView = TileImageView(
        tileImages: tileImages,
        positionCoordinates: Set<TileCoordinates>.from(tileImages.keys),
        visibleRange: range,
        keepRange: range,
        scaleAt: scaleAt,
      );
      expect(tileImageView.renderTiles.map((c) => c.z).toSet(), {10, 5});
      expect(
        tileImageView.staleTiles.toSet(),
        {const TileCoordinates(1, 0, 4), const TileCoordinates(9, 0, 13)},
      );
    });
  });

  test('errorTilesNotVisible', () {
    const zoom = 10;
    final tileImages = tileImagesMappingFrom([
      MockTileImage(1, 1, zoom, loadError: true),
      MockTileImage(2, 1, zoom),
      MockTileImage(1, 2, zoom),
      MockTileImage(2, 2, zoom, loadError: true),
    ]);
    final tileImageView = TileImageView(
      tileImages: tileImages,
      positionCoordinates: Set<TileCoordinates>.from(tileImages.keys),
      visibleRange: discreteTileRange(1, 2, 1, 2, zoom: zoom),
      keepRange: discreteTileRange(1, 2, 2, 2, zoom: zoom),
      scaleAt: _scale3857,
    );
    expect(
      tileImageView.errorTilesNotVisible(),
      [const TileCoordinates(1, 1, zoom), const TileCoordinates(2, 2, zoom)],
    );

    // If an iterator over the original collection is returned then when
    // looping over that iterator and removing from the original collection
    // a concurrent modification exception is thrown. This ensures that the
    // returned collection is not an iterable over the original collection.
    for (final coordinates in tileImageView.errorTilesOutsideOfKeepMargin()) {
      tileImages.remove(coordinates)!;
    }
  });
}

double _scale3857(int zoom) => const Epsg3857().scale(zoom.toDouble());

class MockTileImage extends TileImage {
  @override
  final bool readyToDisplay;

  MockTileImage(
    int x,
    int y,
    int zoom, {
    this.readyToDisplay = true,
    bool loadFinished = true,
    bool loadError = false,
    void Function(TileCoordinates coordinates)? onLoadComplete,
    void Function(TileImage tile, Object error, StackTrace? stackTrace)?
        onLoadError,
    super.errorImage,
  }) : super(
          coordinates: TileCoordinates(x, y, zoom),
          vsync: const MockTickerProvider(),
          imageProvider: testWhiteTileImage,
          onLoadComplete: onLoadComplete ?? (_) {},
          onLoadError: onLoadError ?? (_, __, ___) {},
          tileDisplay: const TileDisplay.instantaneous(),
          cancelLoading: Completer(),
        ) {
    loadFinishedAt = loadFinished ? DateTime.now() : null;
    this.loadError = loadError;
  }
}

class MockTickerProvider extends TickerProvider {
  const MockTickerProvider();

  @override
  Ticker createTicker(TickerCallback onTick) {
    return Ticker((elapsed) {});
  }
}
