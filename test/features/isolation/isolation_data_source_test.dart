import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:spm/src/features/isolation/domain/entities/isolation_event.dart';

void main() {
  late IsolationDataSourceImpl dataSource;
  late String testProjectDir;
  late String outputDir;

  // One isolate run over the fixtures, shared by every group below that only
  // reads what it wrote. The run is around ten seconds and it used to happen
  // once per test, which was most of this suite's runtime.
  late String sharedOutputDir;

  setUpAll(() async {
    sharedOutputDir = Directory.systemTemp
        .createTempSync('spm_isolation_shared')
        .path;
    await IsolationDataSourceImpl()
        .isolate(
          directories: [p.absolute('test/fixtures/isolation')],
          outputDir: sharedOutputDir,
        )
        .drain();
  });

  tearDownAll(() {
    final dir = Directory(sharedOutputDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

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
    // The field's value is not discarded, it moves: the State declares the
    // binding, the generated initState assigns it, and the value it starts from
    // is a top-level variable anyone can edit or lift into a dependencies file.
    expect(content, contains('late int _counter;'));
    expect(content, contains('_counter = fixtureCounter;'));
    expect(content, contains('int fixtureCounter = 0;'));
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
    // Reached from build(), so the declaration has to be there for the call to
    // resolve and the body must not be: the features read the shape of the
    // tree and never a value.
    expect(content, contains('dynamic externalLabel('));
    expect(content, isNot(contains('external label ')));

    // Reached only from `onPressed: _increment`, and `_increment` is written
    // out without its body, so nothing in the file names this at all. A
    // stand-in for it would be a declaration standing in for code that cannot
    // run during the rebuild being measured.
    expect(content, isNot(contains('externalHelper')));
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

    setUpAll(() async {
      content = Directory(p.join(sharedOutputDir, 'BlocBuilder'))
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

    setUpAll(() async {
      content = Directory(p.join(sharedOutputDir, 'BlocBuilder'))
          .listSync(recursive: false)
          .whereType<File>()
          .firstWhere((f) => f.path.contains('captures'))
          .readAsStringSync();
    });

    test('declares every fixture the generated initState reads', () {
      // `state = fixtureState;` is only half a convention while nothing
      // declares fixtureState: the file carries an error-severity diagnostic,
      // and `spm analyze` skips any file that does.
      expect(content, contains('CaptureState fixtureState'));
      expect(content, contains('bool fixtureOnlyActive'));
      expect(content, contains('String fixtureHeading'));
    });

    test('declares the captured global as well as its seed', () {
      // initState assigns to `captureTheme`, so the global itself has to
      // exist. The dependency extractor dropped it for not being a widget.
      expect(content, contains('CaptureTheme captureTheme ='));
      expect(content, contains('CaptureTheme captureThemeValue ='));
    });

    test('gives every seed a value of its own type', () {
      // These used to be declared `late` and left unassigned, on the argument
      // that a fabricated default could be mistaken for the value that was
      // really there. The argument holds for types and not for values: the
      // generated initState reads every one of them, so an unassigned `late` is
      // a LateInitializationError before the first frame, and a transplant that
      // will not mount cannot be measured at all.
      expect(content, contains('CaptureState fixtureState = CaptureState();'));
      expect(content, contains('bool fixtureOnlyActive = false;'));
      expect(content, contains("String fixtureHeading = '';"));
      expect(content, isNot(contains('late CaptureState fixtureState;')));
    });
  });

  group('a builder handed a tear-off is not a scope', () {
    late List<IsolationDataEvent> events;
    late List<String> outputs;

    setUpAll(() async {
      final scratch = Directory.systemTemp.createTempSync('spm_tearoff_test');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final fixtures = p.absolute('test/fixtures/isolation');

      // Its own data source and output directory: `setUpAll` runs before the
      // file-level `setUp` that builds the shared one.
      events = await IsolationDataSourceImpl()
          .isolate(directories: [fixtures], outputDir: scratch.path)
          .toList()
          .then((all) => all.whereType<IsolationDataEvent>().toList());

      outputs = Directory(scratch.path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .toList();
    });

    test('the inline builders are still isolated', () {
      // The absence asserted below has to be an absence of the tear-off, not an
      // absence of builder scopes altogether.
      expect(
        events.where((e) => e.type == 'BlocBuilder'),
        isNotEmpty,
        reason: 'inline BlocBuilder callbacks are scopes and must survive',
      );
    });

    test('`TearOffBuilderHost` contributes no scope and no file', () {
      // `analyze` has never counted this scope. `isolate` used to, which put a
      // row in the mapping and a file on disk for a scope with no metrics
      // anywhere to pair it against.
      for (final output in outputs) {
        expect(
          output,
          isNot(contains('return _row;')),
          reason:
              'a tear-off transplanted as a scope returns a function '
              'where a Widget belongs, so the file can never analyse clean',
        );
      }
    });
  });

  group('an inlined StatefulWidget brings its State\'s dependencies with it', () {
    late String content;

    setUpAll(() async {
      content = Directory(p.join(sharedOutputDir, 'State'))
          .listSync(recursive: false)
          .whereType<File>()
          .firstWhere((f) => f.path.contains('MyStatefulState'))
          .readAsStringSync();
    });

    test('stands in for a type named only inside the companion State', () {
      // `_ExternalStatefulState` is copied across a file boundary and holds a
      // `Vector3`. The companion was skeletonised and never visited, so nothing
      // in it reached the dependency crawl: no stand-in, no import, no
      // cross-file reference. Measured on one real repository, visiting it took
      // that repository from 447 undefined-name errors to 65.
      expect(content, contains('class _ExternalStatefulState'));
      expect(content, contains('Vector3(1, 2, 3)'));
      expect(content, contains('class Vector3'));
    });

    test('carries the import for a name material re-exports behind a show', () {
      // `PartedWidget` overrides `debugFillProperties`, whose parameter type
      // `material.dart` does NOT export: `widgets.dart` re-exports foundation as
      // `show Brightness, UniqueKey`. Deciding which imports to carry by walking
      // the export graph concluded material already provided the name and
      // carried nothing, leaving an undefined name in the output.
      expect(content, contains('class PartedWidget extends StatefulWidget'));
      expect(content, contains('debugFillProperties'));
      expect(content, contains("import 'package:flutter/foundation.dart';"));
    });
  });

  group('a third-party dependency becomes a stand-in, not a dangling name', () {
    late String content;

    setUpAll(() async {
      content = Directory(p.join(sharedOutputDir, 'State'))
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
      // The `Vector3` this fixture imports is never in the widget tree.
      // Handing it a `Widget` supertype would invent widgets that were never
      // built.
      expect(content, isNot(contains('class Vector3 extends')));
    });

    test('carries only the members the scope reaches', () {
      // The imported type declares several hundred swizzle accessors.
      // Emitting the declared surface rather than the referenced one produced a
      // stand-in of several hundred lines for a type this scope touches twice.
      //
      // The accessors render `dynamic`, because a member type only survives
      // when it reaches `Widget`. Their values still come from the real type,
      // so `x` hands back a double and not a stub: a stub in a slot the call
      // site typed `double` is a TypeError at the first frame.
      expect(content, contains('dynamic get x => 0.0;'));
      expect(content, contains('dynamic get y => 0.0;'));
      expect(content, isNot(contains('get zzzz')));
      expect(content, isNot(contains('crossInto')));
    });

    test('never emits a private member of the package it stands in for', () {
      // `_v3storage` is private to the imported type's own library; a
      // stand-in in another library could never have been reached through it.
      expect(content, isNot(contains('_v3storage')));
    });
  });

  group("the scope's own constructor never lands in the generated State", () {
    late Map<String, String> isolated;

    setUpAll(() async {
      String read(String scopeDir, String needle) =>
          Directory(p.join(sharedOutputDir, scopeDir))
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

    test('gives fields the dropped constructor used to initialise a value', () {
      // Dropping the constructor silently would leave these unassigned, which
      // is a different error rather than a fix: the read is in `build`, so an
      // unassigned `late` is a LateInitializationError on the first frame. The
      // value comes from the fixture block, which is where every binding a
      // transplanted scope needs is declared. A value of the field's own type
      // is not measured, because the features come from the shape of the build
      // tree.
      expect(isolated['fieldFormal'], contains('late String _seed;'));
      expect(isolated['fieldFormal'], contains("String fixtureSeed = '';"));
      expect(isolated['initialiserList'], contains('late int _doubled;'));
      expect(isolated['initialiserList'], contains('int fixtureDoubled = 0;'));

      // Declared, never left to throw.
      expect(
        isolated['fieldFormal'],
        isNot(contains(RegExp(r'late String _seed;(?![\s\S]*fixtureSeed)'))),
      );
    });

    test('a field that carried its own value keeps it, in the block', () {
      // `_hits` was `int _hits = 0;` and the constructor never touched it. The
      // hoist relocates the value rather than replacing it with a default, so
      // a list seeded with twenty rows still builds twenty. Only the place it
      // is written changes.
      expect(isolated['fieldFormal'], contains('late int _hits;'));
      expect(isolated['fieldFormal'], contains('_hits = fixtureHits;'));
      expect(isolated['fieldFormal'], contains('int fixtureHits = 0;'));
    });
  });

  group('code a rebuild cannot run is left out', () {
    // `spm analyze` prunes exactly this before it counts anything: the body of
    // a handler closure, the body a handler tear-off names, and every member
    // `build()` cannot reach. None of it can move a feature, and carrying it is
    // what made a transplant of a forty-line `build` several hundred lines
    // long and lost it to an error in code the metrics never read.
    late String pruned;
    late String carried;
    late String prunedDir;
    late String carriedDir;

    String read(String dir) {
      final file = Directory(p.join(dir, 'State'))
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.contains('_NonRebuildHostState'));
      return file.readAsStringSync();
    }

    setUpAll(() async {
      prunedDir = Directory.systemTemp.createTempSync('spm_prune_on').path;
      carriedDir = Directory.systemTemp.createTempSync('spm_prune_off').path;
      await IsolationDataSourceImpl()
          .isolate(
            directories: [p.absolute('test/fixtures/isolation')],
            outputDir: prunedDir,
          )
          .drain();
      await IsolationDataSourceImpl()
          .isolate(
            directories: [p.absolute('test/fixtures/isolation')],
            outputDir: carriedDir,
            pruneNonRebuild: false,
          )
          .drain();
      pruned = read(prunedDir);
      carried = read(carriedDir);
    });

    tearDownAll(() {
      for (final dir in [Directory(prunedDir), Directory(carriedDir)]) {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });

    test(
      'a screen pushed from a handler is neither carried nor stood in for',
      () {
        // The single largest saving. Pushing a route from `onPressed` used to
        // drag the whole destination tree into the file, and the services it
        // called became stand-ins whose degraded signatures are the commonest
        // error in the output.
        expect(carried, contains('class HandlerOnlyDestination'));
        expect(pruned, isNot(contains('HandlerOnlyDestination')));
        expect(pruned, isNot(contains('HandlerOnlyService')));
      },
    );

    test('a handler tear-off keeps its declaration and loses its body', () {
      // `onPressed: _handleSubmit` is evaluated while the tree is built, so the
      // name has to resolve. The body runs only on the press, so nothing in it
      // needs to survive.
      expect(pruned, contains('onPressed: _handleSubmit'));
      expect(pruned, contains('void _handleSubmit() {'));
      expect(pruned, isNot(contains('Navigator.of(context).push')));
    });

    test('a member build() cannot reach is dropped outright', () {
      expect(carried, contains('_refresh'));
      expect(pruned, isNot(contains('_refresh')));
    });

    test('a widget-returning helper build() calls is kept whole', () {
      expect(
        pruned,
        contains("Widget _buildRow() => Row(children: [Text(_title)]);"),
      );
    });

    test('a field initState seeded moves to the fixture block', () {
      // `_title` is `late final` and the original `initState` assigned it, so
      // dropping that method outright leaves a file that analyses clean and
      // throws a LateInitializationError on the first read. What those methods
      // contribute is a value, and the transplant already knows how to supply
      // one: the binding joins the fixture block, and the generated `initState`
      // does nothing but seed it.
      expect(carried, contains("_title = 'seeded';"));
      expect(pruned, isNot(contains("_title = 'seeded';")));

      expect(pruned, contains('String fixtureTitle'));
      expect(
        pruned,
        contains(
          RegExp(
            r'void initState\(\) \{\s*super\.initState\(\);\s*'
            r'_title = fixtureTitle;',
          ),
        ),
      );
    });

    test('everything else initState did goes with it', () {
      // The seeding is the only part worth keeping. The frame callback beside
      // it, and anything it reached, is gone.
      expect(carried, contains('after first frame'));
      expect(pruned, isNot(contains('after first frame')));
      expect(pruned, isNot(contains('addPostFrameCallback')));
    });

    test('a value-returning handler body throws rather than returning null', () {
      // `validator` returns String?. An empty body completes with null, which
      // is a different answer rather than no answer; a body that always throws
      // satisfies every return type because it never completes normally.
      expect(
        pruned,
        contains(
          RegExp(
            r'validator: \(value\) \{\s*/\* spm: non-rebuild body '
            r'erased \*/\s*throw UnimplementedError\(\);',
          ),
        ),
      );
      expect(pruned, isNot(contains("return 'required'")));
    });

    test('a void deferred callback is emptied, not made to throw', () {
      // `addListener` is in the same non-rebuild family as `onPressed` and it
      // really does run, moments after the scope mounts. Throwing there would
      // trade an analyzer error for an uncaught exception around the first
      // frame, which no analyzer run would report.
      expect(
        pruned,
        contains(
          RegExp(
            r'addListener\(\(\) \{\s*/\* spm: '
            r'non-rebuild body erased \*/\s*\}\)',
          ),
        ),
      );
      expect(pruned, isNot(contains('after change')));
    });

    test('a handler argument that is not a closure is untouched', () {
      // `onTap: enabled ? _a : _b` is evaluated while the tree is built, so
      // `analyze` keeps counting it and both branches stay reachable.
      expect(pruned, contains('onTap: _enabled ? _toggleA : _toggleB'));
      expect(pruned, contains('void _toggleA() => setState'));
      expect(pruned, contains('void _toggleB() => setState'));
    });

    test('a local function only a handler calls goes with the handler', () {
      expect(carried, contains('deepInHandler'));
      expect(pruned, isNot(contains('deepInHandler')));
    });

    test('a carried declaration has its handlers erased too', () {
      // The gate applies inside a carried declaration as well as inside the
      // scope's own class, so the erasure has to reach there too. It did not at
      // first, and the result was the exact failure the two halves exist to
      // prevent: `CarriedOnlyFromHandler` skipped by the crawl, still named by
      // the copied source, undefined in the output.
      expect(pruned, contains('class CarriedCard'));
      expect(carried, contains('class CarriedOnlyFromHandler'));
      expect(pruned, isNot(contains('CarriedOnlyFromHandler')));
    });

    test('every dependency is a late binding seeded from the block', () {
      // The shape the extractor emits: `late <Type> <name>;` in the State,
      // one assignment per binding in a generated initState, and the value it
      // starts from declared at the top level where it can be lifted into a
      // shared dependencies file.
      expect(pruned, contains('late String _title;'));
      expect(pruned, contains('late bool _enabled;'));
      expect(pruned, contains('late TextEditingController _controller;'));

      expect(pruned, contains('_enabled = fixtureEnabled;'));
      expect(pruned, contains('bool fixtureEnabled = true;'));
      expect(
        pruned,
        contains(
          'TextEditingController fixtureController = '
          'TextEditingController();',
        ),
      );

      // `final` does not come along. A member the prune keeps may still assign
      // the field -- `_toggleA() => setState(() => _enabled = true)` does --
      // and `late final` would make that a second write to a final.
      expect(pruned, isNot(contains('late final')));

      // Carried, with the prune off, the fields keep their own initialisers and
      // there is no block to lift.
      expect(carried, contains('bool _enabled = true;'));
      expect(carried, isNot(contains('fixtureEnabled')));
    });

    test('a const field stays const, because two features depend on it', () {
      // `treeConstWidgetCount` and `rootBuildReturnsConstWidget` are features.
      // Turning a `static const` into a late binding stops every `const`
      // constructor that reads it being const, and both move.
      expect(pruned, isNot(contains('late FancySpec')));
    });

    test('the prune makes the file smaller and no less clean', () {
      expect(pruned.length, lessThan(carried.length));
    });
  });
}
