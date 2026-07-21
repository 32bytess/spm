part of 'library.dart';

class PartLibraryExample extends StatefulWidget {
  const PartLibraryExample({super.key});

  @override
  State<PartLibraryExample> createState() => _PartLibraryExampleState();
}

class _PartLibraryExampleState extends State<PartLibraryExample> {
  Widget _body() =>
      Padding(padding: const EdgeInsets.all(4), child: _PartChild());

  @override
  Widget build(BuildContext context) => _body();
}

class _PartChild extends StatelessWidget {
  const _PartChild();

  @override
  Widget build(BuildContext context) => Text('part child');
}
