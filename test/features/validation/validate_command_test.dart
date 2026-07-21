import 'dart:convert';
import 'dart:io';

import 'package:spm/core/injection/cli_service_locator.dart';
import 'package:spm/runner.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

/// Hand-written stdout fake: captures `write`/`writeln` so the `--json`
/// machine output can be asserted on. Any other member throws.
class _StdoutCapture implements Stdout {
  final StringBuffer buffer = StringBuffer();

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(ValidationDI.reset);
  tearDown(ValidationDI.reset);

  Future<int?> runValidate(List<String> args) =>
      SpmRunner().run(['validate', ...args]);

  String fixtureArg(String dir, String file) => validationFixturePath(dir, file);

  test('valid pair exits 0', () async {
    final exitCode = await runValidate([
      '--base', fixtureArg('ok', 'base.dart'),
      '--mutation', fixtureArg('ok', 'mutation.dart'),
    ]);

    expect(exitCode, 0);
  });

  test('hard violation exits 1', () async {
    final exitCode = await runValidate([
      '--base', fixtureArg('content_changed', 'base.dart'),
      '--mutation', fixtureArg('content_changed', 'mutation.dart'),
    ]);

    expect(exitCode, 1);
  });

  test('missing file is a usage error (64)', () async {
    final exitCode = await runValidate([
      '--base', fixtureArg('ok', 'does_not_exist.dart'),
      '--mutation', fixtureArg('ok', 'mutation.dart'),
    ]);

    expect(exitCode, 64);
  });

  test('missing mandatory option is a usage error (64)', () async {
    final exitCode = await runValidate([
      '--base', fixtureArg('ok', 'base.dart'),
    ]);

    expect(exitCode, 64);
  });

  test('--json emits one parseable report with the documented keys',
      () async {
    final capture = _StdoutCapture();

    final exitCode = await IOOverrides.runZoned(
      () => runValidate([
        '--base', fixtureArg('content_changed', 'base.dart'),
        '--mutation', fixtureArg('content_changed', 'mutation.dart'),
        '--json',
      ]),
      stdout: () => capture,
    );

    expect(exitCode, 1);
    final report = jsonDecode(capture.buffer.toString().trim());
    expect(report['base'], fixtureArg('content_changed', 'base.dart'));
    expect(report['mutation'], fixtureArg('content_changed', 'mutation.dart'));
    expect(report['valid'], isFalse);
    expect(report['violations'], isNotEmpty);
    expect(report['violations'][0], containsPair('code', 'contentDrift'));
    expect(report['violations'][0], containsPair('severity', 'hard'));
    expect(report['violations'][0]['detail'], isA<String>());
    expect(report['featureDelta'], isA<Map<String, dynamic>>());
  });
}
