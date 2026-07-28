import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late AnalysisResultEntity result;

  setUpAll(() async {
    final results = await getResultsForFixture('part_library');
    result = results.singleWhere(
      (row) => row.scopeName == '_PartLibraryExampleState',
    );
  });

  test('indexes helper declarations from part files', () {
    expect(
      result.helperWidgetCount,
      equals(2),
      reason: '_body creates Padding and the const _PartChild',
    );
  });

  test('follows custom child classes declared in part files', () {
    expect(
      result.treeNonConstWidgetCount,
      equals(1),
      reason: 'the non-const Text in _PartChild.build is traversed',
    );
  });
}
