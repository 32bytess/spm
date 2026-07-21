import 'package:flutter/material.dart';

class SimpleBuildExample extends StatefulWidget {
  const SimpleBuildExample({Key? key}) : super(key: key);

  @override
  State<SimpleBuildExample> createState() => _SimpleBuildExampleState();
}

class _SimpleBuildExampleState extends State<SimpleBuildExample> {
  int counter = 0;

  void incrementSimpleBuild() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text('$counter');
  }
}

class ConditionalBuildExample extends StatefulWidget {
  const ConditionalBuildExample({Key? key}) : super(key: key);

  @override
  State<ConditionalBuildExample> createState() =>
      _ConditionalBuildExampleState();
}

class _ConditionalBuildExampleState extends State<ConditionalBuildExample> {
  int counter = 0;

  void incrementConditionalBuild() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (counter > 0) {
      return Text('positive: $counter');
    }
    return Text('zero or negative: $counter');
  }
}

class ComplexBuildExample extends StatefulWidget {
  const ComplexBuildExample({Key? key}) : super(key: key);

  @override
  State<ComplexBuildExample> createState() => _ComplexBuildExampleState();
}

class _ComplexBuildExampleState extends State<ComplexBuildExample> {
  int counter = 0;

  void incrementComplexBuild() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (counter > 10) {
      return Text('high: $counter');
    } else if (counter > 0) {
      return Text('low: $counter');
    }
    return Text('default: $counter');
  }
}

class TernaryBuildExample extends StatefulWidget {
  const TernaryBuildExample({Key? key}) : super(key: key);

  @override
  State<TernaryBuildExample> createState() => _TernaryBuildExampleState();
}

class _TernaryBuildExampleState extends State<TernaryBuildExample> {
  int counter = 0;
  bool isActive = false;

  void incrementTernaryBuild() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        counter > 0 ? Text('positive') : Text('non-positive'),
        isActive ? Text('active') : Text('inactive'),
      ],
    );
  }
}

// treeCyclomaticComplexity: 2 - a for-in loop counts exactly once
class ForInBuildExample extends StatefulWidget {
  const ForInBuildExample({super.key});

  @override
  State<ForInBuildExample> createState() => _ForInBuildExampleState();
}

class _ForInBuildExampleState extends State<ForInBuildExample> {
  List<int> values = [1, 2, 3];

  void addForInValue() {
    setState(() {
      values = [...values, values.length];
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final v in values) {
      rows.add(Text('$v'));
    }
    return Column(children: rows);
  }
}

// treeCyclomaticComplexity: 3 - collection-for and collection-if elements count
class CollectionElementBuildExample extends StatefulWidget {
  const CollectionElementBuildExample({super.key});

  @override
  State<CollectionElementBuildExample> createState() =>
      _CollectionElementBuildExampleState();
}

class _CollectionElementBuildExampleState
    extends State<CollectionElementBuildExample> {
  bool showFlag = false;

  void toggleFlag() {
    setState(() {
      showFlag = !showFlag;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 3; i++) Text('$i'),
        if (showFlag) const Text('flag'),
      ],
    );
  }
}

// treeCyclomaticComplexity: 3 - two pattern switch cases (default excluded)
class SwitchPatternBuildExample extends StatefulWidget {
  const SwitchPatternBuildExample({super.key});

  @override
  State<SwitchPatternBuildExample> createState() =>
      _SwitchPatternBuildExampleState();
}

class _SwitchPatternBuildExampleState extends State<SwitchPatternBuildExample> {
  int counter = 0;

  void incrementSwitchPattern() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (counter) {
      case 0:
        return const Text('zero');
      case 1:
        return const Text('one');
      default:
        return Text('$counter');
    }
  }
}

// treeCyclomaticComplexity: 3 - two switch expression cases
class SwitchExpressionBuildExample extends StatefulWidget {
  const SwitchExpressionBuildExample({super.key});

  @override
  State<SwitchExpressionBuildExample> createState() =>
      _SwitchExpressionBuildExampleState();
}

class _SwitchExpressionBuildExampleState
    extends State<SwitchExpressionBuildExample> {
  int counter = 0;

  void incrementSwitchExpression() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (counter) {
      0 => const Text('zero'),
      _ => Text('$counter'),
    };
  }
}
