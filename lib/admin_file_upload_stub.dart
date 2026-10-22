import 'dart:typed_data';

class PickedAdminFile {
  final String name;
  final String mimeType;
  final Uint8List bytes;

  const PickedAdminFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });
}

Future<PickedAdminFile?> pickSponsorImageFile() async => null;
