import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:maplibre/maplibre.dart' as ml;

import '../config/app_config.dart';
import 'iraq_map_config.dart';
import 'runtime_environment.dart';

typedef JowlaMapTapCallback = void Function(LatLng point);

/// واجهة تحكم صغيرة تعزل بقية التطبيق عن تفاصيل MapLibre.
class JowlaMapController {
  ml.MapController? _delegate;
  Future<void> Function(ml.MapController controller)? _pendingAction;

  void _attach(ml.MapController controller) {
    _delegate = controller;
    final action = _pendingAction;
    _pendingAction = null;
    if (action != null) unawaited(action(controller));
  }

  void _detach(ml.MapController controller) {
    if (identical(_delegate, controller)) _delegate = null;
  }

  void move(LatLng point, double zoom) {
    _run(
      (controller) => controller.animateCamera(
        center: _toGeographic(point),
        zoom: zoom.clamp(IraqMapConfig.minZoom, IraqMapConfig.maxZoom),
        nativeDuration: const Duration(milliseconds: 450),
      ),
    );
  }

  void fitCoordinates(
    Iterable<LatLng> coordinates, {
    EdgeInsets padding = const EdgeInsets.all(48),
    double maxZoom = 16,
  }) {
    final points = coordinates.toList(growable: false);
    if (points.isEmpty) return;
    if (points.length == 1) {
      move(points.single, maxZoom);
      return;
    }
    _run(
      (controller) => controller.fitBounds(
        bounds: ml.LngLatBounds.fromPoints(
          points.map(_toGeographic).toList(growable: false),
        ),
        padding: padding,
        webMaxZoom: maxZoom,
        nativeDuration: const Duration(milliseconds: 550),
      ),
    );
  }

  void _run(Future<void> Function(ml.MapController controller) action) {
    final controller = _delegate;
    if (controller == null) {
      _pendingAction = action;
      return;
    }
    unawaited(action(controller));
  }
}

@immutable
class JowlaMapPolyline {
  const JowlaMapPolyline({
    required this.points,
    required this.color,
    this.width = 5,
  });

  final List<LatLng> points;
  final Color color;
  final int width;
}

@immutable
class JowlaMapPolygon {
  const JowlaMapPolygon({
    required this.points,
    required this.color,
    required this.outlineColor,
  });

  final List<LatLng> points;
  final Color color;
  final Color outlineColor;
}

@immutable
class JowlaMapMarker {
  const JowlaMapMarker({
    required this.point,
    required this.size,
    required this.child,
    this.alignment = Alignment.center,
    this.smoothMovement = false,
  });

  final LatLng point;
  final Size size;
  final Widget child;
  final Alignment alignment;
  final bool smoothMovement;
}

/// الخريطة النهارية المشتركة لتطبيق السائق.
///
/// تبقي غطاءً ناعمًا فوق العرض الأصلي حتى يؤكد MapLibre اكتمال أول إطار
/// وكل البلاطات المطلوبة، لذلك لا تظهر مربعات ناقصة أو بكسلات أثناء الفتح.
class JowlaVectorMap extends StatefulWidget {
  const JowlaVectorMap({
    required this.initialCenter,
    this.initialZoom = 13,
    this.controller,
    this.polygons = const [],
    this.polylines = const [],
    this.markers = const [],
    this.onTap,
    this.onReady,
    super.key,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final JowlaMapController? controller;
  final List<JowlaMapPolygon> polygons;
  final List<JowlaMapPolyline> polylines;
  final List<JowlaMapMarker> markers;
  final JowlaMapTapCallback? onTap;
  final ValueChanged<Duration>? onReady;

  @override
  State<JowlaVectorMap> createState() => _JowlaVectorMapState();
}

class _JowlaVectorMapState extends State<JowlaVectorMap> {
  final _loadWatch = Stopwatch();
  ml.MapController? _nativeController;
  Timer? _loadTimeout;
  var _reloadGeneration = 0;
  var _styleLoaded = false;
  var _ready = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _beginLoadMeasurement();
  }

  @override
  void didUpdateWidget(covariant JowlaVectorMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      final native = _nativeController;
      if (native != null) {
        oldWidget.controller?._detach(native);
        widget.controller?._attach(native);
      }
    }
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    final controller = _nativeController;
    if (controller != null) widget.controller?._detach(controller);
    super.dispose();
  }

  void _beginLoadMeasurement() {
    _loadWatch
      ..reset()
      ..start();
    _loadTimeout?.cancel();
    if (isFlutterTestEnvironment) return;
    _loadTimeout = Timer(const Duration(seconds: 12), () {
      if (!mounted || _ready) return;
      setState(() => _failed = true);
    });
  }

  void _onMapCreated(ml.MapController controller) {
    _nativeController = controller;
    widget.controller?._attach(controller);
  }

  void _onMapEvent(ml.MapEvent event) {
    if (event is ml.MapEventClick) {
      widget.onTap?.call(LatLng(event.point.lat, event.point.lon));
      return;
    }
    if (event is ml.MapEventIdle && _styleLoaded && !_ready) {
      _loadWatch.stop();
      _loadTimeout?.cancel();
      final elapsed = _loadWatch.elapsed;
      if (kDebugMode) {
        final loadMilliseconds = elapsed.inMilliseconds;
        debugPrint(
          'Jowla vector map first complete frame: $loadMilliseconds ms',
        );
      }
      widget.onReady?.call(elapsed);
      if (mounted) setState(() => _ready = true);
    }
  }

  void _retry() {
    final controller = _nativeController;
    if (controller != null) widget.controller?._detach(controller);
    _nativeController = null;
    setState(() {
      _reloadGeneration += 1;
      _styleLoaded = false;
      _ready = false;
      _failed = false;
    });
    _beginLoadMeasurement();
  }

  @override
  Widget build(BuildContext context) {
    if (isFlutterTestEnvironment) {
      return Stack(
        fit: StackFit.expand,
        children: const [_MapLoadingBackdrop(), _MapAttribution()],
      );
    }

    final layers = <ml.Layer>[
      for (final area in widget.polygons)
        if (area.points.length >= 3)
          ml.PolygonLayer(
            polygons: [
              ml.Feature<ml.Polygon>(
                geometry: ml.Polygon.from([
                  area.points.map(_toGeographic).toList(growable: false),
                ]),
              ),
            ],
            color: area.color,
            outlineColor: area.outlineColor,
          ),
      for (final line in widget.polylines)
        if (line.points.length >= 2)
          ml.PolylineLayer(
            polylines: [
              ml.Feature<ml.LineString>(
                geometry: ml.LineString.from(
                  line.points.map(_toGeographic).toList(growable: false),
                ),
              ),
            ],
            color: line.color,
            width: line.width,
          ),
    ];

    final markers = widget.markers
        .map(
          (marker) => ml.Marker(
            point: _toGeographic(marker.point),
            size: marker.size,
            alignment: marker.alignment,
            child: marker.smoothMovement
                ? _SmoothMarkerChild(point: marker.point, child: marker.child)
                : marker.child,
          ),
        )
        .toList(growable: false);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: IraqMapConfig.backgroundColor,
          child: ml.MapLibreMap(
            key: ValueKey('jowla-vector-map-$_reloadGeneration'),
            options: ml.MapOptions(
              initStyle: AppConfig.mapStyleUrl,
              initCenter: _toGeographic(widget.initialCenter),
              initZoom: widget.initialZoom.clamp(
                IraqMapConfig.minZoom,
                IraqMapConfig.maxZoom,
              ),
              minZoom: IraqMapConfig.minZoom,
              maxZoom: IraqMapConfig.maxZoom,
              minPitch: 0,
              maxPitch: 0,
              maxBounds: const ml.LngLatBounds(
                longitudeWest: IraqMapConfig.west,
                longitudeEast: IraqMapConfig.east,
                latitudeSouth: IraqMapConfig.south,
                latitudeNorth: IraqMapConfig.north,
              ),
              gestures: const ml.MapGestures.all(rotate: false, pitch: false),
              androidTextureMode: false,
              androidForegroundLoadColor: IraqMapConfig.backgroundColor,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoaded: (_) => _styleLoaded = true,
            onEvent: _onMapEvent,
            layers: layers,
            children: [
              if (markers.isNotEmpty)
                ml.WidgetLayer(markers: markers, allowInteraction: true),
            ],
          ),
        ),
        const _MapAttribution(),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _ready && !_failed,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              opacity: _ready && !_failed ? 0 : 1,
              child: _failed
                  ? _MapLoadFailure(onRetry: _retry)
                  : const _MapLoadingBackdrop(showProgress: true),
            ),
          ),
        ),
      ],
    );
  }
}

ml.Geographic _toGeographic(LatLng point) =>
    ml.Geographic(lon: point.longitude, lat: point.latitude);

class _SmoothMarkerChild extends StatefulWidget {
  const _SmoothMarkerChild({required this.point, required this.child});

  final LatLng point;
  final Widget child;

  @override
  State<_SmoothMarkerChild> createState() => _SmoothMarkerChildState();
}

class _SmoothMarkerChildState extends State<_SmoothMarkerChild> {
  late LatLng _fromPoint = widget.point;
  var _animationGeneration = 0;

  @override
  void didUpdateWidget(covariant _SmoothMarkerChild oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.point != widget.point) {
      _fromPoint = oldWidget.point;
      _animationGeneration += 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ml.MapController.maybeOf(context);
    if (controller == null || _fromPoint == widget.point) return widget.child;
    final fromOffset = controller.toScreenLocation(_toGeographic(_fromPoint));
    final toOffset = controller.toScreenLocation(_toGeographic(widget.point));
    final delta = fromOffset - toOffset;
    return TweenAnimationBuilder<double>(
      key: ValueKey(_animationGeneration),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Transform.translate(
        offset: Offset.lerp(delta, Offset.zero, value) ?? Offset.zero,
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _MapAttribution extends StatelessWidget {
  const _MapAttribution();

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      end: 6,
      bottom: 5,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            child: Text(
              '© OpenStreetMap • Geofabrik • VersaTiles',
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 9, color: Color(0xFF374151)),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapLoadingBackdrop extends StatelessWidget {
  const _MapLoadingBackdrop({this.showProgress = false});

  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: IraqMapConfig.backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _RoadBackdropPainter()),
          if (showProgress)
            const Center(
              child: SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoadBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = const Color(0xFFE9E1D7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final major = Paint()
      ..color = const Color(0xFFD8CABA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final first = Path()
      ..moveTo(-20, size.height * 0.76)
      ..cubicTo(
        size.width * 0.25,
        size.height * 0.48,
        size.width * 0.55,
        size.height * 0.72,
        size.width + 20,
        size.height * 0.30,
      );
    final second = Path()
      ..moveTo(size.width * 0.18, -20)
      ..cubicTo(
        size.width * 0.30,
        size.height * 0.27,
        size.width * 0.74,
        size.height * 0.46,
        size.width * 0.82,
        size.height + 20,
      );
    final third = Path()
      ..moveTo(-20, size.height * 0.23)
      ..quadraticBezierTo(
        size.width * 0.54,
        size.height * 0.18,
        size.width + 20,
        size.height * 0.60,
      );
    canvas
      ..drawPath(first, major)
      ..drawPath(second, minor)
      ..drawPath(third, minor);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MapLoadFailure extends StatelessWidget {
  const _MapLoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: IraqMapConfig.backgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined, size: 38),
              const SizedBox(height: 10),
              const Text(
                'تعذر تحميل الخريطة',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
