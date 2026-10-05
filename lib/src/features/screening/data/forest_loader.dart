import 'dart:convert';
import 'dart:io';

import 'package:spm/src/features/screening/data/model/forest_data.g.dart';
import 'package:spm/src/features/screening/domain/forest_model.dart';

/// Decodes the embedded forest once per process.
class ForestLoader {
  ForestLoader._();

  static ForestModel? _cached;

  static ForestModel load() => _cached ??= ForestModel.fromJson(
    jsonDecode(utf8.decode(gzip.decode(base64.decode(forestGzipBase64))))
        as Map<String, dynamic>,
  );
}
