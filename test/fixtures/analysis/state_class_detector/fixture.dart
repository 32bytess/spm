import 'package:flutter/material.dart';

// Direct State subclass. Must be detected
class _DirectState extends State<DirectWidget> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class DirectWidget extends StatefulWidget {
  @override
  State<DirectWidget> createState() => _DirectState();
}

// Indirect subclass via an abstract base. Both base and leaf must be detected
abstract class BaseState<T extends StatefulWidget> extends State<T> {}

class _IndirectState extends BaseState<IndirectWidget> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class IndirectWidget extends StatefulWidget {
  @override
  State<IndirectWidget> createState() => _IndirectState();
}

// Plain class. Must NOT be detected
class PlainClass {}
