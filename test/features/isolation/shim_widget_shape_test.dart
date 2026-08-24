import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/core/constants/app_constants.dart';
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:test/test.dart';

import 'utils/temp_project.dart';

/// What a declaration-only stand-in has to do for the widget it replaces.
///
/// Run with `--no-inline-third-party`, because that is the mode where a
/// third-party widget becomes a stand-in at all. The default carries its real
/// tree, and the stand-in path is then reached only by the budget, the revert
/// pass, and every repo-local declaration that builds no UI.
const String _scopeSource = '''
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

class ShapeHost extends StatefulWidget {
  const ShapeHost({super.key});

  @override
  State<ShapeHost> createState() => ShapeHostState();
}

class ShapeHostState extends State<ShapeHost> {
  final FancyNotifier _notifier = FancyNotifier();
  final FancyStyles _styles = FancyStyles();

  @override
  void initState() {
    super.initState();
    _notifier.addListener(_onChange);
  }

  @override
  void dispose() {
    _notifier.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {}

  @override
  Widget build(BuildContext context) => Column(
    children: [
      FancyBox(child: const Text('inside the box')),
      FancyStack(children: [const Text('a'), const Text('b')]),
      FancyPage(body: const Text('page body')),
      const FancyPage.empty(),
      const FancyChart(points: []),
      _styles.badge,
      Text(_styles.familyName),
      Text('\${_styles.spacing}'),
    ],
  );
}
''';

void main() {
  late TempProject project;
  late Directory output;
  late String isolated;

  setUpAll(() async {
    project = TempProject.create(
      sources: {'shape.dart': _scopeSource},
      extraPackages: {
        'ui_kit': p.join(
          p.absolute('test/fixtures/isolation_third_party'),
          'ui_kit',
        ),
      },
      prefix: 'spm_shim_shape',
    );
    output = Directory.systemTemp.createTempSync('spm_shim_shape_out');

    await IsolationDataSourceImpl()
        .isolate(
          directories: [project.path],
          outputDir: output.path,
          inlineThirdParty: false,
        )
        .toList();

    isolated = Directory(p.join(output.path, 'State'))
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.contains('ShapeHostState'))
        .readAsStringSync();
  });

  tearDownAll(() {
    project.delete();
    if (output.existsSync()) output.deleteSync(recursive: true);
  });

  group('a widget stand-in passes its child through', () {
    test('a `child` parameter becomes a field the build renders', () {
      // The loss this closes: the constructor accepted `child` and the class
      // never rendered it, so whatever tree the transplanted code passed in was
      // constructed and then never mounted, laid out or painted. Where such a
      // stand-in was the root of the generated build, the whole scope drew a
      // blank box.
      expect(isolated, contains('class FancyBox extends StatelessWidget'));
      expect(isolated, contains('final dynamic child;'));
      expect(isolated, contains('child is Widget'));
    });

    test('the field is `dynamic`, not `Widget?`', () {
      // A `this.child` parameter takes the field's type, so a `Widget?` field
      // would refuse a builder, a nullable subtype or another stand-in at the
      // call site. That is exactly the family of failures the dynamic parameter
      // types exist to remove.
      expect(isolated, isNot(contains('final Widget? child;')));
      expect(isolated, contains('FancyBox({super.key, this.child})'));
    });

    test('a constructor that does not take it initialises it anyway', () {
      // A final field with no initialiser has to be initialised by every
      // generative constructor. Without this the output gains
      // `final_not_initialized_constructor`, which is error severity.
      expect(isolated, contains('FancyPage.empty({super.key}) : body = null;'));
    });

    test('`children` wraps in Stack and nothing else', () {
      expect(isolated, contains('class FancyStack extends StatelessWidget'));
      expect(isolated, contains('Stack('));
      expect(isolated, contains('children is List<Widget>'));
    });

    test('the wrapper stays outside every list-strategy set', () {
      // Not a matter of taste. `BuildMetricsVisitor._classifyListStrategy`
      // returns its most expensive class for any `Column`, `Row`, `Wrap` or
      // `Flex` whose `children:` is not a fixed-arity literal, and
      // `listRenderingStrategy` is taken as a scope-wide maximum, so a `Column`
      // here would pin `treeListRenderingStrategy` at its ceiling for every
      // scope reaching such a stand-in, in the transplant and nowhere else.
      //
      // This asserts the coupling rather than the consequence, so it fails
      // loudly if either side moves.
      const wrapper = 'Stack';
      const flexLike = {'Column', 'Row', 'Wrap', 'Flex'};
      const scrollLists = {
        'ListView',
        'GridView',
        'ReorderableListView',
        'PageView',
        'ListWheelScrollView',
      };
      const alwaysLazy = {
        'SliverList',
        'SliverGrid',
        'SliverFixedExtentList',
        'SliverPrototypeExtentList',
        'SliverAnimatedList',
        'AnimatedList',
        'AnimatedGrid',
      };
      expect(flexLike, isNot(contains(wrapper)));
      expect(scrollLists, isNot(contains(wrapper)));
      expect(alwaysLazy, isNot(contains(wrapper)));
      expect(AppConstants.layoutBuilders, isNot(contains(wrapper)));
    });

    test('a stand-in that draws its own content gains nothing', () {
      // `points` is not a pass-through name, and rendering it would build
      // objects the application never draws. That work stays lost, and saying
      // so is the point.
      expect(isolated, contains('class FancyChart extends StatelessWidget'));
      final body = _classBody(isolated, 'FancyChart');
      expect(body, contains('const SizedBox.shrink()'));
      expect(body, isNot(contains('is Widget')));
    });

    test('the pass-through name is declared exactly once', () {
      // The real class also declares `child`, and rendering the field beside a
      // `child` getter would declare one name twice.
      final declarations = RegExp(
        r'\bchild\b',
      ).allMatches(_classBody(isolated, 'FancyBox')).length;
      expect(declarations, greaterThan(0));
      expect(_classBody(isolated, 'FancyBox'), isNot(contains('get child')));
    });
  });

  group('a member type survives only when it hands out a widget', () {
    test('a Widget-returning getter keeps its type', () {
      // `helperWidgetCount` and `helperReferenceCount` come from the
      // widget-returning-helper rule, so degrading this to `dynamic` would stop
      // the member being counted as one.
      expect(isolated, contains('Widget get badge'));
    });

    test('an Iterable<Widget> member keeps its type', () {
      // The rule admits `Iterable<Widget>` as well as `Widget`, because a
      // `List<Widget> _buildRows()` helper is counted as widget-producing.
      expect(isolated, contains('List<Widget> get rows'));
    });

    test('everything else degrades, and still hands back a real value', () {
      expect(isolated, contains('dynamic get spacing => 0;'));
      expect(isolated, contains("dynamic get familyName => '';"));
    });
  });

  group('a non-widget stand-in declares its nearest nameable supertype', () {
    test('the supertype is mirrored', () {
      // What this buys, now that parameter types are `dynamic`, is generic
      // bounds: a package widget generic over `T extends ChangeNotifier?` stops
      // type-checking against a stand-in with no supertype at all.
      expect(isolated, contains('class FancyNotifier extends ChangeNotifier'));
    });

    test('members the supertype supplies are not redeclared', () {
      // `addListener` and `removeListener` are reached by the scope and are
      // `ChangeNotifier`'s own. Rendering them beside `extends ChangeNotifier`
      // would be an invalid override, and the supertype's implementations are
      // the ones the call sites were written against.
      final body = _classBody(isolated, 'FancyNotifier');
      expect(body, isNot(contains('addListener')));
      expect(body, isNot(contains('removeListener')));
    });
  });
}

/// The source of the class named [name], up to its closing brace.
String _classBody(String source, String name) {
  final start = source.indexOf(RegExp('class $name\\b'));
  if (start < 0) return '';
  final open = source.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return source.substring(start);
}
