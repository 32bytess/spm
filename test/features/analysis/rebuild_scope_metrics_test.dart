import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late List<AnalysisResultEntity> results;

  setUpAll(() async {
    results = await getResultsForFixture('rebuild_scopes/scopes.dart');
  });

  AnalysisResultEntity byName(String scopeName) =>
      results.firstWhere((r) => r.scopeName == scopeName);

  List<AnalysisResultEntity> allNamed(String scopeName) =>
      results.where((r) => r.scopeName == scopeName).toList();

  group('scope discovery', () {
    test('emits a row for every rebuild scope, not only State subclasses', () {
      expect(
        results.map((r) => '${r.scopeType}:${r.scopeName}'),
        containsAll([
          'State:_BuilderHostState',
          'ConsumerWidget:ProfileConsumer',
          'BlocBuilder:BlocBuilder_builder',
          'Obx:Obx_builder',
        ]),
      );
    });

    test('a builder given a tear-off yields no row', () {
      // TearOffHost passes a method reference; there is no callback body at
      // the creation site to measure.
      expect(allNamed('BlocBuilder_builder'), hasLength(2));
      expect(results, hasLength(5));
    });

    test('repeated builder scopes of one kind get distinct instanceIds', () {
      final ids = allNamed('BlocBuilder_builder').map((r) => r.instanceId);
      expect(ids.toSet(), hasLength(2));
    });

    test('every row carries a scope type', () {
      expect(results.map((r) => r.scopeType), everyElement(isNotEmpty));
    });
  });

  group('metrics', () {
    test('a ConsumerWidget build tree is measured like a State build', () {
      final consumer = byName('ProfileConsumer');
      // Column + Padding + Text; the Divider is const, EdgeInsets is a const
      // value object.
      expect(consumer.treeNonConstWidgetCount, equals(3));
      expect(consumer.treeConstWidgetCount, equals(1));
      expect(consumer.treeMaxWidgetNestingDepth, equals(3));
      expect(consumer.valueObjectAllocCount, equals(0));
    });

    test('a builder row measures only its own callback', () {
      final padded = allNamed(
        'BlocBuilder_builder',
      ).firstWhere((r) => r.treeNonConstWidgetCount == 2);
      // Padding + Text, with one non-const EdgeInsets allocation.
      expect(padded.valueObjectAllocCount, equals(1));
      expect(padded.treeMaxWidgetNestingDepth, equals(2));

      final obx = byName('Obx_builder');
      expect(obx.treeNonConstWidgetCount, equals(1));
      expect(obx.treeConstWidgetCount, equals(1));
    });

    test('the enclosing State row still counts the nested callbacks', () {
      final host = byName('_BuilderHostState');
      final builders = results.where((r) => r.scopeName.endsWith('_builder'));
      final builderWidgets = builders.fold<int>(
        0,
        (sum, r) => sum + r.treeNonConstWidgetCount,
      );

      // Column + 2 BlocBuilder + Obx + everything the callbacks build: the
      // overlap is intentional, a parent rebuild re-runs every callback.
      expect(host.treeNonConstWidgetCount, equals(8));
      expect(host.treeNonConstWidgetCount, greaterThan(builderWidgets));
    });
  });
}
