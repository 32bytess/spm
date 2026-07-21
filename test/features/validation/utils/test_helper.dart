import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/core/injection/cli_service_locator.dart';
import 'package:spm/features/validation/domain/entities/validation_report.dart';

/// Absolute path of a file inside a validation fixture directory.
String validationFixturePath(String dirName, String fileName) => p.join(
  Directory.current.path,
  'test',
  'fixtures',
  'validation',
  dirName,
  fileName,
);

/// Validates the `base.dart` ↔ `mutation.dart` pair of one fixture
/// directory through the full DI pipeline and returns the report.
Future<ValidationReport> validateFixture(
  String dirName, {
  String? directive,
}) async {
  final basePath = validationFixturePath(dirName, 'base.dart');
  final mutationPath = validationFixturePath(dirName, 'mutation.dart');
  if (!File(basePath).existsSync() || !File(mutationPath).existsSync()) {
    throw Exception('Fixture pair not found in: $dirName');
  }

  final result = await ValidationDI.validatePairUseCase.call(
    basePath: basePath,
    mutationPath: mutationPath,
    directive: directive,
  );

  return result.fold(
    (failure) => throw Exception('Validation failed: ${failure.message}'),
    (report) => report,
  );
}
