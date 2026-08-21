import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:spm/src/features/isolation/domain/entities/isolation_event.dart';
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
  final FancyController _controller = FancyController();

  @override
  void initState() {
    super.initState();
    _controller.tap();
  }

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
  late IsolationSummaryEvent summary;

  setUpAll(() async {
    final fixtures = p.absolute('test/fixtures/isolation_third_party');
    project = TempProject.create(
      sources: {'scope.dart': _scopeSource},
      extraPackages: {'ui_kit': p.join(fixtures, 'ui_kit')},
      prefix: 'spm_third_party',
    );
    outputDir = Directory.systemTemp.createTempSync('spm_third_party_out').path;

    final events = await IsolationDataSourceImpl()
        .isolate(directories: [project.path], outputDir: outputDir)
        .toList();
    summary = events.last as IsolationSummaryEvent;

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

  test('a small type comes across whole', () {
    // Referenced-only was the rule, and it produced stubs that carried
    // `removeListener` and not `addListener`, since the member set was decided
    // by whichever call sites the traversal reached. For a type this size,
    // rendering the declared surface costs a line and removes the whole class
    // of failure.
    expect(isolated, contains('int get weight'));
    expect(isolated, contains('String get label'));
  });

  test('a large type still carries only what the scope reaches', () {
    // The case the referenced-only rule was written for: rendering everything
    // turns a type the scope touches once into hundreds of lines.
    expect(isolated, contains('class FancyController'));
    expect(isolated, isNot(contains('void pad0()')));
  });

  test('an inherited member lands on the type the code names', () {
    // `tap` is declared on `FancyBase`, so keying it to its declaring class put
    // it on the wrong stand-in and left `_controller.tap()` undefined against
    // `FancyController`. The member is recorded from the receiver instead.
    expect(isolated, contains('void tap()'));
    expect(
      RegExp(r'class FancyController \{[^}]*void tap\(\)').hasMatch(isolated),
      isTrue,
      reason: 'tap must be declared on FancyController, not only on FancyBase',
    );
  });

  test('every isolated file analyses clean', () {
    // The property the whole feature exists for: `spm analyze` skips any file
    // carrying an error-severity diagnostic, so a scope that was written but
    // does not analyse contributes nothing.
    expect(summary.verifiedCount, greaterThan(0));
    expect(
      summary.cleanCount,
      summary.verifiedCount,
      reason: '${summary.errorCount} errors across the isolated files',
    );
  });
}
