import 'package:spm/core/injection/cli_service_locator.dart';
import 'package:spm/features/validation/domain/entities/validation_report.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  setUp(ValidationDI.reset);
  tearDown(ValidationDI.reset);

  List<ViolationCode> codesOf(ValidationReport report) =>
      report.violations.map((v) => v.code).toList();

  group('clean structural variants pass', () {
    test('ok: wrapping the tree in Center is a valid mutation', () async {
      final report = await validateFixture('ok');

      expect(report.violations, isEmpty);
      expect(report.isValid(strict: true), isTrue);
      expect(report.baseInstanceId, isNotNull);
      expect(report.mutationInstanceId, isNotNull);
    });

    test('imports_reordered: reordering imports is not a violation', () async {
      final report = await validateFixture('imports_reordered');

      expect(codesOf(report), isNot(contains(ViolationCode.importsChanged)));
      expect(report.isValid(strict: true), isTrue);
    });
  });

  group('tangled mutations are rejected', () {
    test('imports_changed: a new dart:math import is caught', () async {
      final report = await validateFixture('imports_changed');

      expect(codesOf(report), contains(ViolationCode.importsChanged));
      expect(report.isValid(strict: false), isFalse);
    });

    test('seed_changed: initState seeding 500 instead of 10 items', () async {
      final report = await validateFixture('seed_changed');

      expect(codesOf(report), contains(ViolationCode.seedsChanged));
      expect(report.isValid(strict: false), isFalse);
    });

    test('content_changed: Text label edit is content drift', () async {
      final report = await validateFixture('content_changed');

      expect(codesOf(report), contains(ViolationCode.contentDrift));
      expect(report.isValid(strict: false), isFalse);
    });

    test('content_duplicated: duplicating an existing Text label is caught '
        '(multiset, not set)', () async {
      final report = await validateFixture('content_duplicated');

      expect(codesOf(report), contains(ViolationCode.contentDrift));
    });

    test('noncompiling: undefined symbol yields doesNotCompile with the '
        'analyzer message', () async {
      final report = await validateFixture('noncompiling');

      expect(codesOf(report), contains(ViolationCode.doesNotCompile));
      final violation = report.violations.firstWhere(
        (v) => v.code == ViolationCode.doesNotCompile,
      );
      expect(violation.severity, Severity.hard);
    });

    test('forbidden_async: async/await/Future helper is rejected', () async {
      final report = await validateFixture('forbidden_async');

      expect(codesOf(report), contains(ViolationCode.forbiddenConstruct));
      expect(report.isValid(strict: false), isFalse);
    });

    test('noop: byte-identical mutation is rejected', () async {
      final report = await validateFixture('noop');

      expect(codesOf(report), contains(ViolationCode.noOp));
      expect(report.isValid(strict: false), isFalse);
    });
  });
}
