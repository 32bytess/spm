import 'package:flutter/material.dart';

// treeNonConstWidgetCount: 1, treeMaxWidgetNestingDepth: 1
class SingleWidgetExample extends StatefulWidget {
  const SingleWidgetExample({Key? key}) : super(key: key);

  @override
  State<SingleWidgetExample> createState() => _SingleWidgetExampleState();
}

class _SingleWidgetExampleState extends State<SingleWidgetExample> {
  int counter = 0;

  void incrementSingleWidget() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text('$counter');
  }
}

// treeNonConstWidgetCount: 2, treeMaxWidgetNestingDepth: 2
class NestedWidgetsExample extends StatefulWidget {
  const NestedWidgetsExample({Key? key}) : super(key: key);

  @override
  State<NestedWidgetsExample> createState() => _NestedWidgetsExampleState();
}

class _NestedWidgetsExampleState extends State<NestedWidgetsExample> {
  int counter = 0;

  void incrementNestedWidgets() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('$counter'));
  }
}

// treeNonConstWidgetCount: 5, treeMaxWidgetNestingDepth: 3
// Column (1) > [Center > Text (3), Text (2), Text (2)]
class ManyWidgetsExample extends StatefulWidget {
  const ManyWidgetsExample({Key? key}) : super(key: key);

  @override
  State<ManyWidgetsExample> createState() => _ManyWidgetsExampleState();
}

class _ManyWidgetsExampleState extends State<ManyWidgetsExample> {
  int counter = 0;

  void incrementManyWidgets() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(child: Text('nested $counter')),
        Text('flat a'),
        Text('flat b'),
      ],
    );
  }
}
