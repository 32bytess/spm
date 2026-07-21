/*
integration test for the broken-file guard and instanceId stability:
 - a file with compile errors must be skipped (its unresolved types would
   silently zero every feature) and reported in the summary;
 - instanceId must hash the root-relative path (machine-independent), which
   is exactly the relativized filePath emitted on the row.
*/
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/core/injection/cli_service_locator.dart';
import 'package:spm/features/analysis/domain/entities/analysis_event.dart';
import 'package:spm/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

const _validSource = '''
import 'package:flutter/material.dart';

class TempValidExample extends StatefulWidget {
  const TempValidExample({super.key});

  @override
  State<TempValidExample> createState() => _TempValidExampleState();
}

class _TempValidExampleState extends State<TempValidExample> {
  @override
  Widget build(BuildContext context) {
    return Center(child: Text('ok'));
  }
}
''';

const _brokenSource = '''
import 'package:flutter/material.dart';

class TempBrokenExample extends StatefulWidget {
  const TempBrokenExample({super.key});

  @override
  State<TempBrokenExample> createState() => _TempBrokenExampleState();
}

class _TempBrokenExampleState extends State<TempBrokenExample> {
  @override
  Widget build(BuildContext context) {
    return undefinedSymbol(noSuchIdentifier);
  }
}
''';

void main() {
  group('analyzeDirs guard against broken files', () {
    late Directory fixtureDir;
    late List<AnalysisResultEntity> rows;
    AnalysisSummaryEvent? summary;

    setUpAll(() async {
      // Created at runtime (and removed in tearDownAll) so the deliberately
      // broken file never sits in the repo to fail `dart analyze`. It must
      // live inside the package for package:flutter imports to resolve.
      fixtureDir = Directory(
        p.join(
          Directory.current.path,
          'test',
          'fixtures',
          'analysis',
          'tmp_broken_guard',
        ),
      )..createSync(recursive: true);
      File(
        p.join(fixtureDir.path, 'valid_example.dart'),
      ).writeAsStringSync(_validSource);
      File(
        p.join(fixtureDir.path, 'broken_example.dart'),
      ).writeAsStringSync(_brokenSource);

      rows = [];
      await for (final event in AnalysisDI.analyzeUseCase.call([
        fixtureDir.path,
      ])) {
        event.fold((failure) {}, (result) {
          if (result is AnalysisDataEvent) rows.add(result.result);
          if (result is AnalysisSummaryEvent) summary = result;
        });
      }
    });

    tearDownAll(() {
      if (fixtureDir.existsSync()) fixtureDir.deleteSync(recursive: true);
    });

    test('the valid file still yields its row', () {
      expect(
        rows.map((r) => r.stateClassName),
        contains('_TempValidExampleState'),
      );
    });

    test('the broken file yields no garbage row', () {
      expect(
        rows.map((r) => r.stateClassName),
        isNot(contains('_TempBrokenExampleState')),
        reason:
            'unresolved types would classify every widget as a value object '
            'and emit a near-zero feature row',
      );
    });

    test('the summary reports the skip honestly', () {
      expect(summary, isNotNull);
      expect(summary!.filesSkipped, equals(1));
      expect(summary!.keptRows, equals(rows.length));
    });
  });

  group('instanceId', () {
    test('hashes the root-relative path (machine-independent)', () async {
      final results = await getResultsForFixture('build_tree/widget_count.dart');
      expect(results, isNotEmpty);
      for (final r in results) {
        expect(p.isRelative(r.filePath), isTrue);
        expect(
          r.instanceId,
          equals(_rollingHash('${r.filePath}:${r.stateClassName}')),
          reason:
              'instanceId must be derived from the same root-relative path '
              'emitted as filePath, not the absolute path',
        );
      }
    });
  });
}

/// Mirror of StateClassVisitor._hash.
String _rollingHash(String s) => s.codeUnits
    .fold<int>(0, (a, b) => (a * 131 + b) & 0x7fffffff)
    .toRadixString(16);
