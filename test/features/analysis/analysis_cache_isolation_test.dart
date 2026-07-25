import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/core/injection/cli_service_locator.dart';
import 'package:spm/src/features/analysis/domain/entities/analysis_event.dart';
import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

void main() {
  test('repeated analysis does not reuse stale helper AST nodes', () async {
    AnalysisDI.reset();
    final fixtureDir = Directory(
      p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'analysis',
        'tmp_cache_isolation',
      ),
    )..createSync(recursive: true);
    final fixture = File(p.join(fixtureDir.path, 'fixture.dart'));

    try {
      fixture.writeAsStringSync(_source("Text('first')"));
      final first = await _analyze(fixtureDir.path);
      expect(first.helperWidgetCount, equals(1));

      fixture.writeAsStringSync(_source("Center(child: Text('second'))"));
      final second = await _analyze(fixtureDir.path);
      expect(
        second.helperWidgetCount,
        equals(2),
        reason: 'the second run must resolve the modified helper body',
      );
    } finally {
      AnalysisDI.reset();
      if (fixtureDir.existsSync()) fixtureDir.deleteSync(recursive: true);
    }
  });
}

Future<AnalysisResultEntity> _analyze(String path) async {
  final rows = <AnalysisResultEntity>[];
  await for (final event in AnalysisDI.analyzeUseCase.call([path])) {
    event.fold((failure) => fail(failure.message), (value) {
      if (value is AnalysisDataEvent) rows.add(value.result);
    });
  }
  return rows.single;
}

String _source(String helperExpression) =>
    '''
import 'package:flutter/material.dart';

class CacheExample extends StatefulWidget {
  const CacheExample({super.key});

  @override
  State<CacheExample> createState() => _CacheExampleState();
}

class _CacheExampleState extends State<CacheExample> {
  Widget _body() => $helperExpression;

  @override
  Widget build(BuildContext context) => _body();
}
''';
