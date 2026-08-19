import 'package:flutter/material.dart';

/// Same as `closure/card.dart`, except `UndefinedBox` does not exist.
///
/// The error is LOCAL: `MyCard`'s public type is unchanged, so `screen.dart`
/// still resolves cleanly and still passes the scanned-file gate. Its row is
/// emitted with a widget count short by one and a depth short by one, because
/// the unresolved call is not recognised as a widget. Nothing about the row
/// itself reveals that — which is what `unresolvedDependencies` is for.
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
          UndefinedBox(children: [Text('a'), Text('b')]),
        ],
      ),
    );
  }
}
