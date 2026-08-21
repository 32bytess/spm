import 'package:flutter/material.dart';

class _DeepConstChild extends StatelessWidget {
  const _DeepConstChild();

  // helper in child class. Its const Icon IS counted in helperWidgetCount
  // (helper bodies of recursed child widgets are analyzed; const included)
  Widget _buildHelper() => const Icon(Icons.star);

  @override
  Widget build(BuildContext context) {
    return Column(children: [const Text('a'), const Text('b'), _buildHelper()]);
  }
}

// treeNonConstWidgetCount: 3 (non-const, non-helper widgets only)
//   root build: Column(1) + _DeepConstChild(2) = 2 (helper call excluded)
//   child build: Column(1) = 1 (const Text a/b excluded)
// treeConstWidgetCount: 2 (const widgets in build bodies, helpers excluded)
//   root build: 0 const; child build: Text('a') + Text('b') = 2
// helperWidgetCount: 2 (all helper-body widgets, const included)
//   root helper Placeholder(1) + child helper Icon(1) = 2
class ChildWidgetNoRootConstExample extends StatefulWidget {
  const ChildWidgetNoRootConstExample({Key? key}) : super(key: key);

  @override
  State<ChildWidgetNoRootConstExample> createState() =>
      _ChildWidgetNoRootConstExampleState();
}

class _ChildWidgetNoRootConstExampleState
    extends State<ChildWidgetNoRootConstExample> {
  // helper in root state class. Its const Placeholder is NOT counted in treeConstWidgetCount
  Widget _buildRootHelper() => const Placeholder();

  @override
  Widget build(BuildContext context) {
    return Column(children: [_DeepConstChild(), _buildRootHelper()]);
  }
}

// treeNonConstWidgetCount: 3 (non-const, non-helper widgets only)
//   root build: Column(1) + _DeepConstChild(2) = 2 (const Text + helper excluded)
//   child build: Column(1) = 1 (const Text a/b excluded)
// treeConstWidgetCount: 3 (const widgets in build bodies, helpers excluded)
//   root build: const Text('root const') = 1; child build: Text('a') + Text('b') = 2
// helperWidgetCount: 2 (root helper Placeholder + child helper Icon)
class ChildWidgetWithRootConstExample extends StatefulWidget {
  const ChildWidgetWithRootConstExample({Key? key}) : super(key: key);

  @override
  State<ChildWidgetWithRootConstExample> createState() =>
      _ChildWidgetWithRootConstExampleState();
}

class _ChildWidgetWithRootConstExampleState
    extends State<ChildWidgetWithRootConstExample> {
  // helper in root state class. Its const Placeholder is NOT counted in treeConstWidgetCount
  Widget _buildRootHelper() => const Placeholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('root const'),
        _DeepConstChild(),
        _buildRootHelper(),
      ],
    );
  }
}
