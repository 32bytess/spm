import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart' show Severity;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:spm/core/errors/exceptions.dart';
import 'package:spm/core/types.dart';
import 'package:spm/features/analysis/data/models/analysis_result_model.dart';
import 'package:spm/features/analysis/domain/entities/analysis_event.dart';

import 'analysis_data_source.dart';
import 'extractors/tree_extractor.dart';
import 'sets/state_class_instance_set.dart';
import 'sets/tree_features_set.dart';
import 'visitors/state_class_visitor.dart';

class AnalysisDataSourceImpl implements AnalysisDataSource {
  @override
  Stream<AnalysisEvent> analyzeDirs(List<String> repoDirs) async* {
    int filesScanned = 0;
    int filesSkipped = 0;
    int stateClassesFound = 0;
    int keptRows = 0;
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
        final visitor = StateClassVisitor(
          result,
          rootPath: context.contextRoot.root.path,
        );
        unit.accept(visitor);

        stateClassesFound += visitor.instances.length;

        for (final StateClassInstance state in visitor.instances) {
          final TreeFeaturesSet treeFeatures = await treeExtractor.extract(
            state,
            collection: collection,
          );

          keptRows++;
          yield AnalysisDataEvent(
            result: AnalysisResultModel.fromTreeFeatures(
              treeFeatures: treeFeatures,
              state: state,
              filePath: p.relative(
                state.filePath,
                from: context.contextRoot.root.path,
              ),
            ),
          );
        }
      }
    }
    yield AnalysisSummaryEvent(
      filesScanned: filesScanned,
      filesSkipped: filesSkipped,
      stateClassesFound: stateClassesFound,
      keptRows: keptRows,
    );
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
