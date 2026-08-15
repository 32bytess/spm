import 'package:flutter/material.dart';

// ReorderableListView.builder is a lazy, viewport-culled list — the same
// contract as ListView.builder. Its itemBuilder runs per visible element.
// treeListRenderingStrategy: 1; iterationWidgetCount: 1 (Text per element).
class ReorderableLazyExample extends StatefulWidget {
  const ReorderableLazyExample({super.key});

  @override
  State<ReorderableLazyExample> createState() => _ReorderableLazyExampleState();
}

class _ReorderableLazyExampleState extends State<ReorderableLazyExample> {
  List<int> items = [1, 2];

  void bumpReorderableLazy() {
    setState(() {
      items = [...items, items.length];
    });
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      itemCount: items.length,
      onReorder: (a, b) {},
      itemBuilder: (context, index) => Text('${items[index]}', key: ValueKey(index)),
    );
  }
}

// PageView fed a concrete children: list builds every page each rebuild.
// treeListRenderingStrategy: 2.
class EagerPageViewExample extends StatefulWidget {
  const EagerPageViewExample({super.key});

  @override
  State<EagerPageViewExample> createState() => _EagerPageViewExampleState();
}

class _EagerPageViewExampleState extends State<EagerPageViewExample> {
  int counter = 0;

  void bumpEagerPageView() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageView(children: [Text('$counter'), const Text('b')]);
  }
}

// SliverList is lazy only when its delegate is. A SliverChildListDelegate
// materializes every child up front — eager despite the sliver wrapper.
// treeListRenderingStrategy: 2.
class EagerSliverExample extends StatefulWidget {
  const EagerSliverExample({super.key});

  @override
  State<EagerSliverExample> createState() => _EagerSliverExampleState();
}

class _EagerSliverExampleState extends State<EagerSliverExample> {
  int counter = 0;

  void bumpEagerSliver() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate([Text('$counter'), const Text('b')]),
        ),
      ],
    );
  }
}

// The same sliver with a builder delegate stays lazy.
// treeListRenderingStrategy: 1.
class LazySliverExample extends StatefulWidget {
  const LazySliverExample({super.key});

  @override
  State<LazySliverExample> createState() => _LazySliverExampleState();
}

class _LazySliverExampleState extends State<LazySliverExample> {
  int counter = 0;

  void bumpLazySliver() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => Text('$counter'),
            childCount: 3,
          ),
        ),
      ],
    );
  }
}

// List.generate is a factory constructor, not a method invocation, but it
// still runs its callback once per element.
// treeIterationCount: 1; iterationWidgetCount: 1 (Text per element).
class GenerateExample extends StatefulWidget {
  const GenerateExample({super.key});

  @override
  State<GenerateExample> createState() => _GenerateExampleState();
}

class _GenerateExampleState extends State<GenerateExample> {
  int counter = 0;

  void bumpGenerate() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: List.generate(3, (i) => Text('$counter-$i')));
  }
}
