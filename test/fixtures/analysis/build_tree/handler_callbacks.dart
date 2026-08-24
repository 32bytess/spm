import 'package:flutter/material.dart';

// Minimal stand-in for a state-management builder widget, as in
// rebuild_scopes/scopes.dart: detection is name-based, and importing the real
// package would leave this fixture unresolvable and skipped.
class Obx extends StatelessWidget {
  const Obx(this.builder, {super.key});

  final Widget Function() builder;

  @override
  Widget build(BuildContext context) => builder();
}

// Control flow inside an event handler runs on interaction, never inside the
// traced rebuild window.
// treeCyclomaticComplexity: 1 (the if and the && in onPressed do not count).
class HandlerComplexityExample extends StatefulWidget {
  const HandlerComplexityExample({super.key});

  @override
  State<HandlerComplexityExample> createState() =>
      _HandlerComplexityExampleState();
}

class _HandlerComplexityExampleState extends State<HandlerComplexityExample> {
  int counter = 0;
  bool enabled = true;

  void bumpHandlerComplexity() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        if (enabled && counter > 0) {
          counter--;
        } else {
          counter++;
        }
      },
      child: Text('$counter'),
    );
  }
}

// A widget built inside a handler is never mounted by a rebuild.
// treeNonConstWidgetCount: 2 (TextButton + Text), depth 2,
// treeConstWidgetCount 0 and valueObjectAllocCount 0.
class HandlerWidgetExample extends StatefulWidget {
  const HandlerWidgetExample({super.key});

  @override
  State<HandlerWidgetExample> createState() => _HandlerWidgetExampleState();
}

class _HandlerWidgetExampleState extends State<HandlerWidgetExample> {
  int counter = 0;

  void bumpHandlerWidget() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        showDialog<void>(
          context: context,
          builder: (dialogContext) => Container(
            padding: EdgeInsets.all(16),
            child: Column(children: [Text('$counter'), const Divider()]),
          ),
        );
      },
      child: Text('open'),
    );
  }
}

// The severe case: a page pushed from a handler must not merge its build tree
// into this scope. treeNonConstWidgetCount: 2, and walkedWidgetClasses names
// no _PushedPage.
class HandlerNavigationExample extends StatefulWidget {
  const HandlerNavigationExample({super.key});

  @override
  State<HandlerNavigationExample> createState() =>
      _HandlerNavigationExampleState();
}

class _HandlerNavigationExampleState extends State<HandlerNavigationExample> {
  int counter = 0;

  void bumpHandlerNavigation() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (routeContext) => _PushedPage()),
      ),
      child: Text('go'),
    );
  }
}

// A whole other screen. None of it belongs to the scope above.
class _PushedPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('pushed')),
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Text('one'),
            Text('two'),
            Row(children: [Icon(Icons.star), Text('three')]),
          ],
        ),
      ),
    );
  }
}

// A local function reached only through a handler closure contributes nothing.
// treeNonConstWidgetCount: 2 (TextButton + Text).
class HandlerLocalFnExample extends StatefulWidget {
  const HandlerLocalFnExample({super.key});

  @override
  State<HandlerLocalFnExample> createState() => _HandlerLocalFnExampleState();
}

class _HandlerLocalFnExampleState extends State<HandlerLocalFnExample> {
  int counter = 0;

  void bumpHandlerLocalFn() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget badge() => Container(color: Colors.red, child: Text('$counter'));

    return TextButton(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => badge(),
      ),
      child: Text('badge'),
    );
  }
}

// Same thing through a tear-off: `onPressed: submit` is a call site that fires
// on interaction, so submit's body stays out too.
// treeNonConstWidgetCount: 2, valueObjectAllocCount 0.
class HandlerTearOffExample extends StatefulWidget {
  const HandlerTearOffExample({super.key});

  @override
  State<HandlerTearOffExample> createState() => _HandlerTearOffExampleState();
}

class _HandlerTearOffExampleState extends State<HandlerTearOffExample> {
  final List<Widget> pending = [];
  int counter = 0;

  void bumpHandlerTearOff() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    void submit() {
      pending.add(
        Container(padding: EdgeInsets.all(4), child: Text('$counter')),
      );
    }

    return TextButton(onPressed: submit, child: Text('submit'));
  }
}

// Regression guard: builder callbacks are build work and still count, named
// and positional alike.
// treeNonConstWidgetCount: 9, iterationWidgetCount 2 (the itemBuilder body
// runs once per visible element), treeMaxWidgetNestingDepth 5.
class BuilderCallbacksExample extends StatefulWidget {
  const BuilderCallbacksExample({super.key});

  @override
  State<BuilderCallbacksExample> createState() =>
      _BuilderCallbacksExampleState();
}

class _BuilderCallbacksExampleState extends State<BuilderCallbacksExample> {
  int counter = 0;

  void bumpBuilderCallbacks() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (layoutContext, constraints) => Text('$counter'),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            itemCount: 3,
            itemBuilder: (itemContext, index) =>
                Padding(padding: EdgeInsets.all(2), child: Text('$index')),
          ),
        ),
        Obx(() => Text('$counter')),
      ],
    );
  }
}
