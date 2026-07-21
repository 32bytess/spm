import 'package:flutter/material.dart';

// treeListRenderingStrategy: 0 — fixed-arity literal; the if-element is an
// O(1) branch, not a runtime-length expansion.
class FixedColumnExample extends StatefulWidget {
  const FixedColumnExample({super.key});

  @override
  State<FixedColumnExample> createState() => _FixedColumnExampleState();
}

class _FixedColumnExampleState extends State<FixedColumnExample> {
  bool flag = false;

  void toggleFixedColumn() {
    setState(() {
      flag = !flag;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [Text('a'), if (flag) Text('b'), Text('c')],
    );
  }
}

// treeListRenderingStrategy: 2 — spread of a mapped iterable inside the
// literal makes the child count runtime-length.
class SpreadColumnExample extends StatefulWidget {
  const SpreadColumnExample({super.key});

  @override
  State<SpreadColumnExample> createState() => _SpreadColumnExampleState();
}

class _SpreadColumnExampleState extends State<SpreadColumnExample> {
  List<String> items = ['a', 'b'];

  void addSpreadItem() {
    setState(() {
      items = [...items, 'c'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [Text('header'), ...items.map((e) => Text(e))]);
  }
}

// treeListRenderingStrategy: 2 — collection-for element.
class ForElementRowExample extends StatefulWidget {
  const ForElementRowExample({super.key});

  @override
  State<ForElementRowExample> createState() => _ForElementRowExampleState();
}

class _ForElementRowExampleState extends State<ForElementRowExample> {
  List<int> items = [1, 2, 3];

  void addForElementItem() {
    setState(() {
      items = [...items, items.length];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [for (final i in items) Text('$i')]);
  }
}

// treeListRenderingStrategy: 2 — bare list variable: no iteration op in
// sight, but the child count is still runtime-length.
class VariableChildrenExample extends StatefulWidget {
  const VariableChildrenExample({super.key});

  @override
  State<VariableChildrenExample> createState() =>
      _VariableChildrenExampleState();
}

class _VariableChildrenExampleState extends State<VariableChildrenExample> {
  List<Widget> rows = [Text('a')];

  void addVariableRow() {
    setState(() {
      rows = [...rows, Text('b')];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: rows);
  }
}

// treeListRenderingStrategy: 2 — the motivating blind spot of the old
// boolean: SingleChildScrollView over an eagerly-mapped Column builds every
// child on every rebuild, with no viewport culling.
class ScrollViewColumnExample extends StatefulWidget {
  const ScrollViewColumnExample({super.key});

  @override
  State<ScrollViewColumnExample> createState() =>
      _ScrollViewColumnExampleState();
}

class _ScrollViewColumnExampleState extends State<ScrollViewColumnExample> {
  List<String> items = ['a', 'b'];

  void addScrollItem() {
    setState(() {
      items = [...items, 'c'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(children: items.map((e) => Text(e)).toList()),
    );
  }
}

// treeListRenderingStrategy: 1 — SliverList is viewport-bounded by contract.
class SliverListExample extends StatefulWidget {
  const SliverListExample({super.key});

  @override
  State<SliverListExample> createState() => _SliverListExampleState();
}

class _SliverListExampleState extends State<SliverListExample> {
  int count = 3;

  void growSliverList() {
    setState(() {
      count++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => Text('$index'),
            childCount: count,
          ),
        ),
      ],
    );
  }
}

// treeListRenderingStrategy: 1 — the lazy list lives inside a helper body;
// helper signals merge into the tree-level maximum.
class LazyHelperExample extends StatefulWidget {
  const LazyHelperExample({super.key});

  @override
  State<LazyHelperExample> createState() => _LazyHelperExampleState();
}

class _LazyHelperExampleState extends State<LazyHelperExample> {
  List<String> items = ['a', 'b'];

  void addLazyHelperItem() {
    setState(() {
      items = [...items, 'c'];
    });
  }

  Widget _list() {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => Text(items[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 100, child: _list());
  }
}

// treeListRenderingStrategy: 2 — eager beats lazy: the tree-level value is
// the maximum, and the spread Column outranks the ListView.builder.
class EagerBeatsLazyExample extends StatefulWidget {
  const EagerBeatsLazyExample({super.key});

  @override
  State<EagerBeatsLazyExample> createState() => _EagerBeatsLazyExampleState();
}

class _EagerBeatsLazyExampleState extends State<EagerBeatsLazyExample> {
  List<String> items = ['a', 'b'];

  void addEagerBeatsLazyItem() {
    setState(() {
      items = [...items, 'c'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 100,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => Text(items[index]),
          ),
        ),
        ...items.map((e) => Text(e)),
      ],
    );
  }
}
