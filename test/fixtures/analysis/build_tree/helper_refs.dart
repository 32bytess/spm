import 'package:flutter/material.dart';

// A top-level widget function: a helper that lives outside any class.
Widget buildBanner() {
  return DecoratedBox(
    decoration: const BoxDecoration(),
    child: Text('banner'),
  );
}

// Helper referenced as a METHOD TEAR-OFF: items.map(_buildRow) — no
// invocation syntax anywhere, but _buildRow runs per element per rebuild.
// helperReferenceCount: 1; helperWidgetCount: 2 (Padding + Text).
class TearOffExample extends StatefulWidget {
  const TearOffExample({super.key});

  @override
  State<TearOffExample> createState() => _TearOffExampleState();
}

class _TearOffExampleState extends State<TearOffExample> {
  List<int> items = [1, 2];

  void addTearOffItem() {
    setState(() {
      items = [...items, items.length];
    });
  }

  Widget _buildRow(int i) =>
      Padding(padding: const EdgeInsets.all(1), child: Text('$i'));

  @override
  Widget build(BuildContext context) {
    return Column(children: items.map(_buildRow).toList());
  }
}

// Helper is an explicit widget-returning GETTER.
// helperReferenceCount: 1; helperWidgetCount: 2 (SizedBox + Text).
class GetterHelperExample extends StatefulWidget {
  const GetterHelperExample({super.key});

  @override
  State<GetterHelperExample> createState() => _GetterHelperExampleState();
}

class _GetterHelperExampleState extends State<GetterHelperExample> {
  int counter = 0;

  void bumpGetterHelper() {
    setState(() {
      counter++;
    });
  }

  Widget get _header => SizedBox(child: Text('h$counter'));

  @override
  Widget build(BuildContext context) {
    return Column(children: [_header]);
  }
}

// Helper is a TOP-LEVEL widget function of the same library.
// helperReferenceCount: 1; helperWidgetCount: 2 (DecoratedBox + Text).
class TopLevelFnExample extends StatefulWidget {
  const TopLevelFnExample({super.key});

  @override
  State<TopLevelFnExample> createState() => _TopLevelFnExampleState();
}

class _TopLevelFnExampleState extends State<TopLevelFnExample> {
  int counter = 0;

  void bumpTopLevelFn() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: buildBanner());
  }
}

// A plain widget FIELD is data, not a helper: referencing it must not count.
// helperReferenceCount: 0; helperWidgetCount: 0.
class FieldWidgetExample extends StatefulWidget {
  const FieldWidgetExample({super.key});

  @override
  State<FieldWidgetExample> createState() => _FieldWidgetExampleState();
}

class _FieldWidgetExampleState extends State<FieldWidgetExample> {
  final Widget _cached = const SizedBox();
  int counter = 0;

  void bumpFieldWidget() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [_cached, Text('$counter')]);
  }
}
