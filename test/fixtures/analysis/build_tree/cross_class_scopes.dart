import 'package:flutter/material.dart';

// Child widget with its own branching build and a LayoutBuilder.
class _BranchingChild extends StatelessWidget {
  const _BranchingChild({required this.flag});
  final bool flag;

  @override
  Widget build(BuildContext context) {
    if (flag) {
      return LayoutBuilder(
        builder: (context, constraints) => SizedBox(child: Text('wide')),
      );
    }
    return const Text('narrow');
  }
}

// treeCyclomaticComplexity: 3 (root build 1 + child build 2; summed)
// treeMaxWidgetNestingDepth: 5 (child at depth 2 + internal depth 3)
// usesLayoutDependentBuilder: true (set by the child build, ORed across tree)
class CrossClassExample extends StatefulWidget {
  const CrossClassExample({super.key});

  @override
  State<CrossClassExample> createState() => _CrossClassExampleState();
}

class _CrossClassExampleState extends State<CrossClassExample> {
  bool wide = false;

  void toggleCrossClass() {
    setState(() {
      wide = !wide;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: _BranchingChild(flag: wide),
    );
  }
}

// treeIterationCount: 1 (the .map in build; helper-body loops excluded)
// treeMaxIterationNestingDepth: 2 (nested for loops in the helper included)
// treeCyclomaticComplexity: 1 (helper-body control flow excluded)
class HelperIterationScopeExample extends StatefulWidget {
  const HelperIterationScopeExample({super.key});

  @override
  State<HelperIterationScopeExample> createState() =>
      _HelperIterationScopeExampleState();
}

class _HelperIterationScopeExampleState
    extends State<HelperIterationScopeExample> {
  List<String> items = ['a', 'b'];

  void addHelperIterationItem() {
    setState(() {
      items = [...items, 'c'];
    });
  }

  Widget _grid() {
    final rows = <Widget>[];
    for (final a in items) {
      for (final b in items) {
        rows.add(Text('$a$b'));
      }
    }
    return Column(children: rows);
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [...items.map((e) => Text(e)), _grid()]);
  }
}

// helperReferenceCount: 1 (only the build-body call site)
// helperWidgetCount: 3 (_outer Column + _inner Row and Text; chains followed)
class TransitiveHelperExample extends StatefulWidget {
  const TransitiveHelperExample({super.key});

  @override
  State<TransitiveHelperExample> createState() =>
      _TransitiveHelperExampleState();
}

class _TransitiveHelperExampleState extends State<TransitiveHelperExample> {
  int counter = 0;

  void incrementTransitive() {
    setState(() {
      counter++;
    });
  }

  Widget _inner() => Row(children: [Text('$counter')]);

  Widget _outer() => Column(children: [_inner()]);

  @override
  Widget build(BuildContext context) => _outer();
}

// A three-class chain used to guard absolute-depth composition. Each build
// adds exactly one widget level, so the full tree depth is 3.
class _DepthLeaf extends StatelessWidget {
  const _DepthLeaf();

  @override
  Widget build(BuildContext context) => Text('leaf');
}

class _DepthMiddle extends StatelessWidget {
  const _DepthMiddle();

  @override
  Widget build(BuildContext context) => _DepthLeaf();
}

class DepthChainExample extends StatefulWidget {
  const DepthChainExample({super.key});

  @override
  State<DepthChainExample> createState() => _DepthChainExampleState();
}

class _DepthChainExampleState extends State<DepthChainExample> {
  @override
  Widget build(BuildContext context) => _DepthMiddle();
}
