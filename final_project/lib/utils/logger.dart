import 'package:flutter/foundation.dart';

/// לוגר מרוכז עבור כל שירותי האפליקציה.
class AppLogger {
  final String tag;

  const AppLogger(this.tag);

  /// מדפיס הודעה במצב פיתוח בלבד.
  void debug(String msg, [Object? error, StackTrace? stackTrace]) {
    if (!kDebugMode) return;

    final time = DateTime.now()
        .toIso8601String()
        .split('T')
        .last
        .split('.')
        .first;

    debugPrint('[$tag][$time] $msg');
    if (error != null) debugPrint('[$tag][$time][ERROR] $error');
    if (stackTrace != null) debugPrint('[$tag][$time][STACK] $stackTrace');
  }
}
