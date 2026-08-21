import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:spm/src/features/isolation/domain/entities/isolation_event.dart';
import 'package:test/test.dart';

import 'utils/temp_project.dart';

/// Covers the references the analyzer resolves to nothing.
///
/// Two situations produce them, and both are common in real application code.
/// A package the transplant refuses to import defines an extension the scope
/// calls, `context.read<T>()` being the one that reaches a large share of
/// scopes. And a revision whose `pub get` never succeeded resolves no
/// third-party name at all, so nothing reaches the import gate or the shim
/// emitter and every such name used to survive into the output undeclared.
///
/// The import here names a package that is in no package config, so every
/// symbol behind it has a null element. That is exactly the failed-`pub get`
/// state, reproduced without needing a failed `pub get`.
const String _scopeSource = '''
import 'package:flutter/material.dart';
import 'package:not_installed/not_installed.dart';

class UnresolvedHost extends StatefulWidget {
  const UnresolvedHost({super.key});

  @override
  State<UnresolvedHost> createState() => UnresolvedHostState();
}

class UnresolvedHostState extends State<UnresolvedHost> {
  @override
  Widget build(BuildContext context) {
    final model = context.read<ChatModel>();
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(8.sp),
          child: MissingCard(title: 'hi', count: 2),
        ),
        Text('\$model \$missingGlobal'),
      ],
    );
  }
}
''';

void main() {
  late TempProject project;
  late String outputDir;
  late String isolated;
  late IsolationSummaryEvent summary;

  setUpAll(() async {
    project = TempProject.create(
      sources: {'scope.dart': _scopeSource},
      prefix: 'spm_unresolved',
    );
    outputDir = Directory.systemTemp.createTempSync('spm_unresolved_out').path;

    final events = await IsolationDataSourceImpl()
        .isolate(directories: [project.path], outputDir: outputDir)
        .toList();
    summary = events.last as IsolationSummaryEvent;

    isolated = Directory(p.join(outputDir, 'State'))
        .listSync(recursive: false)
        .whereType<File>()
        .firstWhere((f) => f.path.contains('UnresolvedHostState'))
        .readAsStringSync();
  });

  tearDownAll(() {
    project.delete();
    final dir = Directory(outputDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('never imports the package it could not resolve', () {
    expect(isolated, isNot(contains('package:not_installed')));
  });

  test('restores a context extension the import gate refuses to bring in', () {
    // `read` is declared by provider or flutter_bloc, neither of which the
    // isolated file may import. Rebuilt as an extension on BuildContext, it
    // names no package and covers `watch` and `select` the same way.
    expect(
      isolated,
      contains('extension _SpmBuildContextShim on BuildContext'),
    );
    expect(isolated, contains('dynamic read<T0>()'));
  });

  test('restores an extension on an SDK type', () {
    // The `.sp` / `.w` / `.h` sizing extensions are the widest family of
    // undefined names, since a sizing package is hung off `num` itself.
    expect(isolated, contains('extension _SpmNumShim on num'));
    expect(isolated, contains('dynamic get sp'));
  });

  test('an unresolved constructor in a widget position becomes a widget', () {
    // Widget-ness is the one property a stand-in has to preserve:
    // `BuildMetricsVisitor` sorts the allocation by walking the supertype
    // chain, so a plain class would move it into valueObjectAllocCount.
    expect(isolated, contains('class MissingCard extends StatelessWidget'));
    expect(isolated, contains('dynamic title'));
    expect(isolated, contains('dynamic count'));
  });

  test(
    'an unresolved bare identifier is declared rather than left dangling',
    () {
      expect(isolated, contains('late dynamic missingGlobal;'));
    },
  );

  test('every isolated file analyses clean', () {
    // The property the whole feature exists for: `spm analyze` skips any file
    // carrying an error-severity diagnostic, so a scope that was written but
    // does not analyse contributes nothing.
    expect(summary.verifiedCount, greaterThan(0));
    expect(
      summary.cleanCount,
      summary.verifiedCount,
      reason: '${summary.errorCount} errors across the isolated files',
    );
  });
}
