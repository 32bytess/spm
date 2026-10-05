import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/core/injection/cli_service_locator.dart';
import 'package:spm/src/core/loggor/logger.dart';
import 'package:spm/src/core/presentation/directory_arguments.dart';
import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/analysis/data/models/analysis_result_model.dart';
import 'package:spm/src/features/analysis/domain/entities/analysis_event.dart';
import 'package:spm/src/features/analysis/domain/use_cases/analyze_use_case.dart';
import 'package:spm/src/features/screening/data/forest_loader.dart';
import 'package:spm/src/features/screening/data/git_info.dart';
import 'package:spm/src/features/screening/data/snapshot_store.dart';
import 'package:spm/src/features/screening/domain/entities/screen_report.dart';
import 'package:spm/src/features/screening/domain/use_cases/compare_use_case.dart';

/// Version stamped on every snapshot. A baseline written by a different
/// extractor version is compared with a warning, because an extractor change
/// moves the metrics with no code edit.
const screenSpmVersion = '0.8.0';

class ScreenCommand extends Command<int> {
  @override
  final name = 'screen';

  @override
  final description =
      'Screen code changes for likely rebuild-cost increases: store feature '
      'snapshots per commit and compare the working tree against one.';

  ScreenCommand({AnalyzeUseCase? analyzeUseCase}) {
    addSubcommand(SnapshotCommand(analyzeUseCase: analyzeUseCase));
    addSubcommand(CompareCommand(analyzeUseCase: analyzeUseCase));
  }
}

/// Shared by both subcommands: extract the current rows of the given
/// directories, keyed by paths relative to the repository root.
mixin _Extraction on Command<int>, DirectoryArguments {
  AnalyzeUseCase? get injectedAnalyzeUseCase;

  void addExtractionOptions() {
    argParser
      ..addOption(
        'file',
        abbr: 'f',
        help:
            'Keep only the scopes declared in this file (the directories are '
            'still analysed, so helpers and child widgets resolve).',
      )
      ..addOption(
        'package-config',
        help:
            'The resolved .dart_tool/package_config.json to analyse against, '
            'as for `spm analyze`.',
      );
  }

  Future<(GitInfo, List<String>, List<JsonRecord>)?> extract() async {
    final dirs = readDirectories(label: 'Directories');
    final git = await GitInfo.of(dirs.first);
    if (git == null) {
      SpmLogger.logMessage(
        '${dirs.first} is not inside a git repository; `spm screen` keys '
        'snapshots by commit.',
        isError: true,
      );
      return null;
    }
    final relDirs = [
      for (final d in dirs)
        p.posix.joinAll(p.split(p.relative(d, from: git.root))),
    ];
    final file = argResults!['file'] as String?;
    final fileRel = file == null
        ? null
        : p.posix.joinAll(
            p.split(p.relative(p.absolute(file), from: git.root)),
          );

    final analyzer = injectedAnalyzeUseCase ?? AnalysisDI.analyzeUseCase;
    final rows = <JsonRecord>[];
    var failed = false;
    var skipped = 0;
    for (var i = 0; i < dirs.length; i++) {
      await for (final event in analyzer.call([
        dirs[i],
      ], packageConfigFile: argResults!['package-config'] as String?)) {
        event.fold(
          (failure) {
            failed = true;
            SpmLogger.logMessage(
              'Analysis error: ${failure.message}',
              isError: true,
            );
          },
          (result) {
            if (result is AnalysisDataEvent) {
              final row = AnalysisResultModel.fromEntity(
                result.result,
              ).toJson();
              row['filePath'] = relDirs[i] == '.'
                  ? row['filePath']
                  : p.posix.join(relDirs[i], row['filePath'] as String);
              rows.add(row);
            } else if (result is AnalysisSummaryEvent) {
              skipped += result.filesSkipped;
            }
          },
        );
      }
    }
    if (failed) return null;
    if (skipped > 0) {
      // A file that does not compile emits no rows, so against a baseline its
      // scopes look removed rather than edited.
      SpmLogger.logMessage(
        'warning: $skipped file(s) skipped with compile errors; their scopes '
        'are missing from this extraction and will show as removed.',
        isError: true,
      );
    }
    final kept = fileRel == null
        ? rows
        : rows.where((r) => r['filePath'] == fileRel).toList();
    return (git, relDirs, kept);
  }
}

class SnapshotCommand extends Command<int>
    with DirectoryArguments, _Extraction {
  @override
  final AnalyzeUseCase? injectedAnalyzeUseCase;

  @override
  final name = 'snapshot';

  @override
  final description =
      'Extract rebuild-scope features and store them in .spm/screen/ under '
      'the current commit hash.';

  SnapshotCommand({AnalyzeUseCase? analyzeUseCase})
    : injectedAnalyzeUseCase = analyzeUseCase {
    addExtractionOptions();
  }

  @override
  Future<int> run() async {
    final extracted = await extract();
    if (extracted == null) return 1;
    final (git, relDirs, rows) = extracted;
    final short = git.head.substring(0, 12);
    final snapshot = Snapshot(
      id: git.dirty ? '$short-dirty' : short,
      commit: git.head,
      dirty: git.dirty,
      createdAt: DateTime.now().toUtc(),
      spmVersion: screenSpmVersion,
      directories: relDirs,
    );
    final store = SnapshotStore(git.root);
    store.write(snapshot, rows, CompareUseCase.scopeKey);
    SpmLogger.logMessage(
      'Stored ${rows.length} scopes as ${p.relative(store.directory, from: git.root)}/'
      '${snapshot.id}.jsonl${git.dirty ? ' (working tree has uncommitted changes)' : ''}.',
    );
    return 0;
  }
}

class CompareCommand extends Command<int> with DirectoryArguments, _Extraction {
  @override
  final AnalyzeUseCase? injectedAnalyzeUseCase;

  @override
  final name = 'compare';

  @override
  final description =
      'Compare the working tree against a stored snapshot and flag rebuild '
      'scopes whose change is likely to make a rebuild slower.';

  CompareCommand({AnalyzeUseCase? analyzeUseCase})
    : injectedAnalyzeUseCase = analyzeUseCase {
    addExtractionOptions();
    argParser
      ..addOption(
        'against',
        abbr: 'a',
        help:
            'Commit (or prefix) of the snapshot to compare against. Default: '
            'the newest snapshot of an ancestor of HEAD.',
      )
      ..addFlag('json', help: 'Print the report as JSON.', negatable: false)
      ..addOption(
        'fail-on',
        help: 'Exit with 1 when a scope is flagged slower by this verdict.',
        allowed: ['rule', 'forest', 'either', 'both'],
      );
  }

  @override
  Future<int> run() async {
    final extracted = await extract();
    if (extracted == null) return 1;
    final (git, _, after) = extracted;
    final store = SnapshotStore(git.root);
    final picked = await _pickBaseline(git, store.list());
    if (picked == null) return 1;
    final (baseline, reason) = picked;

    final warnings = <String>[
      if (baseline.spmVersion != screenSpmVersion)
        'baseline written by spm ${baseline.spmVersion}, now $screenSpmVersion: '
            'an extractor change can move metrics with no code edit',
      if (baseline.dirty)
        'baseline was taken from a working tree with uncommitted changes',
    ];
    final file = argResults!['file'] as String?;
    var before = store.rows(baseline);
    if (file != null) {
      final rel = p.posix.joinAll(
        p.split(p.relative(p.absolute(file), from: git.root)),
      );
      before = before.where((r) => r['filePath'] == rel).toList();
    }
    final report = CompareUseCase(ForestLoader.load()).call(
      baseline: baseline,
      baselineReason: reason,
      before: before,
      after: after,
      extraWarnings: warnings,
    );

    if (argResults!['json'] as bool) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(report.toJson()),
      );
    } else {
      _printReport(report);
    }
    return _exitCode(report, argResults!['fail-on'] as String?);
  }

  Future<(Snapshot, String)?> _pickBaseline(
    GitInfo git,
    List<Snapshot> all,
  ) async {
    if (all.isEmpty) {
      SpmLogger.logMessage(
        'No snapshot in .spm/screen/ yet. Run `spm screen snapshot <dirs>` on '
        'the version to compare against first.',
        isError: true,
      );
      return null;
    }
    final against = argResults!['against'] as String?;
    if (against != null) {
      final hits =
          all
              .where((s) => s.commit.startsWith(against) || s.id == against)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (hits.isEmpty) {
        SpmLogger.logMessage('No snapshot for commit $against.', isError: true);
        return null;
      }
      final clean = hits.where((s) => !s.dirty);
      return (
        clean.isNotEmpty ? clean.first : hits.first,
        'requested with --against',
      );
    }
    // A clean snapshot of HEAD itself is a baseline only when there are
    // uncommitted edits to screen; otherwise it would compare HEAD with HEAD.
    final candidates = <Snapshot>[];
    for (final s in all.where((s) => !s.dirty)) {
      if (s.commit == git.head && !git.dirty) continue;
      if (await git.isAncestorOfHead(s.commit)) candidates.add(s);
    }
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final s = candidates.first;
      return (
        s,
        s.commit == git.head
            ? 'snapshot of HEAD; screening the uncommitted changes'
            : 'newest snapshot of an ancestor of HEAD',
      );
    }
    final rest = all.where((s) => s.commit != git.head || git.dirty).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (rest.isEmpty) {
      SpmLogger.logMessage(
        'The only snapshot is of HEAD and the working tree is clean: nothing '
        'to compare. Snapshot an earlier commit, or pass --against.',
        isError: true,
      );
      return null;
    }
    return (rest.first, 'newest snapshot; it is NOT an ancestor of HEAD');
  }

  /// Readable names for the per-scope metrics, in report order.
  static const _labels = {
    'treeNonConstWidgetCount': 'non-const widgets',
    'treeConstWidgetCount': 'const widgets',
    'treeMaxWidgetNestingDepth': 'max widget nesting depth',
    'treeListRenderingStrategy': 'list rendering strategy',
    'rootBuildReturnsConstWidget': 'build returns a const widget',
    'helperReferenceCount': 'helper references',
    'usesLayoutDependentBuilder': 'layout-dependent builder',
    'treeCyclomaticComplexity': 'cyclomatic complexity',
    'treeIterationCount': 'iterations (loops, map)',
    'treeMaxIterationNestingDepth': 'max iteration nesting depth',
    'iterationWidgetCount': 'widgets built in iterations',
    'valueObjectAllocCount': 'value-object allocations',
    'helperWidgetCount': 'widgets in helpers',
    'helperMaxWidgetNestingDepth': 'max nesting depth in helpers',
  };

  void _printReport(ScreenReport r) {
    final out = stdout;
    final color = stdout.hasTerminal && stdout.supportsAnsiEscapes;
    String bold(String t) => color ? '\x1B[1m$t\x1B[0m' : t;
    String red(String t) => color ? '\x1B[1;31m$t\x1B[0m' : t;
    String green(String t) => color ? '\x1B[32m$t\x1B[0m' : t;
    String dim(String t) => color ? '\x1B[2m$t\x1B[0m' : t;
    String signed(num v) => v > 0 ? '+$v' : '$v';
    String pct(double v) => '${(v * 100).round()}%';

    final forestReads = ForestLoader.load().features.toSet();
    final b = r.baseline;
    final when = b.createdAt.toUtc().toIso8601String();
    out.writeln(
      'Baseline  ${b.commit.substring(0, 12)}${b.dirty ? ' (dirty)' : ''}, '
      '${when.substring(0, 10)} ${when.substring(11, 16)} UTC',
    );
    out.writeln('          ${r.baselineReason}');
    out.writeln(
      'Scopes    ${r.changed.length} changed, ${r.unchanged} unchanged, '
      '${r.added.length} added, ${r.removed.length} removed',
    );

    var ruleHits = 0, forestHits = 0, split = 0;
    for (final c in r.changed) {
      final hash = c.key.indexOf('#');
      final file = c.key.substring(0, hash);
      final scope = c.key.substring(hash + 1).split(':');
      out.writeln('');
      out.writeln(
        '${bold('== ${scope.length > 1 ? scope[1] : scope[0]}')}'
        '${dim('  (${scope[0]}, $file)')}',
      );

      out.writeln('   What changed (after minus before)');
      final width = c.delta.keys
          .map((k) => (_labels[k] ?? k).length)
          .fold(0, (a, n) => n > a ? n : a);
      for (final e in c.delta.entries) {
        final note = forestReads.contains(e.key) ? '' : dim('  not used');
        out.writeln(
          '     ${(_labels[e.key] ?? e.key).padRight(width)}  '
          '${signed(e.value).padLeft(4)}$note',
        );
      }

      if (!c.scored) {
        out.writeln(
          '   No verdict: only metrics that neither verdict reads moved.',
        );
      } else {
        final dc = c.delta['treeNonConstWidgetCount'] ?? 0;
        final why = dc > 0
            ? 'adds $dc non-const widget${dc == 1 ? '' : 's'}'
            : dc < 0
            ? 'removes ${-dc} non-const widget${dc == -1 ? '' : 's'}'
            : 'non-const widget count unchanged';
        final rule = c.ruleSlower!;
        out.writeln('');
        out.writeln(
          '   Count rule  ${rule ? red('LIKELY SLOWER') : green('not slower   ')}'
          '  $why',
        );

        final s = c.forestScore!;
        final fs = c.forestSlower;
        final verdict = s > 0
            ? red('LIKELY SLOWER')
            : (s < 0 ? green('likely faster') : 'no direction ');
        out.writeln(
          '   Forest      $verdict  ${pct(c.forestForward!)} of trees vote '
          '"slower" for this edit,',
        );
        out.writeln(
          '                              ${pct(c.forestReverse!)} for the '
          'same edit reversed',
        );
        out.writeln(
          dim(
            '                              margin '
            '${s >= 0 ? '+' : ''}${s.toStringAsFixed(2)} '
            '(-1 to +1, 0 = no direction)',
          ),
        );

        if (rule) ruleHits++;
        if (fs) forestHits++;
        out.writeln('');
        if (rule != fs) {
          split++;
          out.writeln(
            '${bold('   => The verdicts disagree.')} Measure this scope on a device.',
          );
        } else if (rule) {
          out.writeln(bold('   => Both verdicts say slower.'));
        } else {
          out.writeln('   => Neither verdict flags this edit as slower.');
        }
      }
      for (final w in c.warnings) {
        out.writeln('   warning: $w');
      }
    }

    if (r.added.isNotEmpty) {
      out.writeln('\nAdded, not scored:   ${r.added.join(', ')}');
    }
    if (r.removed.isNotEmpty) {
      out.writeln(
        '${r.added.isEmpty ? '\n' : ''}'
        'Removed, not scored: ${r.removed.join(', ')}',
      );
    }

    final scored = r.changed.where((c) => c.scored).length;
    out.writeln('');
    out.writeln(
      'Summary   $scored scored: count rule flags $ruleHits, forest flags '
      '$forestHits, they disagree on $split',
    );
    out.writeln(
      dim(
        '\nA verdict is a direction for the rebuild cost of one scope, never '
        'a build time.\nThe count rule did best on real edit history, the '
        'forest on controlled\nvariants. Neither replaces measuring on a '
        'device.',
      ),
    );
  }

  int _exitCode(ScreenReport r, String? failOn) {
    if (failOn == null) return 0;
    final hit = r.changed
        .where((c) => c.scored)
        .any(
          (c) => switch (failOn) {
            'rule' => c.ruleSlower!,
            'forest' => c.forestSlower,
            'both' => c.ruleSlower! && c.forestSlower,
            _ => c.ruleSlower! || c.forestSlower,
          },
        );
    return hit ? 1 : 0;
  }
}
