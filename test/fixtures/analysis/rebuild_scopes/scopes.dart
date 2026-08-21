import 'package:flutter/material.dart';

// Minimal stand-ins for the state-management packages. Detection of consumer
// widgets and builder-pattern widgets is name-based, so the real packages are
// not needed, and a fixture that imported them would fail to resolve and be
// skipped for compile errors.

abstract class ConsumerWidget extends StatelessWidget {
  const ConsumerWidget({super.key});
}

class BlocBuilder<B, S> extends StatelessWidget {
  const BlocBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, S state) builder;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class Obx extends StatelessWidget {
  const Obx(this.builder, {super.key});

  final Widget Function() builder;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// A consumer widget: its build() is a rebuild scope just like a State's.
class ProfileConsumer extends ConsumerWidget {
  const ProfileConsumer({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(padding: const EdgeInsets.all(8), child: Text('profile')),
        const Divider(),
      ],
    );
  }
}

class BuilderHost extends StatefulWidget {
  const BuilderHost({super.key});

  @override
  State<BuilderHost> createState() => _BuilderHostState();
}

// Three builder scopes nested inside one State scope. The State row counts
// their widgets too. A parent rebuild does re-run every callback.
class _BuilderHostState extends State<BuilderHost> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BlocBuilder<int, int>(
          builder: (context, state) => Padding(
            padding: EdgeInsets.all(count.toDouble()),
            child: Text('$state'),
          ),
        ),
        BlocBuilder<String, String>(builder: (context, state) => Text(state)),
        Obx(() => SizedBox(height: count.toDouble(), child: const Divider())),
      ],
    );
  }
}

// A builder given a tear-off has no body at the creation site: no scope row.
class TearOffHost extends StatelessWidget {
  const TearOffHost({super.key});

  Widget _row(BuildContext context, int state) => Text('$state');

  @override
  Widget build(BuildContext context) => BlocBuilder<int, int>(builder: _row);
}
