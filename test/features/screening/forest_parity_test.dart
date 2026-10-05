import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/screening/data/forest_loader.dart';
import 'package:spm/src/features/screening/domain/count_rule.dart';
import 'package:test/test.dart';

/// The Dart port must score exactly what the frozen Python forest scores.
///
/// `forest_parity_vectors.json` holds the thesis's 819 controlled-variant
/// pairs and 110 decisive real-history pairs, each with the Python
/// antisymmetric score and the measured label, written by
/// `analysis_v2/export_forest_for_spm.py`.
void main() {
  final parity =
      jsonDecode(
            File(
              p.join(
                'test',
                'fixtures',
                'screening',
                'forest_parity_vectors.json',
              ),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final forest = ForestLoader.load();
  final features = (parity['features'] as List).cast<String>();

  test('the embedded model reads the same features in the same order', () {
    expect(forest.features, equals(features));
  });

  for (final set in ['arm1_mut_mut', 'arm2_decisive']) {
    test('$set: every Dart score equals the Python score', () {
      final data = parity[set] as Map<String, dynamic>;
      final xs = (data['x'] as List).cast<List>();
      final ss = (data['s'] as List).cast<num>();
      for (var i = 0; i < xs.length; i++) {
        expect(
          forest.score(xs[i].cast<num>()),
          closeTo(ss[i].toDouble(), 1e-12),
          reason: 'pair $i',
        );
      }
    });
  }

  test('real-history pairs: forest 86 / 110, count rule 97 / 110', () {
    final data = parity['arm2_decisive'] as Map<String, dynamic>;
    final xs = (data['x'] as List).cast<List>();
    final ys = (data['y'] as List).cast<int>();
    var forestRight = 0;
    var ruleRight = 0;
    for (var i = 0; i < xs.length; i++) {
      final x = xs[i].cast<num>();
      final slower = ys[i] == 1;
      if ((forest.score(x) > 0) == slower) forestRight++;
      final delta = {
        for (var j = 0; j < features.length; j++) features[j]: x[j],
      };
      if (CountRule.slower(delta) == slower) ruleRight++;
    }
    expect(xs, hasLength(110));
    expect(forestRight, equals(86));
    expect(ruleRight, equals(97));
  });

  test('the score flips sign when the edit is reverted', () {
    final x = ((parity['arm2_decisive'] as Map)['x'] as List).first as List;
    final d = x.cast<num>();
    expect(
      forest.score([for (final v in d) -v]),
      closeTo(-forest.score(d), 1e-15),
    );
  });
}
