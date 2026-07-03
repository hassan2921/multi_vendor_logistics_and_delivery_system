import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/models/location_ping.dart';

/// Streams throttled GPS updates for an active delivery and batches them
/// into infrequent Supabase writes instead of one write per raw GPS fix.
///
/// Two layers of throttling bound write volume:
///  1. Device-level: `distanceFilter` tells the OS to only emit a new
///     position once the courier has moved at least [distanceFilterMeters].
///  2. App-level: positions are buffered and flushed as a single batched
///     insert every [flushInterval] OR once [maxBufferSize] points have
///     accumulated, whichever happens first. That bounds writes to at most
///     one insert per [flushInterval] per active courier, regardless of how
///     chatty the device's GPS is.
class LocationThrottleService {
  LocationThrottleService({
    required this.deliveryId,
    required this.courierId,
    required this.onBatchReady,
    this.distanceFilterMeters = 50,
    this.flushInterval = const Duration(seconds: 10),
    this.maxBufferSize = 5,
    Stream<Position>? positionStreamOverride,
  }) : _positionStreamOverride = positionStreamOverride;

  final String deliveryId;
  final String courierId;
  final Future<void> Function(List<LocationPing> batch) onBatchReady;
  final int distanceFilterMeters;
  final Duration flushInterval;
  final int maxBufferSize;
  final Stream<Position>? _positionStreamOverride;

  final List<LocationPing> _buffer = [];
  StreamSubscription<Position>? _positionSub;
  Timer? _flushTimer;

  Future<void> start() async {
    final stream = _positionStreamOverride ??
        Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: distanceFilterMeters,
          ),
        );

    _positionSub = stream.listen(_onPosition);
    _flushTimer = Timer.periodic(flushInterval, (_) => flush());
  }

  void _onPosition(Position position) {
    _buffer.add(
      LocationPing(
        deliveryId: deliveryId,
        courierId: courierId,
        lat: position.latitude,
        lng: position.longitude,
        recordedAt: position.timestamp,
      ),
    );

    if (_buffer.length >= maxBufferSize) {
      flush();
    }
  }

  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    final batch = List<LocationPing>.of(_buffer);
    _buffer.clear();
    await onBatchReady(batch);
  }

  /// Call from a WidgetsBindingObserver on pause/detach so buffered points
  /// aren't lost when the app is backgrounded mid-buffer.
  void handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      flush();
    }
  }

  Future<void> stop() async {
    await flush();
    await _positionSub?.cancel();
    _flushTimer?.cancel();
  }
}
