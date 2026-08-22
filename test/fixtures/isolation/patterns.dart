import 'package:flutter/material.dart';
import 'parted_host.dart';
import 'external_deps.dart';

// 1. State subclass (Whole tree)
class MyStateful extends StatefulWidget {
  const MyStateful({super.key});
  @override
  State<MyStateful> createState() => _MyStatefulState();
}

class _MyStatefulState extends State<MyStateful> {
  int _counter = 0;

  void _increment() {
    setState(() {
      _counter++;
    });
    externalHelper();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Count: $_counter', style: const TextStyle(color: kExternalColor)),
        const ExternalChild(),
        const ExternalStateful(),
        const PartedWidget(),
        const ExternalCard(),
        ...buildExternalItems(context),
        CustomPaint(painter: ExternalPainter()),
        DecoratedBox(decoration: buildExternalDecoration()),
        // ShapeDecoration, not BoxDecoration: `border:` wants a BoxBorder, and
        // a ShapeBorder there is a type error the fixture used to carry and the
        // transplant faithfully copied across.
        Container(decoration: const ShapeDecoration(shape: ExternalShape())),
        ExternalStyles.divider(),
        Text(ExternalService().label(_counter)),
        ElevatedButton(onPressed: _increment, child: const Text('Add')),
      ],
    );
  }
}

// Mocking Bloc/Get/Provider for harvesting detection
class ConsumerWidget {
  Widget build(BuildContext context, dynamic ref) => Container();
}

class Consumer extends StatelessWidget {
  final Widget Function(BuildContext, dynamic, Widget?) builder;
  const Consumer({super.key, required this.builder});
  @override
  Widget build(BuildContext context) => builder(context, null, null);
}

class BlocBuilder extends StatelessWidget {
  final Widget Function(BuildContext, dynamic) builder;
  const BlocBuilder({super.key, required this.builder});
  @override
  Widget build(BuildContext context) => builder(context, null);
}

class Obx extends StatelessWidget {
  final Widget Function() builder;
  const Obx(this.builder, {super.key});
  @override
  Widget build(BuildContext context) => builder();
}

// 2. ConsumerWidget
class MyConsumerWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, dynamic ref) {
    return const Text('Consumer');
  }
}

// 3. Various inline builders
class BuilderExamples extends StatelessWidget {
  const BuilderExamples({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Consumer(
          builder: (context, value, child) {
            return const Text('Inline Consumer');
          },
        ),
        BlocBuilder(builder: (context, state) => const Text('Inline Bloc')),
        Obx(() => const Text('Inline Obx')),
      ],
    );
  }
}

// 4. A builder handed a tear-off rather than a closure. Not a scope in either
// command: there is no callback body at the creation site to transplant or to
// measure. `isolate` used to take it anyway, and since the scope node is an
// identifier the transplant fell through to its expression fallback and wrote
// `return _row;`, a function returned where a `Widget` belongs.
class TearOffBuilderHost extends StatelessWidget {
  const TearOffBuilderHost({super.key});

  Widget _row(BuildContext context, dynamic state) => const Text('tear-off');

  @override
  Widget build(BuildContext context) => BlocBuilder(builder: _row);
}
