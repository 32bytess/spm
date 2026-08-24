import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/sdk_uris.dart';

/// The names `package:flutter/material.dart` puts in scope.
///
/// Every isolated file imports material, so a top-level declaration sharing a
/// name with something material exports shadows it for the whole file. Dart
/// reports nothing: the local declaration simply wins, and a `Card` from a
/// third-party package silently becomes the type every `Card(...)` in the
/// transplanted body constructs.
///
/// Standing the declaration in used to be the answer, and it was the answer
/// that loses the tree: an empty stand-in named `Text` costs the subtree under
/// every `Text(...)` in the transplanted body. The reasoning behind the guard
/// is sound and it survives, but shimming is not the only way to honour it.
/// The declaration is now carried under a mangled name ([mangle]), and only the
/// references whose resolved element is the shadowing one are rewritten. The
/// element model already tells the two apart, and the skeletoniser already
/// performs right-to-left source rewrites, so the guard stops costing a
/// subtree.
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

  /// The name a shadowing declaration is carried under.
  ///
  /// `$` is a legal identifier character and no Dart source in the wild spells
  /// a type this way, so the mangled name cannot collide with anything the
  /// transplant already carries.
  static String mangle(String name) => '$name\$spm';

  /// Whether [name] declared in [libraryUri] would shadow a Flutter name.
  ///
  /// SDK libraries are exempt, because Flutter's own `Card` is the one being
  /// protected.
  bool shadows(String? name, String? libraryUri) {
    if (name == null || libraryUri == null) return false;
    if (isSdkLibrary(libraryUri)) return false;
    return names.contains(name);
  }

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
