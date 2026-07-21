import 'package:flutter/material.dart';

class ListViewBuilderExample extends StatefulWidget {
  const ListViewBuilderExample({super.key});

  @override
  State<ListViewBuilderExample> createState() => _ListViewBuilderExampleState();
}

class _ListViewBuilderExampleState extends State<ListViewBuilderExample> {
  final List<String> items = ['A', 'B', 'C'];

  void addItemWithListViewBuilder() {
    setState(() {
      items.add('X');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        return ListTile(
          title: Text(items[index]),
          onTap: addItemWithListViewBuilder,
        );
      },
    );
  }
}

class ListViewNoBuilderExample extends StatefulWidget {
  const ListViewNoBuilderExample({super.key});

  @override
  State<ListViewNoBuilderExample> createState() =>
      _ListViewNoBuilderExampleState();
}

class _ListViewNoBuilderExampleState extends State<ListViewNoBuilderExample> {
  final List<String> items = ['A', 'B', 'C'];

  void addItemWithoutBuilder() {
    setState(() {
      items.add('Y');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: items
          .map(
            (item) => ListTile(title: Text(item), onTap: addItemWithoutBuilder),
          )
          .toList(),
    );
  }
}

class GridViewBuilderExample extends StatefulWidget {
  const GridViewBuilderExample({super.key});

  @override
  State<GridViewBuilderExample> createState() => _GridViewBuilderExampleState();
}

class _GridViewBuilderExampleState extends State<GridViewBuilderExample> {
  final List<int> items = List<int>.generate(4, (index) => index);

  void addItemWithGridViewBuilder() {
    setState(() {
      items.add(items.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: addItemWithGridViewBuilder,
          child: Card(child: Center(child: Text('Item ${items[index]}'))),
        );
      },
    );
  }
}
