import 'package:spm/core/types.dart';

/// Severity of a base↔mutation invariant violation.
///
/// [hard] always fails the pair; [soft] fails only under `--strict`.
enum Severity { hard, soft }

/// Machine-readable identifier for each invariant check.
enum ViolationCode {
  importsChanged,
  seedsChanged,
  contentDrift,
  valueDrift,
  doesNotCompile,
  forbiddenConstruct,
  noOp,
  featureDeltaTangled,
  derivationDrift,
}

/// A single invariant violation found while comparing a base↔mutation pair.
class Violation {
  final ViolationCode code;
  final Severity severity;

  /// Human-readable explanation; also fed back to the LLM on retry.
  final String detail;

  const Violation(this.code, this.severity, this.detail);

  JsonRecord toJson() => {
    'code': code.name,
    'severity': severity.name,
    'detail': detail,
  };
}

/// Result of validating that a mutation is a clean structural variant of
/// its base: same imports, seeds, rendered content and workload — only the
/// widget-tree structure may differ.
class ValidationReport {
  final String basePath;
  final String mutationPath;
  final List<Violation> violations;

  /// 12-key feature vector delta (mutation - base). Empty until the
  /// feature-delta audit (check 8) is wired in.
  final Map<String, int> featureDelta;

  final String? baseInstanceId;
  final String? mutationInstanceId;

  const ValidationReport({
    required this.basePath,
    required this.mutationPath,
    required this.violations,
    this.featureDelta = const {},
    this.baseInstanceId,
    this.mutationInstanceId,
  });

  /// Whether the pair passes: no hard violations, and no soft ones either
  /// when [strict] is set.
  bool isValid({required bool strict}) => violations.every(
    (v) => strict ? false : v.severity == Severity.soft,
  );

  int exitCode({required bool strict}) => isValid(strict: strict) ? 0 : 1;

  JsonRecord toJson({required bool strict}) => {
    'base': basePath,
    'mutation': mutationPath,
    if (baseInstanceId != null) 'baseInstanceId': baseInstanceId,
    if (mutationInstanceId != null) 'mutationInstanceId': mutationInstanceId,
    'valid': isValid(strict: strict),
    'violations': violations.map((v) => v.toJson()).toList(),
    'featureDelta': featureDelta,
  };
}
