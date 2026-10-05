import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/screening/domain/count_rule.dart';
import 'package:spm/src/features/screening/domain/entities/screen_report.dart';
import 'package:spm/src/features/screening/domain/forest_model.dart';

/// Pairs the scopes of two extractions and scores every one that moved.
///
/// Pure: no file system and no git, so the matching and the verdicts are
/// tested on literal rows.
class CompareUseCase {
  /// The fourteen per-scope metrics of `spm analyze`, in its column order.
  static const metrics = [
    'treeNonConstWidgetCount',
    'treeMaxWidgetNestingDepth',
    'treeListRenderingStrategy',
    'rootBuildReturnsConstWidget',
    'treeConstWidgetCount',
    'helperReferenceCount',
    'usesLayoutDependentBuilder',
    'treeCyclomaticComplexity',
    'treeIterationCount',
    'treeMaxIterationNestingDepth',
    'iterationWidgetCount',
    'valueObjectAllocCount',
    'helperWidgetCount',
    'helperMaxWidgetNestingDepth',
  ];

  final ForestModel forest;

  CompareUseCase(this.forest);

  /// A scope is the same scope in both versions when its file, type and name
  /// agree. A renamed or moved scope shows up as one removed and one added.
  static String scopeKey(JsonRecord row) =>
      '${row['filePath']}#${row['scopeType']}:${row['scopeName']}';

  ScreenReport call({
    required Snapshot baseline,
    required String baselineReason,
    required List<JsonRecord> before,
    required List<JsonRecord> after,
    List<String> extraWarnings = const [],
  }) {
    final b = _index(before);
    final a = _index(after);
    final changed = <ScopeComparison>[];
    var unchanged = 0;

    for (final key in (a.keys.toSet()..retainAll(b.keys)).toList()..sort()) {
      final rb = b[key]!;
      final ra = a[key]!;
      final delta = <String, num>{
        for (final m in metrics)
          if ((ra[m] as num) != (rb[m] as num))
            m: (ra[m] as num) - (rb[m] as num),
      };
      if (delta.isEmpty) {
        unchanged++;
        continue;
      }
      final vector = [for (final f in forest.features) delta[f] ?? 0];
      final visible = vector.any((d) => d != 0);
      final forward = visible ? forest.probability(vector) : null;
      final reverse = visible
          ? forest.probability([for (final d in vector) -d])
          : null;
      changed.add(
        ScopeComparison(
          key: key,
          delta: delta,
          ruleSlower: visible ? CountRule.slower(delta) : null,
          forestScore: visible ? forward! - reverse! : null,
          forestForward: forward,
          forestReverse: reverse,
          warnings: [...extraWarnings, ..._warnings(rb, ra)],
        ),
      );
    }

    return ScreenReport(
      baseline: baseline,
      baselineReason: baselineReason,
      changed: changed,
      added: (a.keys.toSet().difference(b.keys.toSet()).toList()..sort()),
      removed: (b.keys.toSet().difference(a.keys.toSet()).toList()..sort()),
      unchanged: unchanged,
    );
  }

  static Map<String, JsonRecord> _index(List<JsonRecord> rows) => {
    for (final r in rows) scopeKey(r): r,
  };

  static List<String> _warnings(JsonRecord before, JsonRecord after) {
    final out = <String>[];
    if (before['closureResolved'] == 0 || after['closureResolved'] == 0) {
      out.add(
        'unresolved dependencies: part of the widget tree could not be read, '
        'so the delta may reflect resolution state rather than the edit',
      );
    }
    final pb = (before['packageVersions'] as Map?) ?? const {};
    final pa = (after['packageVersions'] as Map?) ?? const {};
    final moved = {...pb.keys, ...pa.keys}.where((k) => pb[k] != pa[k]).toList()
      ..sort();
    if (moved.isNotEmpty) {
      out.add(
        'package versions changed (${moved.join(', ')}): the delta may come '
        'from a dependency upgrade rather than from this code',
      );
    }
    return out;
  }
}
