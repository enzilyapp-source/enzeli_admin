// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
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

Future<PickedAdminFile?> pickSponsorImageFile() async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/png,image/jpeg,image/webp'
    ..multiple = false;

  final completer = Completer<PickedAdminFile?>();
  input.onChange.first.then((_) {
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }

    final reader = html.FileReader();
    reader.onError.first.then((_) {
      if (!completer.isCompleted) completer.completeError('تعذر قراءة الصورة');
    });
    reader.onLoadEnd.first.then((_) {
      final result = reader.result;
      Uint8List? bytes;
      if (result is ByteBuffer) {
        bytes = Uint8List.view(result);
      } else if (result is Uint8List) {
        bytes = result;
      }
      if (!completer.isCompleted) {
        if (bytes == null) {
          completer.completeError('تعذر قراءة الصورة');
        } else {
          completer.complete(
            PickedAdminFile(
              name: file.name,
              mimeType: file.type.isEmpty
                  ? 'application/octet-stream'
                  : file.type,
              bytes: bytes,
            ),
          );
        }
      }
    });
    reader.readAsArrayBuffer(file);
  });

  input.click();
  return completer.future.timeout(
    const Duration(minutes: 1),
    onTimeout: () => null,
  );
}
