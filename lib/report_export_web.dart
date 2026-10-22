import 'dart:convert';
import 'package:web/web.dart' as web;

Future<bool> exportReportCsv(String filename, String csv) async {
  final anchor = web.HTMLAnchorElement()
    ..href =
        'data:text/csv;charset=utf-8;base64,${base64Encode(utf8.encode(csv))}'
    ..download = filename;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  return true;
}
