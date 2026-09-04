import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;

/// The nearest `.dart_tool/package_config.json` at or above [dir].
///
/// The analyzer finds a project's config by walking up from the file it is
/// analysing, so a directory pointing at a subfolder of a package resolves
/// perfectly well without holding a config of its own. Looking only in the
/// directory itself is what made both callers here draw the wrong conclusion:
/// the verifier skipped exactly those runs, and the extractor reported them as
/// resolved.
File? packageConfigAbove(String dir) {
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

/// Whether [configFile] is the minimal stand-in `spm isolate` writes when it
/// cannot resolve a project's dependencies.
///
/// The synthesised config maps the project's own `package:` URI and no other,
/// so it resolves intra-project references and nothing third-party. Its
/// existence therefore says the opposite of what a real config says, and the
/// existence check that guards resolution has to be able to tell the two apart:
/// without this, the fallback that fires on the first run silently marks every
/// later run of the same checkout as resolved.
///
/// A config that cannot be read or parsed counts as synthesised. An unreadable
/// file is not evidence that resolution happened.
bool isSynthesisedConfig(File configFile) {
  try {
    final decoded = jsonDecode(configFile.readAsStringSync());
    if (decoded is! Map<String, Object?>) return true;
    return decoded['generator'] == 'spm';
  } catch (_) {
    return true;
  }
}

/// An analysis context collection over [includedPaths], on the physical file
/// system.
///
/// Every command that walks real files wants exactly this, and building it by
/// hand in five places meant five chances to pass a different resource
/// provider. It deliberately does not cover `tree_extractor`, which needs
/// `AnalysisContextCollectionImpl` so it can pin `packageConfigPath`, something
/// this factory does not expose.
AnalysisContextCollection contextCollectionFor(List<String> includedPaths) =>
    AnalysisContextCollection(
      includedPaths: includedPaths,
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );
