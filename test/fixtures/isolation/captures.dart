import 'package:flutter/material.dart';

import 'capture_globals.dart';

/// Mirrors the shape of a real state-management payload: a base type with a
/// loaded subtype the builder promotes to.
class CaptureState {}

class CaptureLoaded extends CaptureState {
  final List<String> items;
  CaptureLoaded(this.items);
}

/// Generic builder mock, so the builder callback's parameter carries a real
/// declared type rather than `dynamic`.
class BlocBuilder<S> extends StatelessWidget {
  final Widget Function(BuildContext, S) builder;
  const BlocBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) => throw UnimplementedError();
}

/// Declares a field called `context`, as nMobile's `BottomDialog` does. Copying
/// it onto the generated `State` would shadow `State.context`.
class CaptureDialog {
  late BuildContext context;

  String describe() => 'dialog';
}

class CaptureHost extends StatefulWidget {
  const CaptureHost({super.key});

  @override
  State<CaptureHost> createState() => _CaptureHostState();
}

class _CaptureHostState extends State<CaptureHost> {
  final CaptureDialog dialog = CaptureDialog();

  /// `onlyActive` and `heading` are captured by the builder below: they belong
  /// to this method, not to the callback, so they do not travel with the scope.
  Widget buildList({bool onlyActive = false, String heading = 'Items'}) {
    return BlocBuilder<CaptureState>(
      builder: (context, state) {
        if (state is CaptureLoaded) {
          final items = onlyActive
              ? state.items.where((i) => i.isNotEmpty).toList()
              : state.items;
          return Column(
            children: [
              Text(heading, style: TextStyle(color: captureTheme.tint)),
              for (final item in items) Text('$item ${dialog.describe()}'),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  @override
  Widget build(BuildContext context) => buildList();
}
