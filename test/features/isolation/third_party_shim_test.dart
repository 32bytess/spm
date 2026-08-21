import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:test/test.dart';

import 'utils/temp_project.dart';

/// Exercises the third-party half of the shim policy end to end.
///
/// The rest of the isolation fixtures live inside this package, so every symbol
/// they reach is either project-local or `package:flutter`. Neither reaches the
/// import gate in `dependency_extractor_visitor.dart`, which is where a
/// genuinely third-party name is dropped. This suite builds a throwaway project
/// with a real `package:` dependency outside it so that gate actually fires.
///
/// The scope is written at run time rather than checked in, for the same reason
/// as the legacy-syntax suite: a checked-in file importing `package:ui_kit`
/// resolves for nobody but this test, and `dart pub publish` reports it as a
/// dependency the package does not declare. The `ui_kit` package itself stays
/// on disk, since it has to be resolvable through a package config.
const String _scopeSource = '''
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

class ThirdPartyWidgetHost extends StatefulWidget {
  const ThirdPartyWidgetHost({super.key});

  @override
  State<ThirdPartyWidgetHost> createState() => ThirdPartyWidgetHostState();
}

class ThirdPartyWidgetHostState extends State<ThirdPartyWidgetHost> {
  static const FancySpec _spec = FancySpec(weight: 2);

  @override
  Widget build(BuildContext context) => Column(
    children: [const FancyButton(label: 'go'), Text('\${_spec.weight}')],
  );
}
''';

void main() {
  late TempProject project;
  late String outputDir;
  late String isolated;

  setUpAll(() async {
    final fixtures = p.absolute('test/fixtures/isolation_third_party');
    project = TempProject.create(
      sources: {'scope.dart': _scopeSource},
      extraPackages: {'ui_kit': p.join(fixtures, 'ui_kit')},
      prefix: 'spm_third_party',
    );
    outputDir = Directory.systemTemp.createTempSync('spm_third_party_out').path;

    await IsolationDataSourceImpl()
        .isolate(directories: [project.path], outputDir: outputDir)
        .drain();

    isolated = Directory(p.join(outputDir, 'State'))
        .listSync(recursive: false)
        .whereType<File>()
        .firstWhere((f) => f.path.contains('ThirdPartyWidgetHostState'))
        .readAsStringSync();
  });

  tearDownAll(() {
    project.delete();
    final dir = Directory(outputDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('never imports the third-party package back', () {
    // Importing it is what the gate exists to prevent. The isolated file is
    // meant to stand alone against the Flutter SDK.
    expect(isolated, isNot(contains('package:ui_kit')));
  });

  test('a third-party widget keeps Widget in its supertype chain', () {
    // The single property a shim has to preserve. `BuildMetricsVisitor`
    // classifies `FancyButton(...)` by walking the resolved chain for `Widget`,
    // so a bare `class FancyButton {}` resolves cleanly and is then counted in
    // valueObjectAllocCount instead of widgetCount.
    expect(isolated, contains('class FancyButton extends StatelessWidget'));
  });

  test('a third-party value object gains no Widget supertype', () {
    // The other direction of the same mistake. fl_chart's FlSpot is the real
    // case: it is never in the tree, and giving it a Widget supertype would
    // invent widgets that were never built.
    expect(isolated, contains('class FancySpec'));
    expect(isolated, isNot(contains('class FancySpec extends')));
  });

  test('a shimmed widget keeps the constructor the scope calls, as const', () {
    // `const FancyButton(label: 'go')` is a constant expression at the use
    // site; a stand-in without a const constructor turns it into
    // INVALID_CONSTANT, which is an error and so still skips the file.
    expect(isolated, contains('const FancyButton('));
    expect(isolated, contains('const FancySpec('));
  });

  test('a shimmed widget carries no build body of its own', () {
    // Stated as a limitation rather than a goal: analyzing the original
    // project walks `FancyButton.build` and counts the `Text` inside it. A shim
    // cannot, so an isolated scope using a third-party widget reports a smaller
    // tree than the same scope measured in place. The assertion pins the
    // behaviour so the difference stays visible.
    expect(isolated, contains('const SizedBox.shrink()'));
    expect(isolated, isNot(contains('Text(label)')));
  });

  test('shimmed members are limited to the ones the scope reaches', () {
    expect(isolated, contains('int get weight'));
    expect(isolated, isNot(contains('String get label')));
  });
}
