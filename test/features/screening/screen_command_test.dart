import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/core/injection/cli_service_locator.dart';
import 'package:spm/src/runner.dart';
import 'package:test/test.dart';

const _before = '''
import 'package:flutter/material.dart';

class Counter extends StatefulWidget {
  const Counter({super.key});
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int count = 0;

  void increment() => setState(() => count++);

  @override
  Widget build(BuildContext context) {
    return Column(children: [Text('\$count')]);
  }
}
''';

/// The same scope with three more non-const widgets in its tree.
final _after = _before.replaceFirst(
  "children: [Text('\$count')]",
  "children: [Text('\$count'), Text('a'), Text('b'), Padding(padding: EdgeInsets.all(count.toDouble()), child: Text('c'))]",
);

void main() {
  late Directory repo;
  final packageConfig = p.join(
    Directory.current.path,
    '.dart_tool',
    'package_config.json',
  );

  Future<void> git(List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: repo.path);
    if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
  }

  Future<int> spm(List<String> args) => SpmRunner()
      .run(['screen', ...args, p.join(repo.path, 'lib')])
      .then((code) => code ?? 0);

  setUp(() async {
    repo = Directory.systemTemp.createTempSync('spm_screen_');
    Directory(p.join(repo.path, 'lib')).createSync();
    // A resolved project, as `flutter pub get` would leave it: this package's
    // own config carries package:flutter.
    Directory(p.join(repo.path, '.dart_tool')).createSync();
    File(
      packageConfig,
    ).copySync(p.join(repo.path, '.dart_tool', 'package_config.json'));
    File(p.join(repo.path, '.gitignore')).writeAsStringSync('.dart_tool/\n');
    File(p.join(repo.path, 'lib', 'counter.dart')).writeAsStringSync(_before);
    await git(['init', '-q']);
    await git(['-c', 'user.email=t@t', '-c', 'user.name=t', 'add', '.']);
    await git([
      '-c',
      'user.email=t@t',
      '-c',
      'user.name=t',
      'commit',
      '-qm',
      'before',
    ]);
  });

  tearDown(() {
    AnalysisDI.reset();
    repo.deleteSync(recursive: true);
  });

  test('snapshot stores the rows under the commit hash', () async {
    expect(await spm(['snapshot']), equals(0));
    final index =
        jsonDecode(
              File(
                p.join(repo.path, '.spm', 'screen', 'index.json'),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final snap = (index['snapshots'] as List).single as Map<String, dynamic>;
    expect(snap['dirty'], isFalse);
    final rows = File(
      p.join(repo.path, '.spm', 'screen', '${snap['id']}.jsonl'),
    ).readAsLinesSync();
    expect(rows, hasLength(1));
    expect(jsonDecode(rows.single)['filePath'], equals('lib/counter.dart'));
  });

  test('compare without a snapshot fails with a hint', () async {
    expect(await spm(['compare']), equals(1));
  });

  test('an uncommitted edit that adds widgets is flagged slower', () async {
    expect(await spm(['snapshot']), equals(0));
    File(p.join(repo.path, 'lib', 'counter.dart')).writeAsStringSync(_after);
    expect(await spm(['compare', '--fail-on', 'rule']), equals(1));
  });

  test('a committed edit is compared against the ancestor snapshot', () async {
    expect(await spm(['snapshot']), equals(0));
    File(p.join(repo.path, 'lib', 'counter.dart')).writeAsStringSync(_after);
    await git([
      '-c',
      'user.email=t@t',
      '-c',
      'user.name=t',
      'commit',
      '-qam',
      'after',
    ]);
    expect(await spm(['compare', '--fail-on', 'rule']), equals(1));
    // Reverting the edit is not slower by the rule.
    expect(await spm(['snapshot']), equals(0));
    File(p.join(repo.path, 'lib', 'counter.dart')).writeAsStringSync(_before);
    expect(await spm(['compare', '--fail-on', 'rule']), equals(0));
  });

  test(
    'a clean HEAD with only its own snapshot has nothing to compare',
    () async {
      expect(await spm(['snapshot']), equals(0));
      expect(await spm(['compare']), equals(1));
    },
  );
}
