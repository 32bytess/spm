import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:spm/src/features/isolation/domain/entities/isolation_event.dart';

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
    expect(
      content,
      contains('class _ExternalStatefulState extends State<ExternalStateful>'),
    );

    // Widget subclassing a custom base (not directly a Flutter widget) is detected
    expect(content, contains('class ExternalCard'));

    // The base it extends comes with it too. `_isUiClass` admits ExternalCard
    // only because the *resolved* chain reaches StatelessWidget, so emitting the
    // subclass without its base leaves `extends_non_class` behind and the class
    // stops being a widget, which moves it out of widgetCount and into
    // valueObjectAllocCount, and drops its whole build subtree.
    expect(content, contains('class _BaseCard extends StatelessWidget'));

    // A cross-file class that is not a widget but hands one out is inlined
    // whole: `tree_extractor` walks the body of every widget-returning helper
    // a scope calls, so a stand-in would report zero widgets where analyzing
    // the original project counted the divider's subtree.
    expect(content, contains('class ExternalStyles'));
    expect(content, contains('ColoredBox(color: Colors.grey)'));

    // Cross-file declarations that build no UI are declared but not inlined:
    // enough for the file to resolve, never enough to change a count.
    expect(content, contains('class ExternalService'));
    expect(content, isNot(contains("'\$prefix-\$id'")));
    expect(content, contains('void externalHelper() {}'));
    expect(content, isNot(contains('External helper called')));
    expect(content, contains('const dynamic kExternalColor = null;'));
    expect(content, isNot(contains('kExternalColor = Colors.red')));

    // Should be a StatefulWidget
    expect(content, contains('class GeneratedWidget extends StatefulWidget'));
  });

  test('every isolated fixture analyses clean', () async {
    // The property the whole feature exists for: `spm analyze` skips any file
    // carrying an error-severity diagnostic, so a scope that was written but
    // does not analyse contributes nothing to whatever it was extracted for.
    final events = await dataSource
        .isolate(directories: [testProjectDir], outputDir: outputDir)
        .toList();
    final summary = events.last as IsolationSummaryEvent;

    expect(summary.verifiedCount, summary.isolatedCount);
    expect(
      summary.cleanCount,
      summary.verifiedCount,
      reason: '${summary.errorCount} errors across the isolated files',
    );
  });

  test('keeps the prefix an import was written with', () async {
    // The body is copied verbatim, so `math.pi` only resolves if `as math`
    // survives into the regenerated import list. It did not: the visitor sees
    // the two halves of a prefixed reference as unrelated identifiers, and the
    // URI-only fallback rendered a prefixless directive.
    final stream = dataSource.isolate(
      directories: [testProjectDir],
      outputDir: outputDir,
    );
    await stream.drain();

    final file = Directory(p.join(outputDir, 'State'))
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.contains('PrefixedImportsWidget'));
    final content = file.readAsStringSync();

    expect(content, contains("import 'dart:math' as math;"));
    expect(content, contains('math.pi'));
    expect(content, contains('math.Random()'));
  });

  test('keeps the show clause an import was written with', () async {
    final stream = dataSource.isolate(
      directories: [testProjectDir],
      outputDir: outputDir,
    );
    await stream.drain();

    final file = Directory(p.join(outputDir, 'State'))
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.contains('PrefixedImportsWidget'));

    expect(
      file.readAsStringSync(),
      contains("import 'dart:convert' show jsonEncode;"),
    );
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

  test(
    'should replace image widgets with SizedBox but preserve other widgets',
    () async {
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

      // An `Image.asset` call should be replaced with the placeholder
      expect(content, contains("Image.asset('assets/placeholder.png')"));

      // Placeholder() is Flutter core (not in image set), kept as-is
      expect(content, contains('const Placeholder()'));
    },
  );

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

  group('a transplanted scope keeps the bindings it used to close over', () {
    late String content;

    setUp(() async {
      await dataSource
          .isolate(directories: [testProjectDir], outputDir: outputDir)
          .drain();

      content = Directory(p.join(outputDir, 'BlocBuilder'))
          .listSync(recursive: false)
          .whereType<File>()
          .firstWhere((f) => f.path.contains('captures'))
          .readAsStringSync();
    });

    test('lifts variables captured from the enclosing method', () {
      // `onlyActive` and `heading` belong to buildList(), not to the callback,
      // so nothing would declare them once the callback is transplanted.
      expect(content, contains('late bool onlyActive;'));
      expect(content, contains('late String heading;'));
    });

    test('lifts the builder callback parameter', () {
      expect(content, contains('late CaptureState state;'));
    });

    test('seeds every lifted binding from a conventionally named fixture', () {
      expect(content, contains('void initState()'));
      expect(content, contains('super.initState();'));
      expect(content, contains('state = fixtureState;'));
      expect(content, contains('onlyActive = fixtureOnlyActive;'));
      expect(content, contains('heading = fixtureHeading;'));
    });

    test('seeds cross-file globals from their <name>Value counterpart', () {
      expect(content, contains('captureTheme = captureThemeValue;'));
    });

    test('restores casts that promotion no longer supplies', () {
      // `state` is a field now, and Dart does not promote fields, so the
      // original `state.items` would not resolve.
      expect(content, contains('(state as CaptureLoaded).items'));
      expect(content, isNot(contains('? state.items')));
    });

    test('never copies a `context` field over State.context', () {
      // CaptureDialog declares one and is inlined whole, which is fine. What
      // must not happen is that field being copied onto the generated State,
      // where it would shadow State.context.
      final state = content.substring(
        content.indexOf('class _GeneratedWidgetState'),
      );
      final stateBody = state.substring(0, state.indexOf('\n}'));
      expect(stateBody, isNot(contains('BuildContext context;')));
    });
  });

  group('the transplant declares the seeds its own convention invents', () {
    late String content;

    setUp(() async {
      await dataSource
          .isolate(directories: [testProjectDir], outputDir: outputDir)
          .drain();

      content = Directory(p.join(outputDir, 'BlocBuilder'))
          .listSync(recursive: false)
          .whereType<File>()
          .firstWhere((f) => f.path.contains('captures'))
          .readAsStringSync();
    });

    test('declares every fixture the generated initState reads', () {
      // `state = fixtureState;` is only half a convention while nothing
      // declares fixtureState: the file carries an error-severity diagnostic,
      // and `spm analyze` skips any file that does.
      expect(content, contains('late CaptureState fixtureState;'));
      expect(content, contains('late bool fixtureOnlyActive;'));
      expect(content, contains('late String fixtureHeading;'));
    });

    test('declares the captured global as well as its seed', () {
      // initState assigns to `captureTheme`, so the global itself has to
      // exist. The dependency extractor dropped it for not being a widget.
      expect(content, contains('late CaptureTheme captureTheme;'));
      expect(content, contains('late CaptureTheme captureThemeValue;'));
    });

    test('leaves every seed unassigned', () {
      // A fabricated default would be measured as though it were the value
      // that was really there; an unset `late` throws on read instead.
      expect(content, isNot(contains('fixtureState =')));
      expect(content, isNot(contains('captureThemeValue =')));
    });
  });

  group('a third-party dependency becomes a stand-in, not a dangling name', () {
    late String content;

    setUp(() async {
      await dataSource
          .isolate(directories: [testProjectDir], outputDir: outputDir)
          .drain();

      content = Directory(p.join(outputDir, 'State'))
          .listSync(recursive: false)
          .whereType<File>()
          .firstWhere((f) => f.path.contains('ThirdPartyHostState'))
          .readAsStringSync();
    });

    test('declares the type instead of importing its package', () {
      expect(content, contains('class Vector3'));
      expect(content, isNot(contains('package:vector_math')));
    });

    test('keeps the value object a value object', () {
      // vector_math's Vector3 is never in the widget tree. Handing it a
      // `Widget` supertype would invent widgets that were never built.
      expect(content, isNot(contains('class Vector3 extends')));
    });

    test('carries only the members the scope reaches', () {
      // Vector3 declares several hundred swizzle accessors. Emitting the
      // declared surface rather than the referenced one produced a 400-line
      // stand-in for a type this scope touches twice.
      expect(content, contains('double get x'));
      expect(content, contains('double get y'));
      expect(content, isNot(contains('get zzzz')));
      expect(content, isNot(contains('crossInto')));
    });

    test('never emits a private member of the package it stands in for', () {
      // `_v3storage` is private to vector_math's own library; a stand-in in
      // another library could never have been reached through it.
      expect(content, isNot(contains('_v3storage')));
    });
  });

  group("the scope's own constructor never lands in the generated State", () {
    late Map<String, String> isolated;

    setUp(() async {
      await dataSource
          .isolate(directories: [testProjectDir], outputDir: outputDir)
          .drain();

      String read(String scopeDir, String needle) =>
          Directory(p.join(outputDir, scopeDir))
              .listSync()
              .whereType<File>()
              .firstWhere((f) => f.path.contains(needle))
              .readAsStringSync();

      isolated = {
        'fieldFormal': read('State', 'CtorStatefulState'),
        'initialiserList': read('State', 'CtorInitListState'),
        'nonState': read('ConsumerWidget', 'CtorConsumer'),
      };
    });

    // A constructor copied verbatim keeps the name of the class it came from.
    // Inside `_GeneratedWidgetState` that name no longer matches, so Dart reads
    // it as a bodiless method. That one cause is what produces
    // CONCRETE_CLASS_WITH_ABSTRACT_MEMBER, INVALID_CONSTRUCTOR_NAME,
    // CONST_METHOD and INVALID_SUPER_FORMAL_PARAMETER_LOCATION, which look
    // like four unrelated problems until you find the constructor.
    test('drops a State constructor with a field formal parameter', () {
      expect(isolated['fieldFormal'], isNot(contains('CtorStatefulState(')));
    });

    test('drops a State constructor with an initialiser list', () {
      expect(
        isolated['initialiserList'],
        isNot(contains('CtorInitListState(')),
      );
    });

    test("drops a non-State scope's own constructor", () {
      // The ConsumerWidget majority: 40 of 41 such groups carried this.
      expect(isolated['nonState'], isNot(contains('const CtorConsumer(')));
    });

    test('marks fields the dropped constructor used to initialise as late', () {
      // Dropping the constructor silently would leave these unassigned, which
      // is a different error rather than a fix.
      expect(isolated['fieldFormal'], contains('late final String _seed;'));
      expect(isolated['initialiserList'], contains('late final int _doubled;'));
    });

    test('leaves fields the constructor did not initialise alone', () {
      expect(isolated['fieldFormal'], contains('int _hits = 0;'));
      expect(isolated['fieldFormal'], isNot(contains('late int _hits')));
    });
  });
}
