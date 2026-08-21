import 'package:flutter/material.dart';

// A custom StatefulWidget child: its rebuild cost lives in the State class's
// build(), which the extractor must find via createState()/extends State<W>.
class CounterTile extends StatefulWidget {
  const CounterTile({super.key});

  @override
  State<CounterTile> createState() => _CounterTileState();
}

class _CounterTileState extends State<CounterTile> {
  int n = 0;

  void bumpCounterTile() {
    setState(() {
      n++;
    });
  }

  Widget _label() => Text('$n');

  @override
  Widget build(BuildContext context) {
    return Container(child: _label());
  }
}

// treeNonConstWidgetCount: 3 (root: Column + CounterTile; child State build:
//   Container. The _label() helper's Text is counted in helper widgets)
// treeMaxWidgetNestingDepth: 3 (CounterTile at depth 2 + Container depth 1)
// helperReferenceCount: 2 (root _title() + child-state _label())
// helperWidgetCount: 2 (_title -> Text, _label -> Text)
class StatefulChildHost extends StatefulWidget {
  const StatefulChildHost({super.key});

  @override
  State<StatefulChildHost> createState() => _StatefulChildHostState();
}

class _StatefulChildHostState extends State<StatefulChildHost> {
  int taps = 0;

  void tapStatefulChildHost() {
    setState(() {
      taps++;
    });
  }

  Widget _title() => Text('taps: $taps');

  @override
  Widget build(BuildContext context) {
    return Column(children: [_title(), CounterTile()]);
  }
}
