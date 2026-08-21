import 'dart:convert' show jsonEncode;
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A scope whose body only compiles under the prefix its import declared.
///
/// Nothing else in this fixture tree imports a `dart:` library, prefixed or
/// otherwise, which is why the transplant could drop `as math` unnoticed.
class PrefixedImportsWidget extends StatefulWidget {
  const PrefixedImportsWidget({super.key});

  @override
  State<PrefixedImportsWidget> createState() => _PrefixedImportsWidgetState();
}

class _PrefixedImportsWidgetState extends State<PrefixedImportsWidget> {
  final math.Random _rand = math.Random();

  @override
  Widget build(BuildContext context) {
    final angle = -math.pi / 2 + _rand.nextDouble();
    return Transform.rotate(
      angle: angle,
      child: Text(jsonEncode({'max': math.max(1, 2)})),
    );
  }
}
