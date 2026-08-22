part of 'parted_host.dart';

class PartedWidget extends StatefulWidget {
  const PartedWidget({super.key});

  @override
  State<PartedWidget> createState() => _PartedWidgetState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}

class _PartedWidgetState extends State<PartedWidget> {
  @override
  Widget build(BuildContext context) => const Text('parted');
}
