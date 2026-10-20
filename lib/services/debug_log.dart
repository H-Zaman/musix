import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Tiny append-only diagnostic log in the app's Documents folder
/// (`musix-debug.log`). Release builds don't expose `print` output, and the
/// folder is visible through the Files app / `devicectl device copy from`,
/// so this is how on-device download problems get diagnosed.
class DebugLog {
  static const _fileName = 'musix-debug.log';
  static const _maxBytes = 200 * 1024;

  static Future<void> add(String message) async {
    debugPrint('[musix] $message');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      // Start over once it grows large; recent lines are the useful ones.
      final mode = await file.exists() && await file.length() > _maxBytes
          ? FileMode.write
          : FileMode.append;
      await file.writeAsString(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: mode,
        flush: true,
      );
    } catch (_) {
      // Deliberately broad: logging must never break a download, and plugin
      // failures before the binding exists surface as Errors, not Exceptions.
    }
  }
}
