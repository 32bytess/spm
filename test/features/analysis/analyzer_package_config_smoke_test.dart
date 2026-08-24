import 'package:analyzer/file_system/physical_file_system.dart';
// The point of the test is that this import keeps working.
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Guards the one analyzer API `spm analyze` reaches past the public surface.
///
/// Reading a library outside the analysed roots needs a collection built
/// against the application's own `package_config.json`, and the parameter that
/// takes one lives on `AnalysisContextCollectionImpl` rather than on the public
/// `AnalysisContextCollection` factory, which exposes only `includedPaths`,
/// `excludedPaths`, `resourceProvider` and `sdkPath`.
///
/// This package allows analyzer 13 through 14, and both carry the parameter. If
/// it is renamed or moved, `TreeExtractor` stops reading package libraries and
/// every third-party subtree silently vanishes from the in-place rows. That is
/// a wrong number rather than a missing one, so it fails here first.
void main() {
  test('AnalysisContextCollectionImpl still takes packageConfigFile', () {
    final root = p.normalize(p.absolute('lib'));
    final collection = AnalysisContextCollectionImpl(
      includedPaths: [root],
      packageConfigFile: p.normalize(
        p.absolute(p.join('.dart_tool', 'package_config.json')),
      ),
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );
    addTearDown(collection.dispose);
    expect(collection.contexts, isNotEmpty);
  });
}
