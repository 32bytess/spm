import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/screening/domain/entities/screen_report.dart';

/// `.spm/screen/` at the repository root: one JSONL file of analysis rows per
/// snapshot, plus `index.json` listing them.
///
/// Plain text on purpose, so a team can commit the directory and share its
/// baselines, or ignore it and keep them local.
class SnapshotStore {
  final String directory;

  SnapshotStore(String repoRoot)
    : directory = p.join(repoRoot, '.spm', 'screen');

  File get _index => File(p.join(directory, 'index.json'));

  List<Snapshot> list() {
    if (!_index.existsSync()) return [];
    final json = jsonDecode(_index.readAsStringSync()) as Map<String, dynamic>;
    return (json['snapshots'] as List)
        .cast<Map<String, dynamic>>()
        .map(Snapshot.fromJson)
        .toList();
  }

  /// Writes the rows sorted by scope, replacing any snapshot with the same id.
  void write(
    Snapshot snapshot,
    List<JsonRecord> rows,
    String Function(JsonRecord) key,
  ) {
    Directory(directory).createSync(recursive: true);
    final sorted = [...rows]..sort((a, b) => key(a).compareTo(key(b)));
    File(
      p.join(directory, '${snapshot.id}.jsonl'),
    ).writeAsStringSync(sorted.map((r) => '${jsonEncode(r)}\n').join());
    final kept = list().where((s) => s.id != snapshot.id).toList()
      ..add(snapshot)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _index.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'snapshots': [for (final s in kept) s.toJson()],
      }),
    );
  }

  List<JsonRecord> rows(Snapshot snapshot) =>
      File(p.join(directory, '${snapshot.id}.jsonl'))
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as JsonRecord)
          .toList();
}
