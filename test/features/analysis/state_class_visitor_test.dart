import 'package:spm/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late List<AnalysisResultEntity> results;

  setUpAll(() async {
    results = await getResultsForFixture(
      'state_class_visitor/fixture.dart',
    );
  });

  test('emits exactly one row per State<> subclass, not per setState call', () {
    expect(
      results,
      hasLength(2),
      reason:
          'Fixture has two State<> subclasses (_FooState, _BarState); '
          'the non-State NotAState class must not produce a row.',
    );
  });

  test('stateClassName is the State subclass name, not the method name', () {
    final names = results.map((r) => r.stateClassName).toSet();
    expect(names, containsAll(['_FooState', '_BarState']));
  });
}
