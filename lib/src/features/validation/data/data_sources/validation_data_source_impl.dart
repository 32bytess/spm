import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart' as diag;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:spm/src/core/errors/exceptions.dart';
import 'package:spm/src/core/constants/app_constants.dart';
import 'package:spm/src/features/analysis/data/data_sources/sets/rebuild_scope_instance_set.dart';
import 'package:spm/src/features/analysis/data/data_sources/visitors/rebuild_scope_analysis_visitor.dart';
import 'package:spm/src/features/validation/domain/entities/validation_report.dart';

import 'comparators/content_comparator.dart';
import 'comparators/forbidden_comparator.dart';
import 'comparators/frozen_member_comparator.dart';
import 'comparators/import_comparator.dart';
import 'validation_data_source.dart';

class ValidationDataSourceImpl implements ValidationDataSource {
  final _importComparator = ImportComparator();
  final _frozenMemberComparator = FrozenMemberComparator();
  final _contentComparator = ContentComparator();
  final _forbiddenComparator = ForbiddenComparator();

  @override
  Future<ValidationReport> validatePair({
    required String basePath,
    required String mutationPath,
    String? depsPath,
    String? directive,
  }) async {
    // One collection for all files so the mutation resolves against the
    // real, unmodified dependencies.dart and the compile check is free.
    final collection = AnalysisContextCollection(
      includedPaths: [basePath, mutationPath, ?depsPath],
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );

    final baseResult = await collection
        .contextFor(basePath)
        .currentSession
        .getResolvedUnit(basePath);
    final mutationResult = await collection
        .contextFor(mutationPath)
        .currentSession
        .getResolvedUnit(mutationPath);

    if (baseResult is! ResolvedUnitResult) {
      throw ValidationException('Could not resolve base file: $basePath');
    }
    if (mutationResult is! ResolvedUnitResult) {
      return ValidationReport(
        basePath: basePath,
        mutationPath: mutationPath,
        violations: const [
          Violation(
            ViolationCode.doesNotCompile,
            Severity.hard,
            'mutation could not be resolved as a Dart compilation unit',
          ),
        ],
      );
    }

    final baseStates = _stateScopesOf(baseResult);
    final mutationStates = _stateScopesOf(mutationResult);

    if (baseStates.isEmpty) {
      throw ValidationException('No State subclass found in base: $basePath');
    }
    final baseState = baseStates.first;
    final mutationState = mutationStates.firstOrNull;

    final violations = <Violation>[
      ..._importComparator.compare(baseResult, mutationResult),
      if (mutationState != null)
        ..._frozenMemberComparator.compare(
          baseState.declaringClass!,
          mutationState.declaringClass!,
        )
      else
        const Violation(
          ViolationCode.seedsChanged,
          Severity.hard,
          'no State subclass found in mutation; '
          'frozen members cannot be verified',
        ),
      ..._contentComparator.compare(baseResult.unit, mutationResult.unit),
      ..._compileViolations(mutationResult),
      ..._forbiddenComparator.compare(mutationResult.unit),
      ..._noOpViolation(baseResult, mutationResult),
    ];

    return ValidationReport(
      basePath: basePath,
      mutationPath: mutationPath,
      violations: violations,
      baseInstanceId: baseState.instanceId,
      mutationInstanceId: mutationState?.instanceId,
    );
  }

  /// The `State` subclasses of a unit. Validation compares State pairs only;
  /// the other rebuild scopes the visitor reports are irrelevant here.
  List<RebuildScopeInstance> _stateScopesOf(ResolvedUnitResult result) {
    final visitor = RebuildScopeAnalysisVisitor(result);
    result.unit.accept(visitor);
    return visitor.instances
        .where((i) => i.scopeType == AppConstants.stateScopeType)
        .toList();
  }

  /// Check 5: the mutation must resolve with no ERROR diagnostics against
  /// the unmodified dependency file (replaces the `dart analyze` subprocess).
  Iterable<Violation> _compileViolations(ResolvedUnitResult mutation) {
    final errors = mutation.diagnostics
        .where((d) => d.severity == diag.Severity.error)
        .take(8)
        .toList();
    if (errors.isEmpty) return const [];
    return [
      Violation(
        ViolationCode.doesNotCompile,
        Severity.hard,
        'does not compile:\n${errors.map((e) => e.message).join('\n')}',
      ),
    ];
  }

  /// Check 7: a real structural change is required. `toSource()`
  /// regenerates from tokens, so comment/whitespace-only edits still count
  /// as no-ops.
  Iterable<Violation> _noOpViolation(
    ResolvedUnitResult base,
    ResolvedUnitResult mutation,
  ) {
    if (base.unit.toSource() != mutation.unit.toSource()) return const [];
    return const [
      Violation(
        ViolationCode.noOp,
        Severity.hard,
        'mutation is identical to base; a structural change is required',
      ),
    ];
  }
}
