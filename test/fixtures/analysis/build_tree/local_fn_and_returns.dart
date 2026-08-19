import 'package:flutter/material.dart';

// A local function declared before a loop but invoked inside it costs one
// widget per element. Counting its body at the declaration site would record
// those widgets outside any iteration scope.
// treeIterationCount: 1; iterationWidgetCount: 2 (Padding + Text per element).
class LocalFnInLoopExample extends StatefulWidget {
  const LocalFnInLoopExample({super.key});

  @override
  State<LocalFnInLoopExample> createState() => _LocalFnInLoopExampleState();
}

class _LocalFnInLoopExampleState extends State<LocalFnInLoopExample> {
  List<int> items = [1, 2];

  void bumpLocalFnInLoop() {
    setState(() {
      items = [...items, items.length];
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget row(int i) =>
        Padding(padding: EdgeInsets.all(i.toDouble()), child: Text('$i'));

    return Column(children: items.map(row).toList());
  }
}

// A local function that is never referenced still contributes its widgets:
// deferring the body must not drop it.
// treeNonConstWidgetCount: 1 (Column) + 1 (SizedBox in the unused fn) = 2.
class UnusedLocalFnExample extends StatefulWidget {
  const UnusedLocalFnExample({super.key});

  @override
  State<UnusedLocalFnExample> createState() => _UnusedLocalFnExampleState();
}

class _UnusedLocalFnExampleState extends State<UnusedLocalFnExample> {
  int counter = 0;

  void bumpUnusedLocalFn() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_element
    Widget unused() => SizedBox(height: counter.toDouble());

    return Column(children: const []);
  }
}

// An early-exit guard returning a const widget does not make this a const
// build: the path that matters returns a full tree.
// rootBuildReturnsConstWidget: false.
class GuardedConstReturnExample extends StatefulWidget {
  const GuardedConstReturnExample({super.key});

  @override
  State<GuardedConstReturnExample> createState() =>
      _GuardedConstReturnExampleState();
}

class _GuardedConstReturnExampleState extends State<GuardedConstReturnExample> {
  bool loading = false;
  int counter = 0;

  void bumpGuardedConstReturn() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox.shrink();
    return Column(children: [Text('$counter')]);
  }
}

// Every exit is const, so the build really does return a const widget.
// rootBuildReturnsConstWidget: true.
class AllConstReturnsExample extends StatefulWidget {
  const AllConstReturnsExample({super.key});

  @override
  State<AllConstReturnsExample> createState() => _AllConstReturnsExampleState();
}

class _AllConstReturnsExampleState extends State<AllConstReturnsExample> {
  bool loading = false;
  int counter = 0;

  void bumpAllConstReturns() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox.shrink();
    return const Text('done');
  }
}
