import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:test/test.dart';

/// A project whose dependencies cannot resolve, and what `isolate` says about it
/// on the second run as well as the first.
void main() {
  late Directory project;
  late Directory output;

  setUp(() {
    project = Directory.systemTemp.createTempSync('spm_degraded_src');
    output = Directory.systemTemp.createTempSync('spm_degraded_out');

    // A dependency that cannot be resolved offline or otherwise, so `pub get`
    // fails and the synthesised fallback config is what gets written.
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync(
      'name: degraded_fixture\n'
      'environment:\n'
      "  sdk: '>=3.0.0 <4.0.0'\n"
      'dependencies:\n'
      '  a_package_that_does_not_exist_anywhere_at_all: ^9.9.9\n',
    );
    Directory(p.join(project.path, 'lib')).createSync();
    File(p.join(project.path, 'lib', 'scope.dart')).writeAsStringSync(
      "import 'package:flutter/material.dart';\n"
      'class Counter extends StatefulWidget {\n'
      '  const Counter({super.key});\n'
      '  @override\n'
      '  State<Counter> createState() => _CounterState();\n'
      '}\n'
      'class _CounterState extends State<Counter> {\n'
      '  @override\n'
      "  Widget build(BuildContext context) => const Text('x');\n"
      '}\n',
    );
  });

  tearDown(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
    if (output.existsSync()) output.deleteSync(recursive: true);
  });

  Future<List<Map<String, dynamic>>> runIsolate() async {
    final jsonl = p.join(output.path, 'map.jsonl');
    await IsolationDataSourceImpl()
        .isolate(
          directories: [project.path],
          outputDir: p.join(output.path, 'out'),
          jsonlPath: jsonl,
        )
        .drain();
    final file = File(jsonl);
    if (!file.existsSync()) return const [];
    return [
      for (final line in file.readAsLinesSync())
        if (line.trim().isNotEmpty)
          jsonDecode(line) as Map<String, dynamic>,
    ];
  }

  test('an unresolvable project is flagged on every run, not just the first',
      () async {
    final first = await runIsolate();
    expect(first, isNotEmpty, reason: 'the scope should still be transplanted');
    expect(
      first.every((row) => row['sourceDependenciesResolved'] == false),
      isTrue,
      reason: 'nothing third-party resolved, so every row is shallow',
    );

    // The first run leaves its own synthesised `package_config.json` behind.
    // Taking that as proof of resolution is what silenced the flag from here
    // on, and in a history walk that is every revision after the first.
    expect(
      File(p.join(project.path, '.dart_tool', 'package_config.json')).existsSync(),
      isTrue,
      reason: 'the fallback config is the thing the second run has to see through',
    );

    final second = await runIsolate();
    expect(second, isNotEmpty);
    expect(
      second.every((row) => row['sourceDependenciesResolved'] == false),
      isTrue,
      reason: 'the second run resolved no more than the first did',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a real package config is not mistaken for a synthesised one', () async {
    // The guard keys on the `generator` field spm writes, so a genuine config
    // has to keep reading as resolved.
    File(p.join(project.path, '.dart_tool', 'package_config.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'degraded_fixture',
            'rootUri': '../',
            'packageUri': 'lib/',
            'languageVersion': '3.0',
          },
        ],
        'generator': 'pub',
      }));

    final rows = await runIsolate();
    expect(rows, isNotEmpty);
    expect(
      rows.any((row) => row.containsKey('sourceDependenciesResolved')),
      isFalse,
      reason: 'pub wrote this config, so the project counts as resolved',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
