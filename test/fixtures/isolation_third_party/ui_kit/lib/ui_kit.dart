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
  Widget build(BuildContext context) => FancyRow(label: label);
}

/// The second hop. `FancyButton` is reached from the scope; this is reached
/// only from `FancyButton`'s body, so it comes across only if the crawl
/// recurses into an inlined third-party widget the way it recurses into a
/// repo-local one.
class FancyRow extends StatelessWidget {
  const FancyRow({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(children: [Text(label), const _FancyDot(), const Divider()]);
}

/// Private, and in the same file as the widget that names it.
///
/// Reachable only through the same-file lookup, which used to be gated on the
/// declaring file being inside the project. A package unit fails that test even
/// while it is the unit being walked, so this is what shows the gate moved.
class _FancyDot extends StatelessWidget {
  const _FancyDot();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 2, height: 2);
}

/// Named after something `package:flutter/material.dart` exports.
///
/// Inlining this would put a body behind a name the transplanted code may have
/// meant Flutter's, so it is stood in for instead. The body is distinctive so a
/// test can tell which of the two happened.
class Divider extends StatelessWidget {
  const Divider({super.key});

  @override
  Widget build(BuildContext context) =>
      Column(children: [Text('ui_kit divider'), Text('second line')]);
}

/// A third-party `StatefulWidget`, so the companion `State` has to be found in
/// a unit outside the project.
///
/// This is the case that matters most: `TreeExtractor` measures the `State`'s
/// build body, not the widget's, so a `StatefulWidget` carried without its
/// `State` contributes nothing and names a type nothing declares.
class FancyPanel extends StatefulWidget {
  const FancyPanel({super.key});

  @override
  State<FancyPanel> createState() => _FancyPanelState();
}

class _FancyPanelState extends State<FancyPanel> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) =>
      Column(children: [Text('panel \$_taps'), const SizedBox(height: 4)]);
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

/// The shape that makes carrying a package's code the worse answer.
///
/// `provider` is the real case. Its `ChangeNotifierProvider<T extends
/// ChangeNotifier?>` type-checks in the app because the repo-local class
/// passed for `T` really does extend `ChangeNotifier`. In an isolated file that
/// class is a stand-in with no supertype at all, so carrying the generic
/// across turns a file that analysed into one that does not, and `spm analyze`
/// skips any file carrying an error.
///
/// A stand-in for this widget renders its type parameters without bounds, so it
/// accepts whatever the scope passes and the file analyses. That is what the
/// fallback pass exists to notice.
abstract class FancyModel {
  String get title;
}

class FancyTypedBox<T extends FancyModel> extends StatelessWidget {
  const FancyTypedBox({super.key, required this.value});

  final T value;

  @override
  Widget build(BuildContext context) => Text(value.title);
}
