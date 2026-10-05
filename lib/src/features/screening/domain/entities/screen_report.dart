/// One stored extraction: the rows of `spm analyze` for a commit.
class Snapshot {
  /// File stem under `.spm/screen/`, e.g. `3f2a9c01b7de` or `3f2a9c01b7de-dirty`.
  final String id;
  final String commit;
  final bool dirty;
  final DateTime createdAt;
  final String spmVersion;

  /// Analysed directories, relative to the repository root.
  final List<String> directories;

  Snapshot({
    required this.id,
    required this.commit,
    required this.dirty,
    required this.createdAt,
    required this.spmVersion,
    required this.directories,
  });

  factory Snapshot.fromJson(Map<String, dynamic> json) => Snapshot(
    id: json['id'] as String,
    commit: json['commit'] as String,
    dirty: json['dirty'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
    spmVersion: json['spmVersion'] as String,
    directories: (json['directories'] as List).cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'commit': commit,
    'dirty': dirty,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'spmVersion': spmVersion,
    'directories': directories,
  };
}

/// A rebuild scope present in both versions whose metrics moved.
class ScopeComparison {
  final String key;

  /// After minus before, for every metric that moved.
  final Map<String, num> delta;

  /// Null when none of the model's features moved: the extractor saw an edit
  /// but nothing the rule or the forest reads.
  final bool? ruleSlower;
  final double? forestScore;

  /// Share of trees voting "slower" for the edit as written, and for the same
  /// edit reversed. [forestScore] is the first minus the second.
  final double? forestForward;
  final double? forestReverse;
  final List<String> warnings;

  ScopeComparison({
    required this.key,
    required this.delta,
    required this.ruleSlower,
    required this.forestScore,
    this.forestForward,
    this.forestReverse,
    required this.warnings,
  });

  bool get scored => ruleSlower != null;
  bool get forestSlower => (forestScore ?? 0) > 0;

  Map<String, dynamic> toJson() => {
    'scope': key,
    'delta': delta,
    'countRule': ruleSlower == null
        ? null
        : (ruleSlower! ? 'slower' : 'not slower'),
    'forest': forestScore == null
        ? null
        : {
            'score': forestScore,
            'forward': forestForward,
            'reverse': forestReverse,
            'verdict': forestScore! > 0
                ? 'slower'
                : (forestScore! < 0 ? 'faster' : 'no direction'),
          },
    'warnings': warnings,
  };
}

class ScreenReport {
  final Snapshot baseline;
  final String baselineReason;
  final List<ScopeComparison> changed;
  final List<String> added;
  final List<String> removed;
  final int unchanged;

  ScreenReport({
    required this.baseline,
    required this.baselineReason,
    required this.changed,
    required this.added,
    required this.removed,
    required this.unchanged,
  });

  Map<String, dynamic> toJson() => {
    'baseline': baseline.toJson(),
    'baselineReason': baselineReason,
    'changed': [for (final c in changed) c.toJson()],
    'added': added,
    'removed': removed,
    'unchanged': unchanged,
  };
}
