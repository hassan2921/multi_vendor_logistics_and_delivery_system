import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:multi_vendor_logistics_and_delivery_system/data/models/location_ping.dart';
import 'package:multi_vendor_logistics_and_delivery_system/features/courier/location_service.dart';

Position _fakePosition(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );

void main() {
  group('LocationThrottleService', () {
    test('flushes as a single batch once maxBufferSize is reached, without waiting for the timer', () async {
      final controller = StreamController<Position>();
      final flushedBatches = <List<LocationPing>>[];

      final service = LocationThrottleService(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        maxBufferSize: 3,
        flushInterval: const Duration(minutes: 5), // long enough to not fire during the test
        positionStreamOverride: controller.stream,
        onBatchReady: (batch) async => flushedBatches.add(batch),
      );

      await service.start();

      controller.add(_fakePosition(1, 1));
      controller.add(_fakePosition(2, 2));
      await Future<void>.delayed(Duration.zero);
      expect(flushedBatches, isEmpty, reason: 'should not flush before the buffer is full');

      controller.add(_fakePosition(3, 3));
      await Future<void>.delayed(Duration.zero);

      expect(flushedBatches, hasLength(1));
      expect(flushedBatches.single, hasLength(3));

      await service.stop();
      await controller.close();
    });

    test('flushes on a timer even if the buffer never fills up', () async {
      final controller = StreamController<Position>();
      final flushedBatches = <List<LocationPing>>[];

      final service = LocationThrottleService(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        maxBufferSize: 100,
        flushInterval: const Duration(milliseconds: 20),
        positionStreamOverride: controller.stream,
        onBatchReady: (batch) async => flushedBatches.add(batch),
      );

      await service.start();
      controller.add(_fakePosition(1, 1));

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(flushedBatches, isNotEmpty);
      expect(flushedBatches.first, hasLength(1));

      await service.stop();
      await controller.close();
    });

    test('flush() with an empty buffer is a no-op', () async {
      var callCount = 0;
      final service = LocationThrottleService(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        positionStreamOverride: const Stream.empty(),
        onBatchReady: (batch) async => callCount++,
      );

      await service.start();
      await service.flush();

      expect(callCount, 0);
      await service.stop();
    });
  });
}
