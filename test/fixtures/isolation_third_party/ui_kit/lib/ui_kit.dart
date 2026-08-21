import 'package:flutter/material.dart';

/// Stands in for a third-party widget package, the kind an app pulls in for
/// icons, text, or buttons. A stand-in for one of these has to
/// keep `Widget` in its supertype chain: `BuildMetricsVisitor` decides between
/// `widgetCount` and `valueObjectAllocCount` by walking that chain, so a bare
/// `class FancyButton {}` would resolve cleanly and be counted as a value
/// object.
class FancyButton extends StatelessWidget {
  const FancyButton({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}

/// The other half of the same bucket: the plain data types a charting or
/// layout package exposes, which
/// really are value objects and must not acquire a `Widget` supertype.
class FancySpec {
  const FancySpec({this.weight = 1});

  final int weight;
}
