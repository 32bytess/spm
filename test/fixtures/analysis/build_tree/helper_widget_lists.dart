import 'package:flutter/material.dart';

// Helper returns List<Widget>, spliced straight into children:. The list type
// is not a Widget subtype, but the helper still builds widgets every rebuild.
// helperReferenceCount: 1; helperWidgetCount: 3 (Padding + Text + SizedBox).
class ListHelperExample extends StatefulWidget {
  const ListHelperExample({super.key});

  @override
  State<ListHelperExample> createState() => _ListHelperExampleState();
}

class _ListHelperExampleState extends State<ListHelperExample> {
  int counter = 0;

  void bumpListHelper() {
    setState(() {
      counter++;
    });
  }

  List<Widget> _buildRows() {
    return [
      Padding(padding: const EdgeInsets.all(1), child: Text('$counter')),
      SizedBox(height: counter.toDouble()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: _buildRows());
  }
}

// The list element type is a Widget SUBTYPE, not Widget itself — the real
// `List<DropdownMenuItem<T>> _buildItems()` shape. Iteration inside the helper
// body must surface too.
// helperReferenceCount: 1; helperWidgetCount: 2; treeIterationCount: 1.
class SubtypeListHelperExample extends StatefulWidget {
  const SubtypeListHelperExample({super.key});

  @override
  State<SubtypeListHelperExample> createState() =>
      _SubtypeListHelperExampleState();
}

class _SubtypeListHelperExampleState extends State<SubtypeListHelperExample> {
  int selected = 0;

  void bumpSubtypeListHelper() {
    setState(() {
      selected++;
    });
  }

  List<DropdownMenuItem<int>> _buildItems() {
    final items = <DropdownMenuItem<int>>[];
    for (final value in const [1, 2]) {
      items.add(DropdownMenuItem<int>(value: value, child: Text('$value')));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      items: _buildItems(),
      value: selected,
      onChanged: (_) {},
    );
  }
}

// A lazily-typed helper: Iterable<Widget> spread into a literal.
// helperReferenceCount: 1; helperWidgetCount: 1 (Text).
class IterableHelperExample extends StatefulWidget {
  const IterableHelperExample({super.key});

  @override
  State<IterableHelperExample> createState() => _IterableHelperExampleState();
}

class _IterableHelperExampleState extends State<IterableHelperExample> {
  int counter = 0;

  void bumpIterableHelper() {
    setState(() {
      counter++;
    });
  }

  Iterable<Widget> _labels() sync* {
    yield Text('$counter');
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [..._labels()]);
  }
}

// A non-widget collection is not a helper: the list carries no widget cost.
// helperReferenceCount: 0; helperWidgetCount: 0.
class ValueListExample extends StatefulWidget {
  const ValueListExample({super.key});

  @override
  State<ValueListExample> createState() => _ValueListExampleState();
}

class _ValueListExampleState extends State<ValueListExample> {
  int counter = 0;

  void bumpValueList() {
    setState(() {
      counter++;
    });
  }

  List<String> _labels() => ['a$counter', 'b'];

  @override
  Widget build(BuildContext context) {
    return Column(children: [Text(_labels().join())]);
  }
}
