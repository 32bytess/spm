import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late List<AnalysisResultEntity> results;

  setUpAll(() async {
    results = await getResultsForFixture('state_class_detector/fixture.dart');
  });

  test('detects direct State<> subclass', () {
    expect(
      results.any((r) => r.scopeName == '_DirectState'),
      isTrue,
      reason: 'Direct extends State<X> must be detected.',
    );
  });

  test('detects indirect State<> subclass via abstract base', () {
    expect(
      results.any((r) => r.scopeName == '_IndirectState'),
      isTrue,
      reason:
          '_IndirectState extends BaseState which extends State<X>, so it '
          'must be detected via the supertype chain.',
    );
  });

  test('plain class is not detected', () {
    expect(
      results.any((r) => r.scopeName == 'PlainClass'),
      isFalse,
      reason: 'PlainClass has no State<> ancestor and must not be emitted.',
    );
  });
}
