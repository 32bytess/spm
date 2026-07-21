import 'package:flutter/material.dart';

class _FooState extends State<Foo> {
  int counter = 0;

  void increment() {
    setState(() {
      counter++;
    });
  }

  @override
  Widget build(BuildContext context) => Text('$counter');
}

class Foo extends StatefulWidget {
  @override
  State<Foo> createState() => _FooState();
}

class _BarState extends State<Bar> {
  bool active = false;

  void toggle() {
    setState(() {
      active = !active;
    });
  }

  @override
  Widget build(BuildContext context) => Text('$active');
}

class Bar extends StatefulWidget {
  @override
  State<Bar> createState() => _BarState();
}

// Non-State class that happens to have a setState method — must NOT be detected
class NotAState {
  void setState(VoidCallback fn) => fn();
}
