import 'package:flutter/material.dart';
import 'package:spm/spm.dart';

/// Minimal example of a widget state after SPM instrumentation.
///
/// In normal use, the `spm inject` command adds the `SpmState` superclass and
/// `instanceId` getter for each target `State` class listed in the analysis
/// JSONL manifest.
class CounterExample extends StatefulWidget {
  const CounterExample({super.key});

  @override
  State<CounterExample> createState() => _CounterExampleState();
}

class _CounterExampleState extends SpmState<CounterExample> {
  int _count = 0;

  @override
  String get instanceId => 'example-counter';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Count: $_count'),
        ElevatedButton(
          onPressed: () => setState(() => _count++),
          child: const Text('Increment'),
        ),
      ],
    );
  }
}
