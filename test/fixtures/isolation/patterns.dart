import 'package:flutter/material.dart';
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
        const ExternalCard(),
        ...buildExternalItems(context),
        CustomPaint(painter: ExternalPainter()),
        DecoratedBox(decoration: buildExternalDecoration()),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: ExternalShape(),
          ),
        ),
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
