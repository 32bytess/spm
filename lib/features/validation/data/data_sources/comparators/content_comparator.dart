import 'package:analyzer/dart/ast/ast.dart';
import 'package:spm/features/validation/domain/entities/validation_report.dart';
import '../visitors/rendered_leaf_visitor.dart';

/// Check 3 — rendered content must be identical: the multiset of displayed
/// `Text`/`SelectableText`/`Tooltip` strings and the sets of `Icons.*` and
/// asset references may not differ between base and mutation.
class ContentComparator {
  List<Violation> compare(CompilationUnit base, CompilationUnit mutation) {
    final baseLeaves = RenderedLeafVisitor();
    final mutationLeaves = RenderedLeafVisitor();
    base.accept(baseLeaves);
    mutation.accept(mutationLeaves);

    final violations = <Violation>[];

    final textDiff = _multisetDiff(baseLeaves.texts, mutationLeaves.texts);
    if (textDiff != null) {
      violations.add(_violation('rendered text differs', textDiff));
    }

    final iconDiff = _setDiff(baseLeaves.icons, mutationLeaves.icons);
    if (iconDiff != null) {
      violations.add(_violation('Icons.* usage differs', iconDiff));
    }

    final assetDiff = _setDiff(baseLeaves.assets, mutationLeaves.assets);
    if (assetDiff != null) {
      violations.add(_violation('asset references differ', assetDiff));
    }

    return violations;
  }

  Violation _violation(String what, String diff) =>
      Violation(ViolationCode.contentDrift, Severity.hard, '$what: $diff');

  /// Multiset difference so a duplicated or dropped label is caught even
  /// when the distinct string sets are equal. Returns null when identical.
  String? _multisetDiff(List<String> base, List<String> mutation) {
    final counts = <String, int>{};
    for (final t in base) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    for (final t in mutation) {
      counts[t] = (counts[t] ?? 0) - 1;
    }
    final added = <String>[];
    final removed = <String>[];
    counts.forEach((text, count) {
      if (count < 0) added.addAll(List.filled(-count, text));
      if (count > 0) removed.addAll(List.filled(count, text));
    });
    return _renderDiff(added, removed);
  }

  String? _setDiff(Set<String> base, Set<String> mutation) => _renderDiff(
    mutation.difference(base).toList(),
    base.difference(mutation).toList(),
  );

  String? _renderDiff(List<String> added, List<String> removed) {
    if (added.isEmpty && removed.isEmpty) return null;
    return [
      if (added.isNotEmpty) '+$added',
      if (removed.isNotEmpty) '-$removed',
    ].join(' ');
  }
}
