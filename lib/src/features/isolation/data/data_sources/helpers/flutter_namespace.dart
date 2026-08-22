import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/element/element.dart';

/// The names `package:flutter/material.dart` puts in scope.
///
/// Every isolated file imports material, so a top-level declaration sharing a
/// name with something material exports shadows it for the whole file. Dart
/// reports nothing: the local declaration simply wins, and a `Card` from a
/// third-party package silently becomes the type every `Card(...)` in the
/// transplanted body constructs.
///
/// A stand-in shadows just as thoroughly, so this does not stop the shadowing;
/// `ShimEmitter` says as much about its own output. What it stops is the shadow
/// carrying a body. An empty stand-in named `Text` costs the subtree under
/// every `Text(...)` in the transplanted body, which were leaves anyway. An
/// inlined third-party `Text` builds something, and that something is then
/// counted under every `Text(...)` in the body, including the ones that meant
/// Flutter's. Under-counting a name clash is recoverable; inventing widgets
/// under one is not, so a third-party declaration whose name is in here gets
/// the stand-in it got before this feature existed.
///
/// Read from the export namespace rather than by walking `exportedLibraries`,
/// for the reason spelled out on `_providesName` in
/// `dependency_extractor_visitor.dart`: that walk ignores `show` and `hide`,
/// and Flutter is built out of those clauses.
class FlutterNamespace {
  const FlutterNamespace._(this.names);

  /// Every name material exports, or empty when material would not resolve.
  ///
  /// Empty is the safe direction: it disables the guard rather than blocking
  /// every inline, so a run against a project whose Flutter SDK is missing
  /// behaves as though the guard were not there.
  final Set<String> names;

  static const FlutterNamespace empty = FlutterNamespace._({});

  bool contains(String name) => names.contains(name);

  /// Resolves material once and reads its export namespace.
  static Future<FlutterNamespace> load(AnalysisSession session) async {
    try {
      final result = await session.getLibraryByUri(
        'package:flutter/material.dart',
      );
      if (result is! LibraryElementResult) return empty;
      final dynamic namespace = result.element.exportNamespace;
      // `definedNames2` is the analyzer 13 spelling. This package allows up to
      // analyzer 15, so both are tried, as everywhere else in this feature.
      for (final read in [
        () => namespace.definedNames2,
        () => namespace.definedNames,
      ]) {
        try {
          final defined = read();
          if (defined is Map<String, Element>) {
            return FlutterNamespace._(defined.keys.toSet());
          }
        } catch (_) {}
      }
    } catch (_) {}
    return empty;
  }
}
