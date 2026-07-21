import 'package:analyzer/dart/ast/ast.dart';
import 'package:spm/features/validation/domain/entities/validation_report.dart';
import '../visitors/forbidden_construct_visitor.dart';

/// Check 6 — the mutation may not contain constructs that break
/// measurement determinism (async/await/Future/Stream/Random/
/// DateTime.now/dart:io/network/animation).
class ForbiddenComparator {
  List<Violation> compare(CompilationUnit mutation) {
    final visitor = ForbiddenConstructVisitor();
    mutation.accept(visitor);
    return visitor.findings
        .toSet()
        .map(
          (finding) => Violation(
            ViolationCode.forbiddenConstruct,
            Severity.hard,
            finding,
          ),
        )
        .toList();
  }
}
