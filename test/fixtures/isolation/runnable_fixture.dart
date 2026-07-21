import 'package:flutter/material.dart';

class WidgetWithFields extends StatefulWidget {
  final String title;
  final int count;

  const WidgetWithFields({super.key, required this.title, this.count = 0});

  @override
  State<WidgetWithFields> createState() => _WidgetWithFieldsState();
}

class _WidgetWithFieldsState extends State<WidgetWithFields> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(widget.title),
        Text('Count: ${widget.count}'),
        const SubWidget(label: 'Child'),
      ],
    );
  }
}

class SubWidget extends StatelessWidget {
  final String label;
  const SubWidget({super.key, required this.label});
  @override
  Widget build(BuildContext context) => Text(label);
}
