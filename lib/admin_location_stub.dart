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

Future<AdminLocation?> readBrowserLocation() async => null;
