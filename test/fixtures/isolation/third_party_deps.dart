import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// A scope whose dependency lives in a real third-party package.
///
/// `dependency_extractor_visitor.dart` refuses to import anything outside
/// `package:flutter` and `dart:`, so `Vector3` used to leave the isolated file
/// with an undefined name, and `spm analyze` skips any file carrying one.
/// It is not a widget, so its stand-in must stay a plain class: a `Widget`
/// supertype here would move the allocation out of `valueObjectAllocCount`.
class ThirdPartyHost extends StatefulWidget {
  const ThirdPartyHost({super.key});

  @override
  State<ThirdPartyHost> createState() => ThirdPartyHostState();
}

class ThirdPartyHostState extends State<ThirdPartyHost> {
  final Vector3 _offset = Vector3(1, 2, 3);

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.all(_offset.x), child: Text('${_offset.y}'));
}
