import 'package:flutter/material.dart';

// iterationWidgetCount: 2. Card + Text live inside the .map callback and are
// built once per element; Column and the header Text are one-shot.
class MapIterationExample extends StatefulWidget {
  const MapIterationExample({super.key});

  @override
  State<MapIterationExample> createState() => _MapIterationExampleState();
}

class _MapIterationExampleState extends State<MapIterationExample> {
  List<String> items = ['a', 'b'];

  void addMapIterationItem() {
    setState(() {
      items = [...items, 'c'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('header'),
        ...items.map((e) => Card(child: Text(e))),
      ],
    );
  }
}

// iterationWidgetCount: 2. The for-loop lives in a helper body; SizedBox +
// Text are per-element, the returned Column is one-shot (helper signals merge).
class LoopHelperIterationExample extends StatefulWidget {
  const LoopHelperIterationExample({super.key});

  @override
  State<LoopHelperIterationExample> createState() =>
      _LoopHelperIterationExampleState();
}

class _LoopHelperIterationExampleState
    extends State<LoopHelperIterationExample> {
  List<String> items = ['a', 'b'];

  void addLoopHelperItem() {
    setState(() {
      items = [...items, 'c'];
    });
  }

  Widget _rows() {
    final out = <Widget>[];
    for (final e in items) {
      out.add(SizedBox(child: Text(e)));
    }
    return Column(children: out);
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: _rows());
  }
}

// iterationWidgetCount: 2. The itemBuilder of a lazy list runs per visible
// element: ListTile + Text count, the ListView itself does not.
class LazyBuilderIterationExample extends StatefulWidget {
  const LazyBuilderIterationExample({super.key});

  @override
  State<LazyBuilderIterationExample> createState() =>
      _LazyBuilderIterationExampleState();
}

class _LazyBuilderIterationExampleState
    extends State<LazyBuilderIterationExample> {
  List<String> items = ['a', 'b'];

  void addLazyBuilderItem() {
    setState(() {
      items = [...items, 'c'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => ListTile(title: Text(items[index])),
    );
  }
}

// iterationWidgetCount: 0. Fixed literal children, nothing is per-element.
// valueObjectAllocCount: 1. The non-const EdgeInsets.all(4) margin allocates
// every rebuild; the const padding is canonicalized and free.
class FlatConstValueObjectExample extends StatefulWidget {
  const FlatConstValueObjectExample({super.key});

  @override
  State<FlatConstValueObjectExample> createState() =>
      _FlatConstValueObjectExampleState();
}

class _FlatConstValueObjectExampleState
    extends State<FlatConstValueObjectExample> {
  int counter = 0;

  void bumpFlatConst() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: EdgeInsets.all(4),
      child: Column(children: [Text('a'), Text('$counter')]),
    );
  }
}
