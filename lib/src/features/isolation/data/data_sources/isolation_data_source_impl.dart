import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/extractors/transplant_extractor.dart';
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source.dart';
import 'package:spm/src/features/isolation/data/data_sources/verifier/output_verifier.dart';
import 'package:spm/src/features/isolation/data/data_sources/visitors/rebuild_scope_visitor.dart';
import 'package:spm/src/features/isolation/domain/entities/isolation_event.dart';
import 'package:spm/src/core/loggor/logger.dart';

/// Implementation of [IsolationDataSource] using the `analyzer` package.
class IsolationDataSourceImpl implements IsolationDataSource {
  final TransplantExtractor _extractor;
  final OutputVerifier _verifier;

  IsolationDataSourceImpl({
    TransplantExtractor? extractor,
    OutputVerifier? verifier,
  }) : _extractor = extractor ?? TransplantExtractor(),
       _verifier = verifier ?? OutputVerifier();

  /// Projects whose dependencies could not be resolved, so every third-party
  /// name in them is unresolved and every row produced from them is suspect.
  final Set<String> _degradedProjects = {};

  /// Formats every isolated file so the output is diffable.
  ///
  /// The transplant assembles source by concatenating skeletonised fragments,
  /// which preserves each fragment's original indentation and leaves the result
  /// unevenly laid out. Running the SDK formatter over the output directory
  /// normalises that, so two isolate runs differ only where the code differs.
  ///
  /// Best-effort: a scope that failed to produce parseable Dart should still be
  /// written out for inspection, so a formatter failure is not propagated.
  Future<void> _formatOutput(String outputDir) async {
    try {
      await Process.run('dart', ['format', outputDir]);
    } catch (_) {
      // Formatting is cosmetic; never fail an extraction over it.
    }
  }

  /// Ensures `.dart_tool/package_config.json` exists for [dir].
  ///
  /// First tries `dart pub get` / `flutter pub get`. If both fail (e.g. SDK
  /// version mismatch), synthesises a minimal config that at least maps the
  /// project's own package URI so the analyzer can resolve intra-project
  /// cross-file type references.
  Future<void> _ensurePackageConfig(String dir) async {
    final configFile = File(p.join(dir, '.dart_tool', 'package_config.json'));
    if (configFile.existsSync()) return;
    if (!File(p.join(dir, 'pubspec.yaml')).existsSync()) return;

    for (final cmd in [
      ['dart', 'pub', 'get'],
      ['flutter', 'pub', 'get'],
    ]) {
      try {
        final result = await Process.run(
          cmd.first,
          cmd.sublist(1),
          workingDirectory: dir,
        );
        if (result.exitCode == 0) return;
      } catch (_) {}
    }

    // Nothing below this line resolves a third-party package. The synthesised
    // config maps the project's own `package:` URI and no other, so every
    // reference into a dependency has a null element from here on: no import,
    // no stand-in from the element model, and only what the syntactic
    // reconstruction can recover. A run in this state is reportable, not
    // merely slower, so it is recorded rather than logged and forgotten.
    _degradedProjects.add(dir);
    SpmLogger.logMessage(
      'Could not resolve dependencies for $dir. Every third-party reference '
      'in it is unresolved, so its isolated files are reconstructed from '
      'syntax alone.',
      isError: true,
    );

    // Fallback: synthesise a minimal package_config.json so that the package's
    // own `package:<name>/...` imports resolve to its `lib/` directory. This
    // lets the analyzer trace intra-project type references even when pub
    // cannot run (e.g. SDK version mismatch).
    try {
      final pubspec = File(p.join(dir, 'pubspec.yaml')).readAsStringSync();
      final nameMatch = RegExp(
        r'^name:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec);
      if (nameMatch == null) return;
      final packageName = nameMatch.group(1)!;

      configFile.parent.createSync(recursive: true);
      configFile.writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': packageName,
              'rootUri': '../',
              'packageUri': 'lib/',
              'languageVersion': '3.0',
            },
          ],
          'generated': DateTime.now().toIso8601String(),
          'generator': 'spm',
          'generatorVersion': '0.0.1',
        }),
      );
    } catch (_) {}
  }

  @override
  Stream<IsolationEvent> isolate({
    required List<String> directories,
    required String outputDir,
    String? jsonlPath,
  }) async* {
    // Ensure package resolution is available so cross-file types can be resolved
    for (final dir in directories) {
      await _ensurePackageConfig(dir);
    }

    // Collect all analysis contexts for the provided directories
    final collection = AnalysisContextCollection(
      includedPaths: directories,
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );

    int isolatedCount = 0;
    final mapping = <Map<String, dynamic>>[];

    for (final dir in directories) {
      for (final context in collection.contexts) {
        // Only process files within the specific directory
        if (!p.isWithin(dir, context.contextRoot.root.path) &&
            context.contextRoot.root.path != dir) {
          continue;
        }

        for (final filePath in context.contextRoot.analyzedFiles()) {
          if (!filePath.endsWith('.dart')) continue;

          final result = await context.currentSession.getResolvedUnit(filePath);
          if (result is! ResolvedUnitResult) continue;

          // Find all rebuild scopes in the current file
          final visitor = RebuildScopeVisitor(result);
          result.unit.accept(visitor);

          for (final match in visitor.matches) {
            // Extract and transplant each discovered scope
            final isolatedCode = await _extractor.extract(
              match,
              result,
              context.currentSession,
            );

            final safeName = match.name.replaceAll(
              RegExp(r'[^a-zA-Z0-9]'),
              '_',
            );
            final fileName =
                '${p.basenameWithoutExtension(filePath)}_${match.type}_${safeName}_$isolatedCount.dart';
            final targetDir = p.join(outputDir, match.type);

            // Ensure the target subdirectory (e.g., 'State', 'BlocBuilder') exists
            Directory(targetDir).createSync(recursive: true);

            final targetPath = p.join(targetDir, fileName);
            File(targetPath).writeAsStringSync(isolatedCode);

            final event = IsolationDataEvent(
              originalPath: filePath,
              isolatedPath: targetPath,
              type: match.type,
              name: match.name,
            );

            yield event;

            // Record the mapping for output
            mapping.add({
              'originalPath': filePath,
              'nodeType': match.type,
              'isolatedPath': targetPath,
              'name': match.name,
              if (_degradedProjects.any(
                (project) => p.isWithin(project, filePath),
              ))
                'sourceDependenciesResolved': false,
            });
            isolatedCount++;
          }
        }
      }
    }

    // Formatting first: the verifier reads the files back, and its unused
    // import pruning is line-based, which assumes the formatter has already
    // put one directive on each line.
    await _formatOutput(outputDir);

    final verifications = await _verifier.verify(
      outputDir: outputDir,
      sourceDirectories: directories,
    );

    var verifiedCount = 0;
    var cleanCount = 0;
    var errorCount = 0;
    for (final verification in verifications.values) {
      if (!verification.wasVerified) continue;
      verifiedCount++;
      errorCount += verification.errorCount;
      if (verification.isClean) cleanCount++;
    }

    // Save the mapping to a JSONL file if requested
    if (jsonlPath != null) {
      for (final row in mapping) {
        final verification = verifications[row['isolatedPath']];
        if (verification != null) row.addAll(verification.toJson());
      }
      File(
        jsonlPath,
      ).writeAsStringSync(mapping.map((m) => jsonEncode(m)).join('\n'));
    }

    yield IsolationSummaryEvent(
      isolatedCount: isolatedCount,
      outputDir: outputDir,
      verifiedCount: verifiedCount,
      cleanCount: cleanCount,
      errorCount: errorCount,
    );
  }
}
