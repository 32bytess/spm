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

/// A base class living in the same third-party package as [FancyController].
///
/// It exists so that a member the scope calls is *inherited* rather than
/// declared: the reference resolves to `FancyBase.tap`, so keying the member to
/// the class that declares it puts `tap` on the wrong stand-in and leaves
/// `FancyController.tap()` undefined.
class FancyBase {
  void tap() {}
}

/// Large enough that its whole surface is never rendered, so what the stand-in
/// carries is decided by what the scope reached.
class FancyController extends FancyBase {
  void pad0() {}
  void pad1() {}
  void pad2() {}
  void pad3() {}
  void pad4() {}
  void pad5() {}
  void pad6() {}
  void pad7() {}
  void pad8() {}
  void pad9() {}
  void pad10() {}
  void pad11() {}
  void pad12() {}
  void pad13() {}
  void pad14() {}
  void pad15() {}
  void pad16() {}
  void pad17() {}
  void pad18() {}
  void pad19() {}
  void pad20() {}
  void pad21() {}
  void pad22() {}
  void pad23() {}
  void pad24() {}
  void pad25() {}
  void pad26() {}
  void pad27() {}
  void pad28() {}
  void pad29() {}
  void pad30() {}
  void pad31() {}
  void pad32() {}
  void pad33() {}
  void pad34() {}
  void pad35() {}
  void pad36() {}
  void pad37() {}
  void pad38() {}
  void pad39() {}
  void pad40() {}
}
