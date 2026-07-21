import 'package:flutter/material.dart';

class NoLoopsNoOpsExample extends StatefulWidget {
  const NoLoopsNoOpsExample({super.key});
  @override
  State<NoLoopsNoOpsExample> createState() => _NoLoopsNoOpsExampleState();
}

class _NoLoopsNoOpsExampleState extends State<NoLoopsNoOpsExample> {
  int counter = 0;

  void incrementNoLoopsNoOps() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text('$counter');
  }
}

class SingleForLoopExample extends StatefulWidget {
  const SingleForLoopExample({super.key});
  @override
  State<SingleForLoopExample> createState() => _SingleForLoopExampleState();
}

class _SingleForLoopExampleState extends State<SingleForLoopExample> {
  final List<String> items = ['a', 'b', 'c'];
  int counter = 0;

  void incrementSingleForLoop() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final item in items) {
      children.add(Text(item));
    }
    return Column(children: children);
  }
}

class WhileAndDoWhileExample extends StatefulWidget {
  const WhileAndDoWhileExample({super.key});
  @override
  State<WhileAndDoWhileExample> createState() => _WhileAndDoWhileExampleState();
}

class _WhileAndDoWhileExampleState extends State<WhileAndDoWhileExample> {
  int counter = 0;

  void incrementWhileAndDoWhile() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    int i = 0;
    while (i < 3) {
      children.add(Text('while $i'));
      i++;
    }
    int j = 0;
    do {
      children.add(Text('do $j'));
      j++;
    } while (j < 2);
    return Column(children: children);
  }
}

class LinearOpsOnlyExample extends StatefulWidget {
  const LinearOpsOnlyExample({super.key});
  @override
  State<LinearOpsOnlyExample> createState() => _LinearOpsOnlyExampleState();
}

class _LinearOpsOnlyExampleState extends State<LinearOpsOnlyExample> {
  List<int> items = [3, 1, 2];
  int counter = 0;

  void incrementLinearOpsOnly() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List<int>.from(items)..sort();
    final filtered = sorted.where((x) => x > 1);
    final widgets = filtered.map((x) => Text('$x'));
    return Column(children: widgets.toList());
  }
}

class MixedLoopsAndOpsExample extends StatefulWidget {
  const MixedLoopsAndOpsExample({super.key});
  @override
  State<MixedLoopsAndOpsExample> createState() =>
      _MixedLoopsAndOpsExampleState();
}

class _MixedLoopsAndOpsExampleState extends State<MixedLoopsAndOpsExample> {
  List<String> items = ['x', 'y'];
  int counter = 0;

  void incrementMixedLoopsAndOps() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final item in items) {
      children.add(Text(item));
    }
    items.forEach((item) {
      children.add(Text('fe $item'));
    });
    final label = items.reduce((a, b) => '$a,$b');
    return Column(children: [...children, Text(label)]);
  }
}

class NestedForLoopExample extends StatefulWidget {
  const NestedForLoopExample({super.key});
  @override
  State<NestedForLoopExample> createState() => _NestedForLoopExampleState();
}

class _NestedForLoopExampleState extends State<NestedForLoopExample> {
  final List<List<String>> rows = [
    ['a', 'b'],
    ['c'],
  ];
  int counter = 0;

  void incrementNestedForLoop() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final row in rows) {
      for (final cell in row) {
        children.add(Text(cell));
      }
    }
    return Column(children: children);
  }
}

class NestedCollectionOpExample extends StatefulWidget {
  const NestedCollectionOpExample({super.key});
  @override
  State<NestedCollectionOpExample> createState() =>
      _NestedCollectionOpExampleState();
}

class _NestedCollectionOpExampleState extends State<NestedCollectionOpExample> {
  final List<String> items = ['a', 'b'];
  final List<String> tags = ['a', 'x'];
  int counter = 0;

  void incrementNestedCollectionOp() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // .where nested inside the .map callback runs per element (depth 2);
    // the trailing .map on its result is chained, not nested.
    final widgets = items
        .map((item) => tags.where((t) => t == item).length)
        .map((n) => Text('$n'));
    return Column(children: widgets.toList());
  }
}
