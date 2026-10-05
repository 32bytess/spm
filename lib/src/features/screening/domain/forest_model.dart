/// The frozen random forest of the thesis, ported for inference only.
///
/// Trained in Python (scikit-learn, 500 trees, `max_features="sqrt"`) on the
/// eight feature deltas of the controlled-variant pairs, then exported tree by
/// tree. Nothing here learns: [score] walks the same thresholds the pickle
/// walks, so the port is checked against the Python scores to 1e-12 in
/// `test/features/screening/forest_parity_test.dart`.
class ForestModel {
  /// Feature names, in the column order the trees index.
  final List<String> features;
  final List<_Tree> _trees;

  ForestModel._(this.features, this._trees);

  factory ForestModel.fromJson(Map<String, dynamic> json) {
    final trees = (json['trees'] as List)
        .cast<Map<String, dynamic>>()
        .map(_Tree.fromJson)
        .toList(growable: false);
    return ForestModel._((json['features'] as List).cast<String>(), trees);
  }

  /// Mean leaf share of "slower" over the trees, for one oriented delta.
  double probability(List<num> delta) {
    var sum = 0.0;
    for (final tree in _trees) {
      sum += tree.leafShare(delta);
    }
    return sum / _trees.length;
  }

  /// The antisymmetric score `f(D) - f(-D)`: positive means "after is slower".
  ///
  /// Reading the delta both ways makes the verdict flip exactly when the edit
  /// is reverted, which is what a pair of versions with no privileged
  /// baseline needs.
  double score(List<num> delta) {
    final negated = [for (final d in delta) -d];
    return probability(delta) - probability(negated);
  }
}

class _Tree {
  final List<int> feature;
  final List<double> threshold;
  final List<int> left;
  final List<int> right;
  final List<double> pSlower;

  _Tree(this.feature, this.threshold, this.left, this.right, this.pSlower);

  factory _Tree.fromJson(Map<String, dynamic> json) => _Tree(
    (json['feature'] as List).cast<int>(),
    [for (final t in json['threshold'] as List) (t as num).toDouble()],
    (json['left'] as List).cast<int>(),
    (json['right'] as List).cast<int>(),
    [for (final v in json['pSlower'] as List) (v as num).toDouble()],
  );

  double leafShare(List<num> delta) {
    var node = 0;
    while (left[node] != -1) {
      node = delta[feature[node]] <= threshold[node] ? left[node] : right[node];
    }
    return pSlower[node];
  }
}
