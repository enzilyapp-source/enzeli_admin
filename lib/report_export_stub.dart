import 'package:flutter/services.dart';

Future<bool> exportReportCsv(String filename, String csv) async {
  await Clipboard.setData(ClipboardData(text: csv));
  return false;
}
