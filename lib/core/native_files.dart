import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Share a file with other apps and pick a file, through the app's own
/// Android code (MainActivity, channel "gamex/files") — no extra plugins.
class NativeFiles {
  static const _ch = MethodChannel('gamex/files');

  /// Opens the Android share sheet (Drive, WhatsApp, email…) for [file].
  static Future<void> share(File file, {String mime = 'application/zip', String? subject, String? text}) async {
    // the share provider serves files from the cache folder
    final tmp = await getTemporaryDirectory();
    final copy = await file.copy(p.join(tmp.path, p.basename(file.path)));
    await _ch.invokeMethod('share', {
      'path': copy.path,
      'mime': mime,
      'subject': subject,
      'text': text,
      'title': 'Share backup',
    });
  }

  /// Lets the user choose a file; returns a readable copy, or null if cancelled.
  static Future<File?> pick() async {
    final path = await _ch.invokeMethod<String>('pick');
    return path == null ? null : File(path);
  }
}
