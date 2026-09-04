import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/helpers/inline_budget.dart';
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:test/test.dart';

import 'utils/temp_project.dart';

/// Which packages a transplant carried source from, not merely how much.
///
/// `inlinedThirdPartyDeclarations` says a scope carried package code; it does
/// not say whose. A consumer deciding whether the isolated file may be
/// redistributed needs the names and the versions, and every other field the
/// row carries answers a different question: `carriedUiDeclarations` names the
/// repository's own libraries in the same list and records a declaration
/// before the budget decides whether to keep it.
///
/// The invariant these tests exist to pin is that the two cannot drift: they
/// are written in the same statement inside [InlineBudget.take], so a build
/// that reports a count and no packages means a path or git dependency, never
/// a recording somebody forgot to make.
const String _scopeSource = '''
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

class PackagedHost extends StatefulWidget {
  const PackagedHost({super.key});

  @override
  State<PackagedHost> createState() => PackagedHostState();
}

class PackagedHostState extends State<PackagedHost> {
  @override
  Widget build(BuildContext context) => Column(
    children: [const FancyButton(label: 'go'), const FancyPanel()],
  );
}
''';

void main() {
  group('hostedPackageOf', () {
    test('reads the name and version out of a pub-cache path', () {
      final package = hostedPackageOf(
        '/home/u/.pub-cache/hosted/pub.dev/auto_size_text_field-2.2.4/lib/src/x.dart',
      );
      expect(package?.name, 'auto_size_text_field');
      expect(package?.version, '2.2.4');
    });

    test('reads a prerelease and a build suffix whole', () {
      final package = hostedPackageOf(
        '/c/.pub-cache/hosted/pub.dev/flutter_svg-2.0.0-nullsafety.1/lib/svg.dart',
      );
      expect(package?.version, '2.0.0-nullsafety.1');
    });

    test('a path or git dependency carries no version to read', () {
      // Not a failure and not an error: such a directory genuinely has no
      // version in it. The count still moves, which is the signal that one is
      // in play, and `null` here is what makes that visible rather than
      // inventing a version nobody declared.
      expect(hostedPackageOf('/work/packages/ui_kit/lib/ui_kit.dart'), isNull);
      expect(hostedPackageOf('/repo/lib/widgets/panel.dart'), isNull);
    });
  });

  group('InlineBudget', () {
    test('records the package in the same statement as the count', () {
      final budget = InlineBudget();
      expect(
        budget.take(10, '/c/hosted/pub.dev/fl_chart-0.68.0/lib/fl_chart.dart'),
        isTrue,
      );
      expect(budget.inlinedDeclarations, 1);
      expect(budget.inlinedPackages, {'fl_chart': '0.68.0'});
    });

    test('a refused take records nothing', () {
      // The declaration takes the stand-in path, so its source is not in the
      // file and naming its package would be a false positive on exactly the
      // question the field is read for.
      final budget = InlineBudget(maxDeclarations: 1);
      budget.take(10, '/c/hosted/pub.dev/fl_chart-0.68.0/lib/fl_chart.dart');
      expect(
        budget.take(10, '/c/hosted/pub.dev/gap-3.0.1/lib/gap.dart'),
        isFalse,
      );
      expect(budget.inlinedPackages, {'fl_chart': '0.68.0'});
    });

    test('the same package twice is one entry', () {
      final budget = InlineBudget();
      budget.take(10, '/c/hosted/pub.dev/gap-3.0.1/lib/gap.dart');
      budget.take(10, '/c/hosted/pub.dev/gap-3.0.1/lib/src/gap_impl.dart');
      expect(budget.inlinedDeclarations, 2);
      expect(budget.inlinedPackages, {'gap': '3.0.1'});
    });
  });

  group('the isolated row', () {
    late TempProject project;
    late String outputDir;
    late String cacheDir;
    late Map<String, dynamic> row;

    setUpAll(() async {
      // The fixture package is copied under a `name-version` directory, which
      // is the shape a hosted dependency resolves to and the only place the
      // version appears. Checked in as a plain `ui_kit/` because a path
      // dependency is what the budget test needs; renamed here because a
      // hosted one is what this test is about.
      cacheDir = Directory.systemTemp
          .createTempSync('spm_third_party_packages_cache')
          .path;
      final packageRoot = p.join(cacheDir, 'ui_kit-1.4.2');
      _copyDirectory(
        Directory(p.absolute('test/fixtures/isolation_third_party/ui_kit')),
        Directory(packageRoot),
      );

      project = TempProject.create(
        sources: {'scope.dart': _scopeSource},
        extraPackages: {'ui_kit': packageRoot},
        prefix: 'spm_third_party_packages',
      );
      outputDir = Directory.systemTemp
          .createTempSync('spm_third_party_packages_out')
          .path;
      final jsonlPath = p.join(outputDir, 'map.jsonl');

      await IsolationDataSourceImpl()
          .isolate(
            directories: [project.path],
            outputDir: outputDir,
            jsonlPath: jsonlPath,
          )
          .toList();

      row = File(jsonlPath)
          .readAsLinesSync()
          .where((line) => line.trim().isNotEmpty)
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .firstWhere((r) => r['name'] == 'PackagedHostState');
    });

    tearDownAll(() {
      project.delete();
      for (final path in [outputDir, cacheDir]) {
        final dir = Directory(path);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });

    test('names the package and the version its source came from', () {
      expect(row['inlinedThirdPartyPackages'], {'ui_kit': '1.4.2'});
    });

    test('the count and the packages are non-empty together', () {
      final count = row['inlinedThirdPartyDeclarations'] as int?;
      final packages = row['inlinedThirdPartyPackages'] as Map?;
      expect(count, isNotNull);
      expect(count, greaterThan(0));
      expect(packages, isNotNull);
      expect(packages, isNotEmpty);
    });
  });
}

void _copyDirectory(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(recursive: true)) {
    final relative = p.relative(entity.path, from: from.path);
    final target = p.join(to.path, relative);
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      File(target).parent.createSync(recursive: true);
      entity.copySync(target);
    }
  }
}
