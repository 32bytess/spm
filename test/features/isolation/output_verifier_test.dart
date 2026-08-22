import 'dart:convert';
import 'dart:io';

import 'package:spm/src/features/isolation/data/data_sources/verifier/output_verifier.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('a file that was not analysed never reads as clean', () {
    test('the unverified verdict is not a clean verdict', () {
      const verdict = OutputVerification.unverified;

      // Anything reading `errorCount` back off the mapping row has to be able
      // to tell these two apart. Zero errors means analysed and found nothing;
      // unverified means the question was never answered.
      expect(verdict.wasVerified, isFalse);
      expect(verdict.isClean, isFalse);

      final json = verdict.toJson();
      expect(json['verified'], isFalse);
      // No count is reported for a file that was never counted. A `0` here
      // would read as a clean file.
      expect(json.containsKey('errorCount'), isFalse);
      expect(json.containsKey('warningCount'), isFalse);
    });

    test('output with no package config anywhere is unverified, not clean', () async {
      // `Directory.systemTemp` sits outside any package, so nothing above the
      // output directory can lend it a package config and `package:flutter`
      // cannot resolve. Every verdict in here has to be unverified.
      final outputDir = Directory.systemTemp.createTempSync('spm_verify_test');
      addTearDown(() => outputDir.deleteSync(recursive: true));

      final sourceDir = Directory.systemTemp.createTempSync('spm_verify_src');
      addTearDown(() => sourceDir.deleteSync(recursive: true));

      final file = File(p.join(outputDir.path, 'scope.dart'))
        ..writeAsStringSync(
          "import 'package:flutter/material.dart';\n"
          'class GeneratedWidget extends StatelessWidget {\n'
          '  const GeneratedWidget({super.key});\n'
          '  @override\n'
          '  Widget build(BuildContext context) => const SizedBox();\n'
          '}\n',
        );

      final results = await OutputVerifier().verify(
        outputDir: outputDir.path,
        sourceDirectories: [sourceDir.path],
      );

      final verdict = results[file.path];
      expect(verdict, isNotNull);
      expect(verdict!.wasVerified, isFalse);
      expect(verdict.isClean, isFalse);
    });
  });

  group('the verifier does not rewrite what it reads', () {
    test('an unused import survives verification', () async {
      // Pruning used to happen here, line by line, which cannot survive a `show`
      // clause the formatter has wrapped. The export step prunes over an AST
      // instead, so the transplant is left exactly as it was written.
      final outputDir = Directory.systemTemp.createTempSync('spm_prune_test');
      addTearDown(() => outputDir.deleteSync(recursive: true));

      // A package config good enough to resolve `dart:` but nothing else, so the
      // file analyses rather than falling to the unverified path.
      File(p.join(outputDir.path, '.dart_tool', 'package_config.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'configVersion': 2, 'packages': []}));

      const source =
          "import 'dart:math';\n"
          "import 'dart:convert';\n"
          'int answer() => 42;\n';
      final file = File(p.join(outputDir.path, 'scope.dart'))
        ..writeAsStringSync(source);

      await OutputVerifier().verify(
        outputDir: outputDir.path,
        sourceDirectories: [outputDir.path],
      );

      expect(file.readAsStringSync(), source);
    });
  });
}
