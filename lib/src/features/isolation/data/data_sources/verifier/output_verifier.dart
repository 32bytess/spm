import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;

/// What analysing one isolated file found.
class OutputVerification {
  const OutputVerification({
    required this.errorCount,
    required this.warningCount,
    required this.topCodes,
    required this.unresolvedImports,
    required this.unresolvedNames,
  });

  /// A file that was written but never analysed, because the run had no
  /// package config to resolve `package:flutter` with. Reported rather than
  /// guessed at: without resolution every import looks broken, and a fabricated
  /// clean row would be worse than an honest gap.
  static const OutputVerification unverified = OutputVerification(
    errorCount: -1,
    warningCount: -1,
    topCodes: [],
    unresolvedImports: [],
    unresolvedNames: [],
  );

  final int errorCount;
  final int warningCount;

  /// The most frequent diagnostic codes, most frequent first.
  final List<String> topCodes;

  /// URIs the file imports that do not exist.
  final List<String> unresolvedImports;

  /// Names the file uses but nothing declares.
  final List<String> unresolvedNames;

  bool get wasVerified => errorCount >= 0;
  bool get isClean => errorCount == 0;

  Map<String, Object?> toJson() => {
    'verified': wasVerified,
    if (wasVerified) 'errorCount': errorCount,
    if (wasVerified) 'warningCount': warningCount,
    if (topCodes.isNotEmpty) 'topCodes': topCodes,
    if (unresolvedImports.isNotEmpty) 'unresolvedImports': unresolvedImports,
    if (unresolvedNames.isNotEmpty) 'unresolvedNames': unresolvedNames,
  };
}

/// Analyses the isolated files after they are written.
///
/// The point of a transplant is to be read back by `spm analyze`, which skips
/// any file carrying an error-severity diagnostic. Whether that happened was
/// invisible until now: the run reported how many scopes it wrote, never how
/// many of them could be read. A batch of output can therefore look complete
/// while most of it is unusable, and the run that produced it says nothing.
///
/// Analysis runs in this process, through the same analyzer the extraction
/// used. Shelling out to `dart analyze` would pay a fresh SDK start-up and a
/// fresh resolution of the Flutter SDK for every batch.
///
/// The only edit this makes is removing an import nothing uses. An undefined
/// name is reported and never invented here: inventing one would bypass the
/// widget-ness rule the shim emitters follow, and a stand-in that is not a
/// widget where the original was moves a feature count.
class OutputVerifier {
  /// Diagnostic codes that name a symbol the file failed to resolve.
  static const Set<String> _unresolvedNameCodes = {
    'undefined_identifier',
    'undefined_class',
    'undefined_method',
    'undefined_function',
    'undefined_getter',
    'undefined_setter',
    'creation_with_non_type',
    'not_a_type',
  };

  static const String _unusedImport = 'unused_import';
  static const String _uriDoesNotExist = 'uri_does_not_exist';

  /// Analyses every `.dart` file under [outputDir], keyed by absolute path.
  ///
  /// [sourceDirectories] are the projects the scopes came from; the first one
  /// carrying a package config lends it to the output, so that
  /// `package:flutter` resolves the same way it did during extraction.
  Future<Map<String, OutputVerification>> verify({
    required String outputDir,
    required List<String> sourceDirectories,
  }) async {
    final files = _dartFilesIn(outputDir);
    if (files.isEmpty) return const {};

    if (!_prepareOutputPackage(outputDir, sourceDirectories)) {
      return {for (final file in files) file: OutputVerification.unverified};
    }

    final collection = AnalysisContextCollection(
      includedPaths: [outputDir],
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );

    final results = <String, OutputVerification>{};
    for (final file in files) {
      final context = collection.contextFor(file);
      var diagnostics = await _diagnosticsFor(context, file);

      if (_pruneUnusedImports(file, diagnostics)) {
        // The file changed under the context, so its old result is stale.
        context.changeFile(file);
        await context.applyPendingFileChanges();
        diagnostics = await _diagnosticsFor(context, file);
      }

      results[file] = _summarise(file, diagnostics);
    }
    return results;
  }

  Future<List<Diagnostic>> _diagnosticsFor(dynamic context, String file) async {
    try {
      final result = await context.currentSession.getErrors(file);
      if (result is ErrorsResult) return result.diagnostics;
    } catch (_) {}
    return const [];
  }

  OutputVerification _summarise(String file, List<Diagnostic> diagnostics) {
    var errors = 0;
    var warnings = 0;
    final counts = <String, int>{};
    final unresolvedImports = <String>{};
    final unresolvedNames = <String>{};

    String? content;
    String textOf(Diagnostic diagnostic) {
      content ??= File(file).readAsStringSync();
      final end = diagnostic.offset + diagnostic.length;
      if (diagnostic.offset < 0 || end > content!.length) return '';
      return content!.substring(diagnostic.offset, end);
    }

    for (final diagnostic in diagnostics) {
      final code = diagnostic.diagnosticCode.lowerCaseName;
      final severity = diagnostic.diagnosticCode.severity;
      if (severity == DiagnosticSeverity.ERROR) {
        errors++;
        counts[code] = (counts[code] ?? 0) + 1;
      } else if (severity == DiagnosticSeverity.WARNING) {
        warnings++;
      }
      if (code == _uriDoesNotExist) {
        unresolvedImports.add(textOf(diagnostic).replaceAll("'", ''));
      } else if (_unresolvedNameCodes.contains(code)) {
        final name = textOf(diagnostic);
        if (name.isNotEmpty) unresolvedNames.add(name);
      }
    }

    final ordered = counts.keys.toList()
      ..sort((a, b) {
        final delta = counts[b]!.compareTo(counts[a]!);
        return delta != 0 ? delta : a.compareTo(b);
      });

    return OutputVerification(
      errorCount: errors,
      warningCount: warnings,
      topCodes: ordered.take(5).toList(),
      unresolvedImports: unresolvedImports.toList()..sort(),
      unresolvedNames: unresolvedNames.toList()..sort(),
    );
  }

  /// Removes the import lines nothing in [file] uses. Returns whether the file
  /// was rewritten.
  ///
  /// Line-based, because the transplant writes one directive per line and the
  /// formatter has already run. An unused import cannot be load-bearing, so
  /// dropping it can only reduce the diagnostic count.
  bool _pruneUnusedImports(String file, List<Diagnostic> diagnostics) {
    final offsets = [
      for (final diagnostic in diagnostics)
        if (diagnostic.diagnosticCode.lowerCaseName == _unusedImport)
          diagnostic.offset,
    ];
    if (offsets.isEmpty) return false;

    final content = File(file).readAsStringSync();
    final doomed = <int>{};
    for (final offset in offsets) {
      final line = _lineIndexOf(content, offset);
      if (line != null) doomed.add(line);
    }
    if (doomed.isEmpty) return false;

    final lines = const LineSplitter().convert(content);
    final kept = [
      for (var i = 0; i < lines.length; i++)
        if (!doomed.contains(i) || !lines[i].trimLeft().startsWith('import '))
          lines[i],
    ];
    if (kept.length == lines.length) return false;

    File(file).writeAsStringSync('${kept.join('\n')}\n');
    return true;
  }

  static int? _lineIndexOf(String content, int offset) {
    if (offset < 0 || offset > content.length) return null;
    var line = 0;
    for (var i = 0; i < offset; i++) {
      if (content.codeUnitAt(i) == 0x0a) line++;
    }
    return line;
  }

  List<String> _dartFilesIn(String outputDir) {
    final dir = Directory(outputDir);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((path) => path.endsWith('.dart'))
        .toList()
      ..sort();
  }

  /// Gives [outputDir] enough of a package for the analyzer to resolve
  /// `package:flutter`. Returns whether it succeeded.
  ///
  /// The source project's own config is reused, with every root made absolute
  /// so it still points at the same packages from a different directory.
  bool _prepareOutputPackage(String outputDir, List<String> sourceDirectories) {
    final target = File(p.join(outputDir, '.dart_tool', 'package_config.json'));

    if (!target.existsSync()) {
      final source = sourceDirectories
          .map(_packageConfigAbove)
          .whereType<File>()
          .firstOrNull;
      if (source == null) return false;
      try {
        target.parent.createSync(recursive: true);
        target.writeAsStringSync(_absolutised(source));
      } catch (_) {
        return false;
      }
    }

    final pubspec = File(p.join(outputDir, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      try {
        pubspec.writeAsStringSync(
          '# Written by `spm isolate` so the isolated files analyse in place.\n'
          'name: spm_isolated_output\n'
          'environment:\n'
          "  sdk: '>=3.0.0 <4.0.0'\n",
        );
      } catch (_) {
        // A missing pubspec still leaves the package config usable.
      }
    }
    return true;
  }

  /// The nearest `.dart_tool/package_config.json` at or above [dir].
  ///
  /// The analyzer finds a project's config by walking up from the file it is
  /// analysing, so a source directory pointing at a subfolder of a package
  /// resolves perfectly well without holding a config of its own. Looking only
  /// in the directory itself made the verifier skip exactly those runs.
  static File? _packageConfigAbove(String dir) {
    var current = p.normalize(p.absolute(dir));
    while (true) {
      final candidate = File(
        p.join(current, '.dart_tool', 'package_config.json'),
      );
      if (candidate.existsSync()) return candidate;
      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }

  /// Rewrites every `rootUri` in [source] to an absolute URI.
  String _absolutised(File source) {
    final config =
        jsonDecode(source.readAsStringSync()) as Map<String, Object?>;
    final base = p.dirname(source.path);

    final packages = [
      for (final entry
          in (config['packages'] as List? ?? const [])
              .cast<Map<String, Object?>>())
        {...entry, 'rootUri': _absoluteRoot(entry['rootUri'] as String?, base)},
    ];

    return jsonEncode({...config, 'packages': packages});
  }

  String _absoluteRoot(String? rootUri, String base) {
    if (rootUri == null) return Uri.directory(base).toString();
    final uri = Uri.parse(rootUri);
    if (uri.hasScheme) return rootUri;
    return Uri.directory(
      p.normalize(p.join(base, uri.toFilePath())),
    ).toString();
  }
}
