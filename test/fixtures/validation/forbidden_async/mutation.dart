// ignore_for_file: unused_element
import 'package:flutter/material.dart';

class SampleWidget extends StatefulWidget {
  const SampleWidget({super.key});

  @override
  State<SampleWidget> createState() => _SampleWidgetState();
}

class _SampleWidgetState extends State<SampleWidget> {
  late final List<int> items;
  int selected = 0;

  @override
  void initState() {
    super.initState();
    items = List.generate(10, (i) => i * 2);
  }

  Future<void> _warmUp() async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const Text('Header'),
          const Icon(Icons.star),
          for (final item in items) Text('Row $item'),
        ],
      ),
    );
  }
}
