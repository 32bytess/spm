// ignore_for_file: unused_import
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class SampleWidget extends StatefulWidget {
  const SampleWidget({super.key});

  @override
  State<SampleWidget> createState() => _SampleWidgetState();
}

class _SampleWidgetState extends State<SampleWidget> {
  final FocusNode focusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: KeyboardListener(
        focusNode: focusNode,
        child: const Text('Header'),
      ),
    );
  }
}
