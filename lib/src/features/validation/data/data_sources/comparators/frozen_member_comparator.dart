import 'package:analyzer/dart/ast/ast.dart';
import 'package:spm/src/features/validation/domain/entities/validation_report.dart';

/// Check 2 — input data and state seeds must be frozen: the
/// `initState`/`dispose`/`didUpdateWidget` bodies and the field region of
/// the State class must be identical between base and mutation.
///
/// Comparison uses `AstNode.toSource()`, which regenerates code from
/// tokens, so formatting and comments cannot cause false violations.
class FrozenMemberComparator {
  static const _frozenMethods = ['initState', 'dispose', 'didUpdateWidget'];

  List<Violation> compare(ClassDeclaration base, ClassDeclaration mutation) {
    final violations = <Violation>[];

    for (final name in _frozenMethods) {
      final baseBody = _methodBody(base, name);
      final mutationBody = _methodBody(mutation, name);
      if (baseBody != mutationBody) {
        violations.add(
          Violation(
            ViolationCode.seedsChanged,
            Severity.hard,
            "'$name' differs between base and mutation "
            '(state seeds must be frozen)',
          ),
        );
      }
    }

    if (_fieldRegion(base) != _fieldRegion(mutation)) {
      violations.add(
        Violation(
          ViolationCode.seedsChanged,
          Severity.hard,
          'field declarations differ between base and mutation '
          '(input data must be frozen)',
        ),
      );
    }

    return violations;
  }

  String? _methodBody(ClassDeclaration cls, String name) => _members(cls)
      .whereType<MethodDeclaration>()
      .where((m) => m.name.lexeme == name)
      .map((m) => m.body.toSource())
      .firstOrNull;

  String _fieldRegion(ClassDeclaration cls) => _members(
    cls,
  ).whereType<FieldDeclaration>().map((f) => f.toSource()).join('\n');

  Iterable<ClassMember> _members(ClassDeclaration cls) {
    final body = cls.body;
    if (body is BlockClassBody) return body.members;
    return const <ClassMember>[];
  }
}
