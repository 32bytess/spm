import 'package:flutter/material.dart';

class WithLayoutBuilderExample extends StatefulWidget {
  const WithLayoutBuilderExample({super.key});

  @override
  State<WithLayoutBuilderExample> createState() =>
      _WithLayoutBuilderExampleState();
}

class _WithLayoutBuilderExampleState extends State<WithLayoutBuilderExample> {
  int counter = 0;

  void incrementWithLayoutBuilder() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: constraints.maxWidth * 0.5,
            child: Text('layout: $counter'),
          ),
        );
      },
    );
  }
}

class WithoutLayoutBuilderExample extends StatefulWidget {
  const WithoutLayoutBuilderExample({super.key});

  @override
  State<WithoutLayoutBuilderExample> createState() =>
      _WithoutLayoutBuilderExampleState();
}

class _WithoutLayoutBuilderExampleState
    extends State<WithoutLayoutBuilderExample> {
  int counter = 0;

  void incrementWithoutLayoutBuilder() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text('plain: $counter'),
    );
  }
}
