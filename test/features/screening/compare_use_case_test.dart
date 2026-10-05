import 'package:spm/src/features/screening/data/forest_loader.dart';
import 'package:spm/src/features/screening/domain/entities/screen_report.dart';
import 'package:spm/src/features/screening/domain/use_cases/compare_use_case.dart';
import 'package:test/test.dart';

Map<String, dynamic> row(
  String file,
  String name, {
  Map<String, int> metrics = const {},
  int closureResolved = 1,
  Map<String, String> packages = const {},
}) => {
  'filePath': file,
  'scopeType': 'State',
  'scopeName': name,
  for (final m in CompareUseCase.metrics) m: metrics[m] ?? 0,
  'closureResolved': closureResolved,
  'packageVersions': packages,
};

void main() {
  final compare = CompareUseCase(ForestLoader.load());
  final baseline = Snapshot(
    id: 'abc',
    commit: 'abc',
    dirty: false,
    createdAt: DateTime.utc(2026, 10, 4),
    spmVersion: '0.8.0',
    directories: ['lib'],
  );

  ScreenReport run(
    List<Map<String, dynamic>> before,
    List<Map<String, dynamic>> after,
  ) => compare(
    baseline: baseline,
    baselineReason: 'test',
    before: before,
    after: after,
  );

  test('added widgets: the rule says slower', () {
    final r = run(
      [
        row('lib/a.dart', '_AState', metrics: {'treeNonConstWidgetCount': 3}),
      ],
      [
        row('lib/a.dart', '_AState', metrics: {'treeNonConstWidgetCount': 7}),
      ],
    );
    expect(r.changed.single.ruleSlower, isTrue);
    expect(r.changed.single.delta, equals({'treeNonConstWidgetCount': 4}));
  });

  test('the revert of an edit gets the opposite forest verdict', () {
    final small = row(
      'lib/a.dart',
      '_AState',
      metrics: {'treeNonConstWidgetCount': 3, 'helperWidgetCount': 1},
    );
    final big = row(
      'lib/a.dart',
      '_AState',
      metrics: {'treeNonConstWidgetCount': 9, 'helperWidgetCount': 4},
    );
    final forward = run([small], [big]).changed.single.forestScore!;
    final back = run([big], [small]).changed.single.forestScore!;
    expect(back, closeTo(-forward, 1e-15));
  });

  test('unchanged, added and removed scopes are reported, not scored', () {
    final r = run(
      [row('lib/a.dart', '_AState'), row('lib/b.dart', '_OldState')],
      [row('lib/a.dart', '_AState'), row('lib/b.dart', '_NewState')],
    );
    expect(r.unchanged, equals(1));
    expect(r.changed, isEmpty);
    expect(r.added, equals(['lib/b.dart#State:_NewState']));
    expect(r.removed, equals(['lib/b.dart#State:_OldState']));
  });

  test('a move only outside the model gets no verdict', () {
    final r = run(
      [row('lib/a.dart', '_AState')],
      [
        row('lib/a.dart', '_AState', metrics: {'treeIterationCount': 2}),
      ],
    );
    expect(r.changed.single.scored, isFalse);
    expect(r.changed.single.forestScore, isNull);
  });

  test('unresolved closures and moved packages are warned about', () {
    final r = run(
      [
        row('lib/a.dart', '_AState', packages: {'provider': '6.0.0'}),
      ],
      [
        row(
          'lib/a.dart',
          '_AState',
          metrics: {'treeNonConstWidgetCount': 1},
          closureResolved: 0,
          packages: {'provider': '6.1.0'},
        ),
      ],
    );
    final w = r.changed.single.warnings.join('\n');
    expect(w, contains('unresolved dependencies'));
    expect(w, contains('package versions changed (provider)'));
  });
}
