import 'package:flutter/material.dart';

/// The two shapes that used to strand a constructor inside
/// `_GeneratedWidgetState`, where its name no longer matches the enclosing
/// class and Dart reads it as a bodiless method.

/// Shape 1: a `State` subclass that declares its own constructor with a field
/// formal parameter. Dropping the constructor leaves `_seed` unassigned, so the
/// field has to become `late`.
class CtorStateful extends StatefulWidget {
  const CtorStateful({super.key});
  @override
  State<CtorStateful> createState() => CtorStatefulState('seed');
}

class CtorStatefulState extends State<CtorStateful> {
  final String _seed;
  int _hits = 0;

  void _bump() => setState(() => _hits++);

  CtorStatefulState(this._seed);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(_seed),
        Text('$_hits'),
        TextButton(onPressed: _bump, child: const Text('bump')),
      ],
    );
  }
}

/// Shape 2: a non-`State` scope whose own constructor used to be copied into
/// the generated State class verbatim. This is the ConsumerWidget majority.
class CtorConsumer extends ConsumerWidget {
  const CtorConsumer({super.key});

  @override
  Widget build(BuildContext context, dynamic ref) {
    return const Padding(padding: EdgeInsets.all(8), child: Text('consumer'));
  }
}

/// Shape 3: an initialiser list rather than a field formal parameter. Same
/// consequence for the field, reached by a different syntax.
class CtorInitList extends StatefulWidget {
  const CtorInitList({super.key});
  @override
  State<CtorInitList> createState() => CtorInitListState(21);
}

class CtorInitListState extends State<CtorInitList> {
  final int _doubled;

  CtorInitListState(int base) : _doubled = base * 2;

  @override
  Widget build(BuildContext context) => Text('$_doubled');
}

/// Minimal stand-in so the fixture resolves without Riverpod, mirroring the
/// mock in `patterns.dart`.
class ConsumerWidget {
  const ConsumerWidget({this.key});

  final Key? key;

  Widget build(BuildContext context, dynamic ref) => Container();
}
