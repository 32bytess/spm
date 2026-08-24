import 'package:flutter/material.dart';

/// Image constructions, which the transplant rewrites so the output needs no
/// network and no assets directory.
///
/// The rewrite used to replace the whole node, which erased the widget subtrees
/// inside `errorBuilder` and turned an `ImageProvider` into a widget. Both are
/// visible here.
class ImageHost extends StatefulWidget {
  const ImageHost({super.key});

  @override
  State<ImageHost> createState() => _ImageHostState();
}

class _ImageHostState extends State<ImageHost> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.network(
          'https://example.invalid/a.png',
          width: 24,
          errorBuilder: (context, error, stack) =>
              Column(children: [const Icon(Icons.error), const Text('failed')]),
          loadingBuilder: (context, child, progress) => const Text('loading'),
        ),
        CircleAvatar(
          backgroundImage: NetworkImage('https://example.invalid/b.png'),
        ),
        Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('images/c.png'),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ],
    );
  }
}
