import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/core/errors/exceptions.dart';
import 'package:spm/src/features/isolation/data/data_sources/extractors/transplant_extractor.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/package_config.dart';
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source.dart';
import 'package:spm/src/features/isolation/data/data_sources/sets/isolation_match_set.dart';
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
  ///
  /// Cleared at the start of every [isolate] call. This class is a lazy
  /// singleton in [IsolationDI], so without that a verdict reached on one run
  /// would still be here on the next, flagging rows from a project that
  /// resolved perfectly well.
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
  Future<void> _formatOutput(String outputDir) => _format([outputDir]);

  Future<void> _format(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await Process.run('dart', ['format', ...paths]);
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
  ///
  /// Every path out of here either resolves the project or records it in
  /// [_degradedProjects]. That was not true before, and each of the three ways
  /// out failed in the same direction, towards "resolved": a run that resolved
  /// nothing reported nothing, and `sourceDependenciesResolved` stayed absent on
  /// rows it should have been false on.
  Future<void> _ensurePackageConfig(String dir) async {
    final configFile = File(p.join(dir, '.dart_tool', 'package_config.json'));
    if (configFile.existsSync()) {
      // Existence is not resolution. The config this method writes below when
      // pub fails satisfies this check, so a second run over the same checkout
      // used to sail past it: the flag fired once, on the run that created the
      // file, and never again. In a history walk, where a worktree keeps its
      // `.dart_tool` across checkouts, that is every revision after the first.
      if (isSynthesisedConfig(configFile)) _degradedProjects.add(dir);
      return;
    }
    if (!File(p.join(dir, 'pubspec.yaml')).existsSync()) {
      // No pubspec here to run pub against. That is fine when a real config sits
      // above (a subdirectory of a package, which the analyzer resolves by
      // walking up), and it means nothing resolved when there is not one.
      if (packageConfigAbove(dir) == null) _degradedProjects.add(dir);
      return;
    }

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

  /// Re-extracts every scope that carried third-party source and still does not
  /// analyse, then keeps whichever of the two versions has fewer errors.
  ///
  /// Carrying a third-party widget's tree is the better answer when it works,
  /// and it does not always work. A package's own generics are the recurring
  /// reason: inlining `provider` brings across
  /// `ChangeNotifierProvider<T extends ChangeNotifier?>` with its real bound,
  /// and the repo-local `AuthProvider` that satisfies it in the original app is
  /// a stand-in here with no supertype at all, so a file that used to type-check
  /// against a stand-in's `dynamic` now does not. Merged imports are the other:
  /// two package files that each imported one of `dart:developer` and
  /// `dart:math` are fine apart and ambiguous about `log` together.
  ///
  /// Neither is worth guessing at from the source. Analysing both answers and
  /// keeping the better one makes the guarantee exact: no scope ends up with
  /// more errors than standing everything in would have given it, which matters
  /// because `spm analyze` skips any file carrying one.
  Future<Map<String, OutputVerification>> _revertUnprofitableInlining({
    required List<
      ({
        IsolationMatch match,
        ResolvedUnitResult result,
        AnalysisSession session,
        String targetPath,
        int row,
      })
    >
    rewritable,
    required Map<String, OutputVerification> verifications,
    required List<Map<String, dynamic>> mapping,
    required String outputDir,
    required List<String> directories,
  }) async {
    final candidates = rewritable.where((scope) {
      final verification = verifications[scope.targetPath];
      return verification != null &&
          verification.wasVerified &&
          !verification.isClean;
    }).toList();
    if (candidates.isEmpty) return verifications;

    // The inlined source, read back off disk rather than held from the first
    // pass: it is already written, and a scope that turns out to be better
    // inlined has to be restorable byte for byte.
    final inlined = <String, String>{};
    final rewritten = <String>[];
    for (final scope in candidates) {
      try {
        final fallback = await _extractor.extract(
          scope.match,
          scope.result,
          scope.session,
          inlineThirdParty: false,
        );
        inlined[scope.targetPath] = File(scope.targetPath).readAsStringSync();
        File(scope.targetPath).writeAsStringSync(fallback.source);
        rewritten.add(scope.targetPath);
      } catch (_) {
        // A scope that will not re-extract keeps the version it has. The
        // inlined file is already written and already verified.
      }
    }
    if (rewritten.isEmpty) return verifications;

    await _format(rewritten);
    final second = await _verifier.verify(
      outputDir: outputDir,
      sourceDirectories: directories,
      only: rewritten,
    );

    final merged = Map<String, OutputVerification>.from(verifications);
    for (final scope in candidates) {
      final before = verifications[scope.targetPath];
      final after = second[scope.targetPath];
      if (before == null || after == null) continue;
      final keepFallback =
          after.wasVerified && after.errorCount < before.errorCount;
      if (!keepFallback) {
        final source = inlined[scope.targetPath];
        if (source != null) File(scope.targetPath).writeAsStringSync(source);
        continue;
      }
      merged[scope.targetPath] = after;
      final row = mapping[scope.row];
      row.remove('inlinedThirdPartyDeclarations');
      row.remove('thirdPartyInlineTruncated');
      // Said out loud, because this row measures a smaller tree than the same
      // scope does in place, and the count alone would not show it.
      row['thirdPartyInlineReverted'] = true;
    }
    return merged;
  }

  @override
  Stream<IsolationEvent> isolate({
    required List<String> directories,
    required String outputDir,
    String? jsonlPath,
    bool inlineThirdParty = true,
  }) async* {
    _degradedProjects.clear();

    // A path that does not exist does not produce an empty run, it produces a
    // context rooted at the nearest real package above it, whose files are then
    // all filtered out. The run reports success over zero scopes, which reads
    // exactly like a project with no rebuild scopes in it. `analyze` has always
    // rejected this; so does `isolate` now.
    final missing = directories.where((dir) => !Directory(dir).existsSync());
    if (missing.isNotEmpty) {
      throw IsolationException(
        'Isolation directories do not exist: ${missing.join(', ')}',
        StackTrace.current.toString(),
      );
    }

    // Ensure package resolution is available so cross-file types can be resolved
    for (final dir in directories) {
      await _ensurePackageConfig(dir);
    }

    // Collect all analysis contexts for the provided directories
    final collection = AnalysisContextCollection(
      includedPaths: directories,
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );

    if (collection.contexts.isEmpty) {
      throw IsolationException(
        'No analysis contexts found in: ${directories.join(', ')}',
        StackTrace.current.toString(),
      );
    }

    int isolatedCount = 0;
    final mapping = <Map<String, dynamic>>[];

    // The scopes that carried third-party source, so they can be re-extracted
    // without it if that turns out to analyse better. `row` indexes [mapping],
    // since the row is what has to be corrected alongside the file.
    final rewritable =
        <
          ({
            IsolationMatch match,
            ResolvedUnitResult result,
            AnalysisSession session,
            String targetPath,
            int row,
          })
        >[];

    // One pass over the contexts, not one per input directory. The analyzer
    // already roots each context at an included path and merges overlapping
    // ones, so the per-directory filter this replaces never admitted a context
    // twice for distinct inputs. It did for a repeated one: passing the same
    // directory twice isolated every scope in it twice.
    for (final context in collection.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        if (!filePath.endsWith('.dart')) continue;

        final result = await context.currentSession.getResolvedUnit(filePath);
        if (result is! ResolvedUnitResult) continue;

        // Find all rebuild scopes in the current file
        final visitor = RebuildScopeVisitor(result);
        result.unit.accept(visitor);

        for (final match in visitor.matches) {
          // Extract and transplant each discovered scope
          final transplant = await _extractor.extract(
            match,
            result,
            context.currentSession,
            inlineThirdParty: inlineThirdParty,
          );

          final safeName = match.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          final fileName =
              '${p.basenameWithoutExtension(filePath)}_${match.type}_${safeName}_$isolatedCount.dart';
          final targetDir = p.join(outputDir, match.type);

          // Ensure the target subdirectory (e.g., 'State', 'BlocBuilder') exists
          Directory(targetDir).createSync(recursive: true);

          final targetPath = p.join(targetDir, fileName);
          File(targetPath).writeAsStringSync(transplant.source);

          if (transplant.inlinedThirdPartyDeclarations > 0) {
            rewritable.add((
              match: match,
              result: result,
              session: context.currentSession,
              targetPath: targetPath,
              row: mapping.length,
            ));
          }

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
            if (transplant.inlinedThirdPartyDeclarations > 0)
              'inlinedThirdPartyDeclarations':
                  transplant.inlinedThirdPartyDeclarations,
            // Only when it happened. A row without the field carried whatever
            // third-party UI it reached; a row with it measures a smaller tree
            // than the same scope would in place, and that is not something a
            // reader should have to infer from a count.
            if (transplant.truncated) 'thirdPartyInlineTruncated': true,
          });
          isolatedCount++;
        }
      }
    }

    // Formatting first, so the diagnostics the verifier reports carry offsets
    // into the file that is actually on disk. The verifier reads the files back
    // and never writes to them.
    await _formatOutput(outputDir);

    var verifications = await _verifier.verify(
      outputDir: outputDir,
      sourceDirectories: directories,
    );

    verifications = await _revertUnprofitableInlining(
      rewritable: rewritable,
      verifications: verifications,
      mapping: mapping,
      outputDir: outputDir,
      directories: directories,
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
      // One line each, every line terminated, as `analyze` writes its JSONL with
      // `writeln`. A reader that splits on the newline sees the same rows either
      // way, but one that reads line by line does not, and neither does a shell
      // that concatenates two of these files.
      File(
        jsonlPath,
      ).writeAsStringSync(mapping.map((m) => '${jsonEncode(m)}\n').join());
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
