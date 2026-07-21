import 'package:analyzer/dart/analysis/results.dart';
import 'package:spm/features/validation/domain/entities/validation_report.dart';

/// Check 1 — the resolved imported-library sets of base and mutation must
/// be identical.
///
/// Works on the element model (canonical library URIs), so import
/// reordering and `as` aliases are tolerated while a genuinely new
/// dependency is caught.
class ImportComparator {
  List<Violation> compare(ResolvedUnitResult base, ResolvedUnitResult mutation) {
    final baseLibs = _importedLibs(base);
    final mutationLibs = _importedLibs(mutation);

    final added = mutationLibs.difference(baseLibs);
    final removed = baseLibs.difference(mutationLibs);
    if (added.isEmpty && removed.isEmpty) return const [];

    final parts = [
      if (added.isNotEmpty) '+${added.join(', +')}',
      if (removed.isNotEmpty) '-${removed.join(', -')}',
    ];
    return [
      Violation(
        ViolationCode.importsChanged,
        Severity.hard,
        'imported libraries changed: ${parts.join(' ')}',
      ),
    ];
  }

  Set<String> _importedLibs(ResolvedUnitResult r) => r
      .libraryFragment
      .libraryImports
      .where((i) => !i.isSynthetic)
      .map((i) => i.importedLibrary?.uri.toString())
      .whereType<String>()
      .toSet();
}
