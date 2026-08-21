import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart' show Severity;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/core/errors/exceptions.dart';
import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/analysis/data/models/analysis_result_model.dart';
import 'package:spm/src/features/analysis/domain/entities/analysis_event.dart';

import 'analysis_data_source.dart';
import 'extractors/tree_extractor.dart';
import 'sets/rebuild_scope_instance_set.dart';
import 'sets/tree_features_set.dart';
import 'visitors/rebuild_scope_analysis_visitor.dart';

class AnalysisDataSourceImpl implements AnalysisDataSource {
  @override
  Stream<AnalysisEvent> analyzeDirs(
    List<String> repoDirs, {
    Set<String>? scopeTypes,
  }) async* {
    int filesScanned = 0;
    int filesSkipped = 0;
    int scopesFound = 0;
    int keptRows = 0;
    final scopesByType = <String, int>{};
    final collection = AnalysisContextCollection(
      includedPaths: repoDirs,
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );
    // AST nodes are tied to the collection/session that resolved them. Keep
    // the extractor (and its library cache) local to this run so repeated or
    // concurrent analyses can never reuse stale nodes from another session.
    final treeExtractor = TreeExtractor();
    if (collection.contexts.isEmpty) {
      throw AnalyzerInitializationException(
        'No analysis contexts found in : ${repoDirs.join(', ')}',
      );
    }
    for (final context in collection.contexts) {
      for (final path in context.contextRoot.analyzedFiles()) {
        if (!path.endsWith('.dart')) continue;
        filesScanned++;
        final session = context.currentSession;
        final result = await session.getResolvedUnit(path);
        if (result is! ResolvedUnitResult) continue;

        // A file with compile errors resolves types to null; every widget
        // would silently classify as a value object and the row would be
        // near-zero garbage. Skip it and report it instead.
        if (result.diagnostics.any((d) => d.severity == Severity.error)) {
          filesSkipped++;
          continue;
        }

        final unit = result.unit;
        final visitor = RebuildScopeAnalysisVisitor(
          result,
          rootPath: context.contextRoot.root.path,
        );
        unit.accept(visitor);

        scopesFound += visitor.instances.length;
        for (final scope in visitor.instances) {
          scopesByType.update(
            scope.scopeType,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }

        for (final RebuildScopeInstance scope in visitor.instances) {
          if (scopeTypes != null && !scopeTypes.contains(scope.scopeType)) {
            continue;
          }

          final extraction = await treeExtractor.extract(
            scope,
            collection: collection,
          );
          final TreeFeaturesSet treeFeatures = extraction.features;
          final root = context.contextRoot.root.path;

          keptRows++;
          yield AnalysisDataEvent(
            result: AnalysisResultModel.fromTreeFeatures(
              treeFeatures: treeFeatures,
              scope: scope,
              filePath: p.relative(scope.filePath, from: root),
              dependencyFiles: _withinRoot(
                extraction.closure.dependencyFiles,
                root,
              ),
              unresolvedDependencies: _withinRoot(
                extraction.closure.unresolvedDependencies,
                root,
              ),
            ),
          );
        }
      }
    }
    yield AnalysisSummaryEvent(
      filesScanned: filesScanned,
      filesSkipped: filesSkipped,
      scopesFound: scopesFound,
      scopesByType: scopesByType,
      keptRows: keptRows,
    );
  }

  /// Project files from a closure, relative to the analysis root.
  ///
  /// Everything outside the root is dropped: the closure reaches into the SDK
  /// and the pub cache, and those are neither editable by a commit nor
  /// meaningful as a repo-relative path. Filtering here rather than in the
  /// extractor keeps the root, which the extractor does not know, in the one
  /// place that does.
  List<String> _withinRoot(List<String> paths, String root) {
    final within = <String>[];
    for (final path in paths) {
      if (p.isWithin(root, path)) within.add(p.relative(path, from: root));
    }
    within.sort();
    return within;
  }

  @override
  AsyncVoid saveResults(
    AnalysisDataEventStream analysisResult,
    OutputPath filePath,
  ) async {
    try {
      final file = File(filePath);
      final sink = file.openWrite();

      await for (final event in analysisResult) {
        try {
          final jsonlLine = jsonEncode(
            AnalysisResultModel.fromEntity(event.result).toJson(),
          );
          sink.writeln(jsonlLine);
        } catch (e) {
          throw FileWriteException(
            'Failed to encode analysis result to JSON: $e',
            e.toString(),
          );
        }
      }

      await sink.flush();
      await sink.close();
    } on FileSystemException catch (e) {
      throw FileWriteException(
        'File system error while writing to $filePath: ${e.message}',
        e.toString(),
      );
    } catch (e) {
      throw FileWriteException(
        'Unexpected error while saving results to $filePath: $e',
        e.toString(),
      );
    }
  }
}
