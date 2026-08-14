import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class AdminLocation {
  final double latitude;
  final double longitude;
  final double? accuracy;

  const AdminLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });
}

Future<AdminLocation?> readBrowserLocation() async {
  final completer = Completer<AdminLocation?>();
  final geolocation = web.window.navigator.geolocation;

  try {
    geolocation.getCurrentPosition(
      ((web.GeolocationPosition position) {
        if (completer.isCompleted) return;
        final coords = position.coords;
        completer.complete(
          AdminLocation(
            latitude: coords.latitude,
            longitude: coords.longitude,
            accuracy: coords.accuracy,
          ),
        );
      }).toJS,
      ((web.GeolocationPositionError _) {
        if (!completer.isCompleted) completer.complete(null);
      }).toJS,
      web.PositionOptions(enableHighAccuracy: true, timeout: 15000),
    );
  } catch (_) {
    return null;
  }

  return completer.future;
}
