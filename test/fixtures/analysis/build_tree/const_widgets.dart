import 'package:flutter/material.dart';

// rootBuildReturnsConstWidget: true, treeConstWidgetCount: 1
// const Center(child: Text) is one canonicalized const unit (const boundary)
class AllConstExample extends StatefulWidget {
  const AllConstExample({Key? key}) : super(key: key);

  @override
  State<AllConstExample> createState() => _AllConstExampleState();
}

class _AllConstExampleState extends State<AllConstExample> {
  int counter = 0;

  void incrementAllConst() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('hello'));
  }
}

// rootBuildReturnsConstWidget: false, treeConstWidgetCount: 0
// No const widgets, return is non-const
class NoConstExample extends StatefulWidget {
  const NoConstExample({Key? key}) : super(key: key);

  @override
  State<NoConstExample> createState() => _NoConstExampleState();
}

class _NoConstExampleState extends State<NoConstExample> {
  int counter = 0;

  void incrementNoConst() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('$counter'));
  }
}

// rootBuildReturnsConstWidget: false, treeConstWidgetCount: 1
// Center is non-const (return), const Text inside is one const unit
class MixedConstExample extends StatefulWidget {
  const MixedConstExample({Key? key}) : super(key: key);

  @override
  State<MixedConstExample> createState() => _MixedConstExampleState();
}

class _MixedConstExampleState extends State<MixedConstExample> {
  int counter = 0;

  void incrementMixedConst() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: const Text('static'));
  }
}

// rootBuildReturnsConstWidget: false, treeConstWidgetCount: 1
// The const return lives inside a preamble closure, not the build body root
class PreambleClosureConstExample extends StatefulWidget {
  const PreambleClosureConstExample({super.key});

  @override
  State<PreambleClosureConstExample> createState() =>
      _PreambleClosureConstExampleState();
}

class _PreambleClosureConstExampleState
    extends State<PreambleClosureConstExample> {
  int counter = 0;

  void incrementPreambleClosureConst() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget Function() placeholder = () => const SizedBox();
    return Column(children: [placeholder(), Text('$counter')]);
  }
}
