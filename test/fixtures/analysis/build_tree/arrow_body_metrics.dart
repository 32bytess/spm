import 'package:flutter/material.dart';

class ArrowConstReturnExample extends StatefulWidget {
  const ArrowConstReturnExample({super.key});
  @override
  State<ArrowConstReturnExample> createState() =>
      _ArrowConstReturnExampleState();
}

class _ArrowConstReturnExampleState extends State<ArrowConstReturnExample> {
  int counter = 0;

  void incrementArrowConstReturn() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) => const Text('static');
}

class ArrowHelperRootExample extends StatefulWidget {
  const ArrowHelperRootExample({super.key});
  @override
  State<ArrowHelperRootExample> createState() =>
      _ArrowHelperRootExampleState();
}

class _ArrowHelperRootExampleState extends State<ArrowHelperRootExample> {
  int counter = 0;

  void incrementArrowHelperRoot() {
    setState(() {
      counter++;
    });
  }

  Widget _body() => Column(children: [Text('$counter'), Text('again')]);

  @override
  Widget build(BuildContext context) => _body();
}

class ClosureConstReturnExample extends StatefulWidget {
  const ClosureConstReturnExample({super.key});
  @override
  State<ClosureConstReturnExample> createState() =>
      _ClosureConstReturnExampleState();
}

class _ClosureConstReturnExampleState extends State<ClosureConstReturnExample> {
  int counter = 0;

  void incrementClosureConstReturn() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$counter'),
        Builder(
          builder: (context) {
            return const SizedBox();
          },
        ),
        Builder(builder: (context) => const SizedBox()),
      ],
    );
  }
}
