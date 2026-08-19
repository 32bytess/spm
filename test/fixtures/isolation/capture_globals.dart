import 'package:flutter/material.dart';

/// A cross-file, app-wide handle. The transplant drops it (it is not a widget),
/// so an isolated scope that reads it has to seed it in `initState`.
class CaptureTheme {
  final Color tint = Colors.blue;
}

late CaptureTheme captureTheme;
