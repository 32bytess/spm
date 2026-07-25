/*
integration test for :
  - treeNonConstWidgetCount
  - treeMaxWidgetNestingDepth
  - rootBuildReturnsConstWidget
  - treeConstWidgetCount
  - helperReferenceCount
  - helperWidgetCount
  - helperMaxWidgetNestingDepth
  - treeCyclomaticComplexity
*/
import 'package:spm/src/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:test/test.dart';

import 'utils/test_helper.dart';

void main() {
  late List<AnalysisResultEntity> results;

  setUpAll(() async {
    results = await getResultsForFixture('build_tree');
    expect(
      results,
      isNotEmpty,
      reason: 'No analysis results found for build_tree fixture.',
    );
  });

  group('build tree metrics', () {
    test('treeNonConstWidgetCount', () {
      final widgetCountResults = results
          .where((r) => r.filePath.contains('widget_count'))
          .toList();
      expect(
        widgetCountResults,
        hasLength(3),
        reason: 'Expected 3 State<> subclasses in widget_count fixture',
      );

      final singleWidget = widgetCountResults.firstWhere(
        (r) => r.stateClassName == '_SingleWidgetExampleState',
      );
      expect(
        singleWidget.treeNonConstWidgetCount,
        equals(1),
        reason: 'Build with single Text should have treeNonConstWidgetCount=1',
      );

      final nestedWidgets = widgetCountResults.firstWhere(
        (r) => r.stateClassName == '_NestedWidgetsExampleState',
      );
      expect(
        nestedWidgets.treeNonConstWidgetCount,
        equals(2),
        reason:
            'Build with Center > Text should have treeNonConstWidgetCount=2',
      );

      final manyWidgets = widgetCountResults.firstWhere(
        (r) => r.stateClassName == '_ManyWidgetsExampleState',
      );
      expect(
        manyWidgets.treeNonConstWidgetCount,
        equals(5),
        reason:
            'Build with Column > [Center > Text, Text, Text] should have treeNonConstWidgetCount=5',
      );
    });

    test('treeMaxWidgetNestingDepth', () {
      final widgetCountResults = results
          .where((r) => r.filePath.contains('widget_count'))
          .toList();

      final singleWidget = widgetCountResults.firstWhere(
        (r) => r.stateClassName == '_SingleWidgetExampleState',
      );
      expect(
        singleWidget.treeMaxWidgetNestingDepth,
        equals(1),
        reason: 'Single widget should have treeMaxWidgetNestingDepth=1',
      );

      final nestedWidgets = widgetCountResults.firstWhere(
        (r) => r.stateClassName == '_NestedWidgetsExampleState',
      );
      expect(
        nestedWidgets.treeMaxWidgetNestingDepth,
        equals(2),
        reason: 'Center > Text should have treeMaxWidgetNestingDepth=2',
      );

      final manyWidgets = widgetCountResults.firstWhere(
        (r) => r.stateClassName == '_ManyWidgetsExampleState',
      );
      expect(
        manyWidgets.treeMaxWidgetNestingDepth,
        equals(3),
        reason:
            'Column > Center > Text (deepest branch) should have treeMaxWidgetNestingDepth=3',
      );
    });

    test('rootBuildReturnsConstWidget', () {
      final constResults = results
          .where((r) => r.filePath.contains('const_widgets'))
          .toList();
      expect(
        constResults,
        hasLength(4),
        reason: 'Expected 4 State<> subclasses in const_widgets fixture',
      );

      final allConst = constResults.firstWhere(
        (r) => r.stateClassName == '_AllConstExampleState',
      );
      expect(
        allConst.rootBuildReturnsConstWidget,
        isTrue,
        reason:
            'Build returning const widget should have rootBuildReturnsConstWidget=true',
      );

      final noConst = constResults.firstWhere(
        (r) => r.stateClassName == '_NoConstExampleState',
      );
      expect(
        noConst.rootBuildReturnsConstWidget,
        isFalse,
        reason:
            'Build returning non-const widget should have rootBuildReturnsConstWidget=false',
      );

      final mixedConst = constResults.firstWhere(
        (r) => r.stateClassName == '_MixedConstExampleState',
      );
      expect(
        mixedConst.rootBuildReturnsConstWidget,
        isFalse,
        reason:
            'Build returning non-const root with const child should have rootBuildReturnsConstWidget=false',
      );

      final preambleClosure = constResults.firstWhere(
        (r) => r.stateClassName == '_PreambleClosureConstExampleState',
      );
      expect(
        preambleClosure.rootBuildReturnsConstWidget,
        isFalse,
        reason:
            'const returned by a preamble closure is not the build body root '
            'return; build itself returns a non-const Column',
      );
    });

    test('treeConstWidgetCount', () {
      final constResults = results
          .where((r) => r.filePath.contains('const_widgets'))
          .toList();

      final allConst = constResults.firstWhere(
        (r) => r.stateClassName == '_AllConstExampleState',
      );
      expect(
        allConst.treeConstWidgetCount,
        equals(1),
        reason:
            'const Center(child: Text) is one canonicalized const unit: the '
            'const root is counted, its subtree is skipped (const boundary)',
      );

      final noConst = constResults.firstWhere(
        (r) => r.stateClassName == '_NoConstExampleState',
      );
      expect(
        noConst.treeConstWidgetCount,
        equals(0),
        reason: 'No const widgets should have treeConstWidgetCount=0',
      );

      final mixedConst = constResults.firstWhere(
        (r) => r.stateClassName == '_MixedConstExampleState',
      );
      expect(
        mixedConst.treeConstWidgetCount,
        equals(1),
        reason:
            'const Text inside non-const Center should have treeConstWidgetCount=1',
      );

      final preambleClosure = constResults.firstWhere(
        (r) => r.stateClassName == '_PreambleClosureConstExampleState',
      );
      expect(
        preambleClosure.treeConstWidgetCount,
        equals(1),
        reason:
            'the const SizedBox inside the preamble closure is still counted',
      );
    });

    test('helperReferenceCount', () {
      final helperResults = results
          .where((r) => r.filePath.contains('helper_methods'))
          .toList();
      expect(
        helperResults,
        hasLength(12),
        reason: 'Expected 12 State<> subclasses in helper_methods fixture',
      );

      final noHelpers = helperResults.firstWhere(
        (r) => r.stateClassName == '_NoHelpersExampleState',
      );
      expect(
        noHelpers.helperReferenceCount,
        equals(0),
        reason:
            'Build with no helper methods should have helperReferenceCount=0',
      );

      final singleHelper = helperResults.firstWhere(
        (r) => r.stateClassName == '_SingleHelperExampleState',
      );
      expect(
        singleHelper.helperReferenceCount,
        equals(1),
        reason:
            'Build calling one buildXxx method should have helperReferenceCount=1',
      );

      final multipleHelpers = helperResults.firstWhere(
        (r) => r.stateClassName == '_MultipleHelpersExampleState',
      );
      expect(
        multipleHelpers.helperReferenceCount,
        equals(3),
        reason:
            'Build calling buildHeader, _buildBody, buildFooter should have helperReferenceCount=3',
      );

      final nonBuildNamed = helperResults.firstWhere(
        (r) => r.stateClassName == '_NonBuildNamedHelperExampleState',
      );
      expect(
        nonBuildNamed.helperReferenceCount,
        equals(1),
        reason:
            'createCard() returns Widget so it should be counted regardless of name',
      );

      final buildNamedNonWidget = helperResults.firstWhere(
        (r) => r.stateClassName == '_BuildNamedNonWidgetExampleState',
      );
      expect(
        buildNamedNonWidget.helperReferenceCount,
        equals(0),
        reason:
            'buildTitle() returns String not Widget so it should not be counted',
      );

      final preambleHelper = helperResults.firstWhere(
        (r) => r.stateClassName == '_PreambleHelperExampleState',
      );
      expect(
        preambleHelper.helperReferenceCount,
        equals(0),
        reason:
            'buildCard() called in preamble before return should not be counted',
      );

      final directReturn = helperResults.firstWhere(
        (r) => r.stateClassName == '_DirectReturnHelperExampleState',
      );
      expect(
        directReturn.helperReferenceCount,
        equals(1),
        reason:
            'buildContent() as direct return value should be counted via _inReturnExpression',
      );

      final repeated = helperResults.firstWhere(
        (r) => r.stateClassName == '_RepeatedHelperCallExampleState',
      );
      expect(
        repeated.helperReferenceCount,
        equals(2),
        reason:
            'buildItem() called twice counts per call site, even though the '
            'body is analyzed once',
      );

      final widgetListOp = helperResults.firstWhere(
        (r) => r.stateClassName == '_WidgetListOpExampleState',
      );
      expect(
        widgetListOp.helperReferenceCount,
        equals(0),
        reason:
            'firstWhere on a List<Widget> returns Widget but is a collection '
            'op, not a helper',
      );
      expect(
        widgetListOp.treeIterationCount,
        equals(1),
        reason: 'the firstWhere still counts as one linear collection op',
      );

      final preambleClosure = helperResults.firstWhere(
        (r) => r.stateClassName == '_PreambleClosureHelperExampleState',
      );
      expect(
        preambleClosure.helperReferenceCount,
        equals(0),
        reason:
            'make() is a function-typed variable invocation, not a method '
            'call, and makeCard() inside the closure body is not a build-body '
            'call site',
      );

      final templateBuild = helperResults.firstWhere(
        (r) => r.stateClassName == '_TemplateBuildCallExampleState',
      );
      expect(
        templateBuild.helperReferenceCount,
        equals(0),
        reason: 'template.build(context) is a foreign build(), never a helper',
      );
    });

    test('helperWidgetCount', () {
      final helperResults = results
          .where((r) => r.filePath.contains('helper_methods'))
          .toList();

      final noHelpers = helperResults.firstWhere(
        (r) => r.stateClassName == '_NoHelpersExampleState',
      );
      expect(noHelpers.helperWidgetCount, equals(0));

      final singleHelper = helperResults.firstWhere(
        (r) => r.stateClassName == '_SingleHelperExampleState',
      );
      expect(
        singleHelper.helperWidgetCount,
        equals(1),
        reason: 'buildContent() returns Text — 1 widget',
      );

      final multipleHelpers = helperResults.firstWhere(
        (r) => r.stateClassName == '_MultipleHelpersExampleState',
      );
      expect(
        multipleHelpers.helperWidgetCount,
        equals(3),
        reason: 'Three helpers each returning 1 widget → 3 total',
      );

      final nonBuildNamed = helperResults.firstWhere(
        (r) => r.stateClassName == '_NonBuildNamedHelperExampleState',
      );
      expect(
        nonBuildNamed.helperWidgetCount,
        equals(2),
        reason: 'createCard() returns Card(child: Text) → 2 widgets',
      );

      final deepHelper = helperResults.firstWhere(
        (r) => r.stateClassName == '_DeepHelperExampleState',
      );
      expect(
        deepHelper.helperWidgetCount,
        equals(3),
        reason: 'buildDeep() returns Column > Row > Text → 3 widgets',
      );

      final repeated = helperResults.firstWhere(
        (r) => r.stateClassName == '_RepeatedHelperCallExampleState',
      );
      expect(
        repeated.helperWidgetCount,
        equals(1),
        reason: 'buildItem() called twice but body counted once — 1 widget',
      );

      final templateBuild = helperResults.firstWhere(
        (r) => r.stateClassName == '_TemplateBuildCallExampleState',
      );
      expect(
        templateBuild.helperWidgetCount,
        equals(0),
        reason:
            'template.build(context) must not re-enter the state class\'s own '
            'build body via helper resolution',
      );
    });

    test('helperMaxWidgetNestingDepth', () {
      final helperResults = results
          .where((r) => r.filePath.contains('helper_methods'))
          .toList();

      final noHelpers = helperResults.firstWhere(
        (r) => r.stateClassName == '_NoHelpersExampleState',
      );
      expect(noHelpers.helperMaxWidgetNestingDepth, equals(0));

      final singleHelper = helperResults.firstWhere(
        (r) => r.stateClassName == '_SingleHelperExampleState',
      );
      expect(
        singleHelper.helperMaxWidgetNestingDepth,
        equals(1),
        reason: 'buildContent() returns a flat Text → depth 1',
      );

      final multipleHelpers = helperResults.firstWhere(
        (r) => r.stateClassName == '_MultipleHelpersExampleState',
      );
      expect(
        multipleHelpers.helperMaxWidgetNestingDepth,
        equals(1),
        reason: 'All helpers return flat widgets → max depth 1',
      );

      final nonBuildNamed = helperResults.firstWhere(
        (r) => r.stateClassName == '_NonBuildNamedHelperExampleState',
      );
      expect(
        nonBuildNamed.helperMaxWidgetNestingDepth,
        equals(2),
        reason: 'createCard() returns Card(child: Text) → depth 2',
      );

      final deepHelper = helperResults.firstWhere(
        (r) => r.stateClassName == '_DeepHelperExampleState',
      );
      expect(
        deepHelper.helperMaxWidgetNestingDepth,
        equals(3),
        reason: 'buildDeep() returns Column > Row > Text → depth 3',
      );

      final repeated = helperResults.firstWhere(
        (r) => r.stateClassName == '_RepeatedHelperCallExampleState',
      );
      expect(
        repeated.helperMaxWidgetNestingDepth,
        equals(1),
        reason: 'buildItem() returns flat Text → depth 1',
      );
    });

    group('child widget class aggregation', () {
      late List<AnalysisResultEntity> childResults;

      setUpAll(() {
        childResults = results
            .where((r) => r.filePath.contains('child_widget_metrics'))
            .toList();
        expect(
          childResults,
          hasLength(2),
          reason: 'Expected 2 State subclasses in child_widget_metrics fixture',
        );
      });

      test('treeNonConstWidgetCount counts non-const widgets in child build()', () {
        final noRootConst = childResults.firstWhere(
          (r) => r.stateClassName == '_ChildWidgetNoRootConstExampleState',
        );
        expect(
          noRootConst.treeNonConstWidgetCount,
          equals(3),
          reason:
              'root build: Column + _DeepConstChild = 2 (helper call excluded); '
              'child build: Column = 1 (const Text a/b excluded); total = 3',
        );

        final withRootConst = childResults.firstWhere(
          (r) => r.stateClassName == '_ChildWidgetWithRootConstExampleState',
        );
        expect(
          withRootConst.treeNonConstWidgetCount,
          equals(3),
          reason:
              'root build: Column + _DeepConstChild = 2 (const Text and helper '
              'call excluded); child build: Column = 1; total = 3',
        );
      });

      test('helperWidgetCount includes child widget helper bodies', () {
        final noRootConst = childResults.firstWhere(
          (r) => r.stateClassName == '_ChildWidgetNoRootConstExampleState',
        );
        expect(
          noRootConst.helperWidgetCount,
          equals(2),
          reason:
              'root helper _buildRootHelper -> const Placeholder (1) + child '
              'helper _buildHelper -> const Icon (1) = 2 (const counted in helpers)',
        );
        expect(
          noRootConst.helperMaxWidgetNestingDepth,
          equals(1),
          reason: 'Placeholder and Icon are flat widgets -> depth 1',
        );

        final withRootConst = childResults.firstWhere(
          (r) => r.stateClassName == '_ChildWidgetWithRootConstExampleState',
        );
        expect(
          withRootConst.helperWidgetCount,
          equals(2),
          reason: 'Same root + child helper widgets -> 2',
        );
      });

      test('treeMaxWidgetNestingDepth composes across the child build', () {
        for (final r in childResults) {
          expect(
            r.treeMaxWidgetNestingDepth,
            equals(4),
            reason:
                '${r.stateClassName}: _DeepConstChild sits at depth 2 '
                '(Column > child) and its build reaches internal depth 2 '
                '(Column > Text) → absolute depth 2 + 2 = 4',
          );
        }
      });

      test(
        'treeConstWidgetCount covers full tree but excludes helper method widgets',
        () {
          final noRootConst = childResults.firstWhere(
            (r) => r.stateClassName == '_ChildWidgetNoRootConstExampleState',
          );
          expect(
            noRootConst.treeConstWidgetCount,
            equals(2),
            reason:
                'root build: 0 const; child build: Text(a) + Text(b) = 2; '
                'root helper Placeholder and child helper Icon are NOT counted',
          );

          final withRootConst = childResults.firstWhere(
            (r) => r.stateClassName == '_ChildWidgetWithRootConstExampleState',
          );
          expect(
            withRootConst.treeConstWidgetCount,
            equals(3),
            reason:
                'root build: const Text = 1; child build: Text(a) + Text(b) = 2; total = 3; '
                'root helper Placeholder and child helper Icon are NOT counted',
          );
        },
      );
    });

    test('treeCyclomaticComplexity', () {
      final complexityResults = results
          .where((r) => r.filePath.contains('build_complexity'))
          .toList();
      expect(
        complexityResults,
        hasLength(8),
        reason: 'Expected 8 State<> subclasses in build_complexity fixture',
      );

      final simpleBuild = complexityResults.firstWhere(
        (r) => r.stateClassName == '_SimpleBuildExampleState',
      );
      expect(
        simpleBuild.treeCyclomaticComplexity,
        equals(1),
        reason:
            'Linear build with no branching should have treeCyclomaticComplexity=1',
      );

      final conditionalBuild = complexityResults.firstWhere(
        (r) => r.stateClassName == '_ConditionalBuildExampleState',
      );
      expect(
        conditionalBuild.treeCyclomaticComplexity,
        equals(2),
        reason:
            'Build with one if statement should have treeCyclomaticComplexity=2',
      );

      final complexBuild = complexityResults.firstWhere(
        (r) => r.stateClassName == '_ComplexBuildExampleState',
      );
      expect(
        complexBuild.treeCyclomaticComplexity,
        equals(3),
        reason:
            'Build with if + else if should have treeCyclomaticComplexity=3',
      );

      final ternaryBuild = complexityResults.firstWhere(
        (r) => r.stateClassName == '_TernaryBuildExampleState',
      );
      expect(
        ternaryBuild.treeCyclomaticComplexity,
        equals(3),
        reason:
            'Build with two ternary expressions should have treeCyclomaticComplexity=3',
      );

      final forInBuild = complexityResults.firstWhere(
        (r) => r.stateClassName == '_ForInBuildExampleState',
      );
      expect(
        forInBuild.treeCyclomaticComplexity,
        equals(2),
        reason:
            'A for-in loop counts exactly once (ForStatement, not its '
            'ForEachParts child as well)',
      );

      final collectionElements = complexityResults.firstWhere(
        (r) => r.stateClassName == '_CollectionElementBuildExampleState',
      );
      expect(
        collectionElements.treeCyclomaticComplexity,
        equals(3),
        reason:
            'collection-for and collection-if elements inside literals each '
            'count once',
      );

      final switchPattern = complexityResults.firstWhere(
        (r) => r.stateClassName == '_SwitchPatternBuildExampleState',
      );
      expect(
        switchPattern.treeCyclomaticComplexity,
        equals(3),
        reason:
            'Dart 3 pattern switch cases count (+1 each for case 0 and '
            'case 1); default does not',
      );

      final switchExpression = complexityResults.firstWhere(
        (r) => r.stateClassName == '_SwitchExpressionBuildExampleState',
      );
      expect(
        switchExpression.treeCyclomaticComplexity,
        equals(3),
        reason: 'switch expression cases count (+1 each for 0 and _)',
      );
    });

    test('value objects are excluded from widget count and depth', () {
      final voResults = results
          .where((r) => r.filePath.contains('value_objects'))
          .toList();
      expect(
        voResults,
        hasLength(1),
        reason: 'Expected 1 State subclass in value_objects fixture',
      );

      final vo = voResults.first;
      expect(
        vo.treeNonConstWidgetCount,
        equals(2),
        reason:
            'Container + Text = 2; EdgeInsets/TextStyle value objects excluded',
      );
      expect(
        vo.treeMaxWidgetNestingDepth,
        equals(2),
        reason: 'Container > Text = 2; value-object arguments add no depth',
      );
    });
  });
}
