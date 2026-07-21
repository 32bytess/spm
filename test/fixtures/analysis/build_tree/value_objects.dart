import 'package:flutter/material.dart';

// Value objects (EdgeInsets, TextStyle) are NOT widgets: they must be excluded
// from both treeNonConstWidgetCount and treeMaxWidgetNestingDepth.
//
// treeNonConstWidgetCount: 2
//   Container(1) + Text(1) = 2
//   EdgeInsets.all, EdgeInsets.symmetric, TextStyle are value objects -> excluded
// treeMaxWidgetNestingDepth: 2
//   Container > Text = 2 (value-object arguments add no depth)
class ValueObjectExample extends StatefulWidget {
  const ValueObjectExample({Key? key}) : super(key: key);

  @override
  State<ValueObjectExample> createState() => _ValueObjectExampleState();
}

class _ValueObjectExampleState extends State<ValueObjectExample> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8),
      margin: EdgeInsets.symmetric(horizontal: 4),
      child: Text('hi', style: TextStyle(fontSize: 12)),
    );
  }
}
