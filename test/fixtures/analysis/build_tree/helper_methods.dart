import 'package:flutter/material.dart';

// helperReferenceCount: 0
class NoHelpersExample extends StatefulWidget {
  const NoHelpersExample({super.key});

  @override
  State<NoHelpersExample> createState() => _NoHelpersExampleState();
}

class _NoHelpersExampleState extends State<NoHelpersExample> {
  int counter = 0;

  void incrementNoHelpers() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text('$counter');
  }
}

// helperReferenceCount: 1
class SingleHelperExample extends StatefulWidget {
  const SingleHelperExample({super.key});

  @override
  State<SingleHelperExample> createState() => _SingleHelperExampleState();
}

class _SingleHelperExampleState extends State<SingleHelperExample> {
  int counter = 0;

  void incrementSingleHelper() {
    setState(() {
      counter++;
    });
  }

  Widget buildContent() {
    return Text('$counter');
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [buildContent()]);
  }
}

// helperReferenceCount: 3
class MultipleHelpersExample extends StatefulWidget {
  const MultipleHelpersExample({super.key});

  @override
  State<MultipleHelpersExample> createState() => _MultipleHelpersExampleState();
}

class _MultipleHelpersExampleState extends State<MultipleHelpersExample> {
  int counter = 0;

  void incrementMultipleHelpers() {
    setState(() {
      counter++;
    });
  }

  Widget buildHeader() {
    return const Text('Header');
  }

  Widget _buildBody() {
    return Text('Body $counter');
  }

  Widget buildFooter() {
    return const Text('Footer');
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [buildHeader(), _buildBody(), buildFooter()]);
  }
}

// helperReferenceCount: 1 - non-build-named method returning Widget
class NonBuildNamedHelperExample extends StatefulWidget {
  const NonBuildNamedHelperExample({super.key});

  @override
  State<NonBuildNamedHelperExample> createState() =>
      _NonBuildNamedHelperExampleState();
}

class _NonBuildNamedHelperExampleState
    extends State<NonBuildNamedHelperExample> {
  int counter = 0;

  void incrementNonBuildNamed() {
    setState(() {
      counter++;
    });
  }

  Widget createCard() => Card(child: Text('$counter'));

  @override
  Widget build(BuildContext context) {
    return Column(children: [createCard()]);
  }
}

// helperReferenceCount: 0 - build-named method returning String (not Widget)
class BuildNamedNonWidgetExample extends StatefulWidget {
  const BuildNamedNonWidgetExample({super.key});

  @override
  State<BuildNamedNonWidgetExample> createState() =>
      _BuildNamedNonWidgetExampleState();
}

class _BuildNamedNonWidgetExampleState
    extends State<BuildNamedNonWidgetExample> {
  int counter = 0;

  void incrementBuildNamedNonWidget() {
    setState(() {
      counter++;
    });
  }

  String buildTitle() => 'Count: $counter';

  @override
  Widget build(BuildContext context) {
    return Text(buildTitle());
  }
}

// helperReferenceCount: 0 - Widget-returning helper called in preamble
class PreambleHelperExample extends StatefulWidget {
  const PreambleHelperExample({super.key});

  @override
  State<PreambleHelperExample> createState() => _PreambleHelperExampleState();
}

class _PreambleHelperExampleState extends State<PreambleHelperExample> {
  int counter = 0;

  void incrementPreambleHelper() {
    setState(() {
      counter++;
    });
  }

  Widget buildCard() => Card(child: Text('$counter'));

  @override
  Widget build(BuildContext context) {
    final card = buildCard();
    return Column(children: [card]);
  }
}

// helperWidgetCount: 3, helperMaxWidgetNestingDepth: 3
class DeepHelperExample extends StatefulWidget {
  const DeepHelperExample({super.key});

  @override
  State<DeepHelperExample> createState() => _DeepHelperExampleState();
}

class _DeepHelperExampleState extends State<DeepHelperExample> {
  int counter = 0;

  void incrementDeepHelper() {
    setState(() {
      counter++;
    });
  }

  Widget buildDeep() {
    return Column(
      children: [
        Row(children: [Text('$counter')]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return buildDeep();
  }
}

// helperWidgetCount: 1, helperMaxWidgetNestingDepth: 1
// (same helper called twice, body counted once via deduplication)
class RepeatedHelperCallExample extends StatefulWidget {
  const RepeatedHelperCallExample({super.key});

  @override
  State<RepeatedHelperCallExample> createState() =>
      _RepeatedHelperCallExampleState();
}

class _RepeatedHelperCallExampleState extends State<RepeatedHelperCallExample> {
  int counter = 0;

  void incrementRepeated() {
    setState(() {
      counter++;
    });
  }

  Widget buildItem() => Text('$counter');

  @override
  Widget build(BuildContext context) {
    return Column(children: [buildItem(), buildItem()]);
  }
}

// helperReferenceCount: 1 - Widget-returning helper as direct return value
class DirectReturnHelperExample extends StatefulWidget {
  const DirectReturnHelperExample({super.key});

  @override
  State<DirectReturnHelperExample> createState() =>
      _DirectReturnHelperExampleState();
}

class _DirectReturnHelperExampleState extends State<DirectReturnHelperExample> {
  int counter = 0;

  void incrementDirectReturn() {
    setState(() {
      counter++;
    });
  }

  Widget buildContent() => Text('$counter');

  @override
  Widget build(BuildContext context) {
    return buildContent();
  }
}

// helperReferenceCount: 0 - firstWhere on a List<Widget> is an O(N)
// collection op, not a helper, even though its static type is Widget
class WidgetListOpExample extends StatefulWidget {
  const WidgetListOpExample({super.key});

  @override
  State<WidgetListOpExample> createState() => _WidgetListOpExampleState();
}

class _WidgetListOpExampleState extends State<WidgetListOpExample> {
  List<Widget> panels = [const Text('a'), const SizedBox()];

  void addPanel() {
    setState(() {
      panels = [...panels, const Text('b')];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [panels.firstWhere((w) => w is Text)]);
  }
}

// helperReferenceCount: 0 - make() is a function-typed variable invocation
// (not a method call), and makeCard() inside the closure body is not a
// build-body call site
class PreambleClosureHelperExample extends StatefulWidget {
  const PreambleClosureHelperExample({super.key});

  @override
  State<PreambleClosureHelperExample> createState() =>
      _PreambleClosureHelperExampleState();
}

class _PreambleClosureHelperExampleState
    extends State<PreambleClosureHelperExample> {
  int counter = 0;

  void incrementPreambleClosure() {
    setState(() {
      counter++;
    });
  }

  Widget makeCard() => Card(child: Text('$counter'));

  @override
  Widget build(BuildContext context) {
    final Widget Function() make = () {
      return makeCard();
    };
    return Row(children: [make()]);
  }
}

// helperReferenceCount: 0 - a foreign build() method is never a helper and
// must not re-enter this class's own build body via helper resolution
class CardTemplate {
  const CardTemplate(this.label);
  final String label;

  Widget build(BuildContext context) => Card(child: Text(label));
}

class TemplateBuildCallExample extends StatefulWidget {
  const TemplateBuildCallExample({super.key});

  @override
  State<TemplateBuildCallExample> createState() =>
      _TemplateBuildCallExampleState();
}

class _TemplateBuildCallExampleState extends State<TemplateBuildCallExample> {
  final CardTemplate template = const CardTemplate('x');
  int counter = 0;

  void incrementTemplate() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [template.build(context), Text('$counter')]);
  }
}
