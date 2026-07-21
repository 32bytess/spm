import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:spm/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:spm/features/isolation/domain/entities/isolation_event.dart';

void main() {
  late IsolationDataSourceImpl dataSource;
  late String testProjectDir;
  late String outputDir;

  setUp(() {
    dataSource = IsolationDataSourceImpl();
    testProjectDir = p.absolute('test/fixtures/isolation');
    outputDir = Directory.systemTemp.createTempSync('spm_isolation_test').path;
  });

  tearDown(() {
    final dir = Directory(outputDir);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('should isolate all requested patterns and inline dependencies', () async {
    final stream = dataSource.isolate(
      directories: [testProjectDir],
      outputDir: outputDir,
    );

    final events = await stream.toList();
    final summary = events.last as IsolationSummaryEvent;

    expect(
      summary.isolatedCount,
      greaterThanOrEqualTo(5),
    ); // State, ConsumerWidget, 3 inlines

    // Check if State subclass (whole tree) was isolated correctly into 'State' directory (flat)
    final stateIsolatedFile = Directory(p.join(outputDir, 'State'))
        .listSync(recursive: false)
        .whereType<File>()
        .firstWhere((f) => f.path.contains('MyStatefulState'));

    final content = stateIsolatedFile.readAsStringSync();

    // Should contain the state class members
    expect(content, contains('int _counter = 0;'));
    expect(content, contains('void _increment()'));

    // Widget classes from cross-file deps are inlined
    expect(content, contains('class ExternalChild'));

    // Cross-file functions returning List<Widget> are included
    expect(content, contains('List<Widget> buildExternalItems'));

    // CustomPainter subclasses are included
    expect(content, contains('class ExternalPainter extends CustomPainter'));

    // ShapeBorder subclasses are included
    expect(content, contains('class ExternalShape extends ShapeBorder'));

    // Functions returning Decoration subtypes are included
    expect(content, contains('BoxDecoration buildExternalDecoration'));

    // Deep (level-2) widget reachable only through ExternalChild is included
    expect(content, contains('class DeepWidget'));

    // Non-widget at level 2 is excluded even though a widget references it
    expect(content, isNot(contains('class DeepService')));

    // StatefulWidget children must include their companion State class
    expect(content, contains('class ExternalStateful extends StatefulWidget'));
    expect(content, contains('class _ExternalStatefulState extends State<ExternalStateful>'));

    // Widget subclassing a custom base (not directly a Flutter widget) is detected
    expect(content, contains('class ExternalCard'));

    // Non-widget / non-enum cross-file decls are excluded (declarations, not references)
    expect(content, isNot(contains('const kExternalColor =')));
    expect(content, isNot(contains('void externalHelper()')));

    // Should be a StatefulWidget
    expect(content, contains('class GeneratedWidget extends StatefulWidget'));
  });

  test('should include external SDK and package imports', () async {
    final stream = dataSource.isolate(
      directories: [testProjectDir],
      outputDir: outputDir,
    );

    await stream.drain();

    final builderIsolatedFile = Directory(p.join(outputDir, 'State'))
        .listSync(recursive: false)
        .whereType<File>()
        .firstWhere((f) => f.path.contains('BuilderTestWidget'));

    final content = builderIsolatedFile.readAsStringSync();

    expect(content, contains("import 'package:flutter/cupertino.dart';"));
  });

  test('should replace image widgets with SizedBox but preserve other widgets', () async {
    final stream = dataSource.isolate(
      directories: [testProjectDir],
      outputDir: outputDir,
    );

    await stream.drain();

    final builderIsolatedFile = Directory(p.join(outputDir, 'State'))
        .listSync(recursive: false)
        .whereType<File>()
        .firstWhere((f) => f.path.contains('BuilderTestWidget'));

    final content = builderIsolatedFile.readAsStringSync();

    // Image.asset(...) should be replaced with the placeholder
    expect(content, contains("Image.asset('assets/placeholder.png')"));

    // Placeholder() is Flutter core (not in image set) — kept as-is
    expect(content, contains('const Placeholder()'));
  });

  test('should preserve parameter types in inline builders', () async {
    final stream = dataSource.isolate(
      directories: [testProjectDir],
      outputDir: outputDir,
    );

    await stream.drain();

    final consumerIsolatedFile = Directory(p.join(outputDir, 'Consumer'))
        .listSync(recursive: false)
        .whereType<File>()
        .firstWhere((f) => f.path.contains('Consumer_builder'));

    final content = consumerIsolatedFile.readAsStringSync();

    // Consumer builder: (context, value, child)
    // value is typed 'dynamic' in the mock Consumer; child is 'Widget?'
    // so after stripping nullability it becomes 'Widget'.
    expect(content, contains('dynamic value;'));
    expect(content, contains('Widget child;'));
  });
}
