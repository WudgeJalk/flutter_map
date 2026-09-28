import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_bounds/tile_bounds_at_zoom.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_range.dart';

/// The [TileImageView] stores all loaded [TileImage]s with their
/// [TileCoordinates].
final class TileImageView {
  final Map<TileCoordinates, TileImage> _tileImages;
  final Set<TileCoordinates> _positionCoordinates;
  final DiscreteTileRange _visibleRange;
  final DiscreteTileRange _keepRange;
  final TileCoordinatesResolver _resolver;
  final double Function(int zoom) _scaleAt;
  final TileBoundsAtZoom? _targetBounds;

  /// Create a new [TileImageView] instance.
  ///
  /// [scaleAt] is the CRS scale of a zoom level (`crs.scale(zoom)`): tiles of
  /// other zoom levels are matched to the target zoom by their projected
  /// footprint, so any ratio between zoom levels works, not only 2.
  /// [targetBounds] are the tile bounds at the target zoom: invalid tiles
  /// never keep a tile of another zoom level alive.
  const TileImageView({
    required Map<TileCoordinates, TileImage> tileImages,
    required Set<TileCoordinates> positionCoordinates,
    required DiscreteTileRange visibleRange,
    required DiscreteTileRange keepRange,
    required double Function(int zoom) scaleAt,
    TileBoundsAtZoom? targetBounds,
    final TileCoordinatesResolver resolver =
        const TileCoordinatesResolver(false),
  })  : _tileImages = tileImages,
        _positionCoordinates = positionCoordinates,
        _visibleRange = visibleRange,
        _keepRange = keepRange,
        _scaleAt = scaleAt,
        _targetBounds = targetBounds,
        _resolver = resolver;

  /// Get a list with all tiles that have an error and are outside of the
  /// margin that should get kept.
  List<TileCoordinates> errorTilesOutsideOfKeepMargin() =>
      _errorTilesWithinRange(_keepRange);

  /// Get a list with all tiles that are not visible on the current map
  /// viewport.
  List<TileCoordinates> errorTilesNotVisible() =>
      _errorTilesWithinRange(_visibleRange);

  /// Get a list with all tiles that are not visible on the current map
  /// viewport.
  List<TileCoordinates> _errorTilesWithinRange(DiscreteTileRange range) {
    final List<TileCoordinates> result = <TileCoordinates>[];
    for (final positionCoordinates in _positionCoordinates) {
      if (range.contains(
        positionCoordinates,
        replicatesWorldLongitude: _resolver.replicatesWorldLongitude,
      )) {
        continue;
      }
      final TileImage? tileImage =
          _tileImages[_resolver.get(positionCoordinates)];
      if (tileImage?.loadError ?? false) {
        result.add(positionCoordinates);
      }
    }
    return result;
  }

  /// Get a list of [TileImage] that are stale and can get for pruned.
  ///
  /// A tile at the target zoom is stale outside of the keep range. A tile at
  /// another zoom is stale unless it is the fallback of a hole of the keep
  /// range (see [_Fallbacks]): a tile which does not cover yet and will be
  /// loaded — visible, or already created (the rest of the keep range is
  /// never loaded, it must not keep other zoom levels in memory).
  Iterable<TileCoordinates> get staleTiles {
    final fallbacks = _fallbacksIn(_keepRange);
    final stale = <TileCoordinates>[];
    for (final positionCoordinates in _positionCoordinates) {
      final keep = positionCoordinates.z == _keepRange.zoom
          ? _keepRange.contains(
              positionCoordinates,
              replicatesWorldLongitude: _resolver.replicatesWorldLongitude,
            )
          : fallbacks.clip(positionCoordinates) != _Fallbacks.none;
      if (!keep) stale.add(positionCoordinates);
    }
    return stale;
  }

  /// Get a list of [TileCoordinates] that need to get rendered on screen.
  ///
  /// All tiles of the visible range at the target zoom (ready or not, so that
  /// they show up once loaded), plus the fallback tiles of other zoom levels
  /// under the holes left by visible tiles which do not cover yet.
  Iterable<TileCoordinates> get renderTiles =>
      renderTilesWithClip.map((tile) => tile.$1);

  /// [renderTiles], each with its clip: `null` to paint the whole tile, or
  /// the holes it fills, as rectangles in the unit square of that tile. A
  /// tile of another zoom level only paints the holes it is the fallback of:
  /// in a transparent layer, painting it under the ready tiles (or under a
  /// fallback of a closer zoom) would show its stretched drawing through them.
  Iterable<(TileCoordinates, List<Rect>?)> get renderTilesWithClip {
    final fallbacks = _fallbacksIn(_visibleRange);
    final render = <(TileCoordinates, List<Rect>?)>[];
    for (final positionCoordinates in _positionCoordinates) {
      if (positionCoordinates.z == _visibleRange.zoom) {
        if (_visibleRange.contains(
          positionCoordinates,
          replicatesWorldLongitude: _resolver.replicatesWorldLongitude,
        )) {
          render.add((positionCoordinates, null));
        }
      } else {
        final clip = fallbacks.clip(positionCoordinates);
        if (clip != _Fallbacks.none) render.add((positionCoordinates, clip));
      }
    }
    return render;
  }

  /// Whether the tile paints its area: ready to display, and not a load
  /// error without an error image (`readyToDisplay` is also set on error, but
  /// such a tile paints nothing — it must neither hide the fallback below
  /// it nor be kept as a fallback).
  bool _covers(TileCoordinates coordinates) {
    final tile = _tileImages[_resolver.get(coordinates)];
    return tile != null &&
        tile.readyToDisplay &&
        !(tile.loadError && tile.errorImage == null);
  }

  _Fallbacks _fallbacksIn(DiscreteTileRange range) {
    final ready = <int, Set<TileCoordinates>>{};
    for (final coordinates in _positionCoordinates) {
      final dz = coordinates.z - range.zoom;
      if (dz != 0 &&
          dz >= -_maxAncestorLevels &&
          dz <= _maxChildLevels &&
          _covers(coordinates)) {
        ready.putIfAbsent(coordinates.z, () => {}).add(coordinates);
      }
    }
    return _Fallbacks(
      range,
      _scaleAt,
      (_targetBounds?.validCoordinatesIn(range) ?? range.coordinates).where(
        (coordinates) =>
            !_covers(coordinates) &&
            (_positionCoordinates.contains(coordinates) ||
                _visibleRange.contains(
                  coordinates,
                  replicatesWorldLongitude: _resolver.replicatesWorldLongitude,
                )),
      ),
      ready,
    );
  }
}

/// Fallback zoom levels (as the former `_retainAncestor`/`_retainChildren`):
/// tiles of farther zoom levels are neither rendered nor kept.
const _maxAncestorLevels = 5;
const _maxChildLevels = 2;

/// The holes of a [DiscreteTileRange] (tiles which do not cover yet), each
/// with at most ONE fallback zoom level: the closest level (the finer one on
/// a tie) whose ready tiles cover all of the hole; else the closest level
/// whose ready tiles cover part of it. A tile of another zoom level only
/// paints (and is only kept for) the holes of its own level: pinching across
/// many levels keeps one of them per hole, and two levels are never painted
/// on top of each other.
final class _Fallbacks {
  final DiscreteTileRange _range;
  final double Function(int zoom) _scaleAt;
  final int _width;
  final Map<int, Set<TileCoordinates>> _ready;

  /// Per cell of the range: [_notHole], [_orphan] (a hole without fallback
  /// yet), or its fallback zoom level.
  final Int32List _owner;

  static const _notHole = -1;
  static const _orphan = -2;

  /// Clip of a tile which is the fallback of no hole: neither rendered nor
  /// kept.
  static const none = <Rect>[];

  _Fallbacks(
    this._range,
    this._scaleAt,
    Iterable<TileCoordinates> holes,
    this._ready,
  )   : _width = _range.max.x - _range.min.x + 1,
        _owner = Int32List(
          (_range.max.x - _range.min.x + 1) * (_range.max.y - _range.min.y + 1),
        ) {
    _owner.fillRange(0, _owner.length, _notHole);
    for (final c in holes) {
      _owner[(c.y - _range.min.y) * _width + c.x - _range.min.x] = _orphan;
    }
    final z0 = _range.zoom;
    final levels = _ready.keys.toList()
      ..sort((a, b) {
        final byDistance = (a - z0).abs().compareTo((b - z0).abs());
        return byDistance != 0 ? byDistance : b.compareTo(a);
      });
    // Holes covered whole by a level first, then partial fallbacks.
    for (final whole in const [true, false]) {
      for (final z in levels) {
        final tiles = _ready[z]!;
        final ratio = _scaleAt(z) / _scaleAt(z0);
        for (int i = 0; i < _owner.length; i++) {
          if (_owner[i] != _orphan) continue;
          final x = i % _width + _range.min.x;
          final y = i ~/ _width + _range.min.y;
          int covered = 0;
          int cells = 0;
          for (int ty = _first(y, ratio); ty <= _last(y, ratio); ty++) {
            for (int tx = _first(x, ratio); tx <= _last(x, ratio); tx++) {
              cells++;
              if (tiles.contains(TileCoordinates(tx, ty, z))) covered++;
            }
          }
          if (whole ? covered == cells : covered > 0) _owner[i] = z;
        }
      }
    }
  }

  // The tiles of a zoom level under tile [i] of a zoom level [ratio] times
  // coarser (same projection as `Tile.build`).
  static int _first(int i, double ratio) => (i * ratio + 1e-6).floor();
  static int _last(int i, double ratio) => ((i + 1) * ratio - 1e-6).ceil() - 1;

  /// The holes [coordinates] is the fallback of, as rectangles (one per run
  /// of a row) in the unit square of that tile: `null` when it is the
  /// fallback of all of its footprint within the range, [none] when it is
  /// the fallback of no hole.
  List<Rect>? clip(TileCoordinates coordinates) {
    if (!(_ready[coordinates.z]?.contains(coordinates) ?? false)) return none;
    final ratio = _scaleAt(_range.zoom) / _scaleAt(coordinates.z);
    final x0 = math.max(_first(coordinates.x, ratio), _range.min.x);
    final x1 = math.min(_last(coordinates.x, ratio), _range.max.x);
    final y0 = math.max(_first(coordinates.y, ratio), _range.min.y);
    final y1 = math.min(_last(coordinates.y, ratio), _range.max.y);
    bool owns(int x, int y) =>
        _owner[(y - _range.min.y) * _width + x - _range.min.x] == coordinates.z;
    // Cell i of the range spans [i / ratio, (i + 1) / ratio] in tile units.
    double at(int i, int tile) => (i / ratio - tile).clamp(0, 1).toDouble();
    final rects = <Rect>[];
    var all = true;
    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        if (!owns(x, y)) {
          all = false;
          continue;
        }
        final start = x;
        while (x < x1 && owns(x + 1, y)) {
          x++;
        }
        rects.add(Rect.fromLTRB(
          at(start, coordinates.x),
          at(y, coordinates.y),
          at(x + 1, coordinates.x),
          at(y + 1, coordinates.y),
        ));
      }
    }
    if (rects.isEmpty) return none;
    return all ? null : rects;
  }
}
