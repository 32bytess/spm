import 'package:flutter/material.dart';

/// The scope that builds this lives in `screen.dart`. Its widgets are merged
/// into that scope's metrics, so this file is part of that row even though the
/// row's `filePath` never names it.
class MyCard extends StatelessWidget {
  const MyCard({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Text(title),
          Icon(Icons.star),
          Row(children: [Text('a'), Text('b')]),
        ],
      ),
    );
  }
}
