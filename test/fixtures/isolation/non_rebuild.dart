import 'package:flutter/material.dart';

// A whole screen reachable only by pushing it from a handler. `spm analyze`
// never walks the push, so this tree contributes nothing to the scope's
// metrics, and carrying it is how a transplant of a small build() ends up
// several hundred lines long.
class HandlerOnlyDestination extends StatelessWidget {
  const HandlerOnlyDestination({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('destination')));
  }
}

// Produces no UI and is called only from a handler.
class HandlerOnlyService {
  Future<void> submit(String value) async {
    debugPrint('submitted $value');
  }
}

// Carried whole, because build() renders it. Its own handler must be erased
// too: the crawl is gated inside a carried declaration as well, and a gate
// without an erasure leaves `CarriedOnlyFromHandler` with nothing to resolve
// against.
class CarriedCard extends StatelessWidget {
  const CarriedCard({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => CarriedOnlyFromHandler().fire(),
      child: const Text('carried'),
    );
  }
}

// Named only inside CarriedCard's handler.
class CarriedOnlyFromHandler {
  void fire() => debugPrint('fired');
}

class NonRebuildHost extends StatefulWidget {
  const NonRebuildHost({super.key});

  @override
  State<NonRebuildHost> createState() => _NonRebuildHostState();
}

class _NonRebuildHostState extends State<NonRebuildHost> {
  // Read by build() and assigned by initState(), which is why initState is
  // kept even though a rebuild does not run it. Dropping it makes the file
  // analyse clean and then throw a LateInitializationError on the first read.
  late final String _title;

  bool _enabled = true;

  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _title = 'seeded';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Void-returning and it really does run, moments after the scope mounts.
      // A throw here would trade an analyzer error for an uncaught exception
      // around the first frame.
      debugPrint('after first frame');
    });
  }

  // Reached only as `onPressed: _handleSubmit`. The reference is evaluated
  // while the tree is built, so the name has to resolve; the body runs only on
  // the press, so nothing in it needs to survive.
  void _handleSubmit() {
    HandlerOnlyService().submit(_controller.text);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const HandlerOnlyDestination()),
    );
  }

  // Reached from build(), so it is kept whole: `tree_extractor` walks the body
  // of every widget-returning helper a scope calls.
  Widget _buildRow() => Row(children: [Text(_title)]);

  // Reached from nowhere a rebuild can run.
  Future<void> _refresh() async {
    await HandlerOnlyService().submit('refresh');
  }

  void _toggleA() => setState(() => _enabled = true);
  void _toggleB() => setState(() => _enabled = false);

  @override
  Widget build(BuildContext context) {
    // Material, because the transplanted file carries no Scaffold and both
    // TextFormField and ElevatedButton need a Material ancestor.
    // A void deferred callback on the rebuild path, so the eraser's empty-block
    // branch is still exercised now that initState is dropped. Registering a
    // listener in build is not good practice; it is here because the slot is
    // what the predicate keys on, not the place.
    _controller.addListener(() {
      debugPrint('after change');
    });
    return Material(
      child: Column(
        children: [
          _buildRow(),
          const CarriedCard(),
          TextFormField(
            controller: _controller,
            // Returns String?, so an empty body would return null and change what
            // the form does. It also must not dangle.
            validator: (value) {
              if (value == null || value.isEmpty) return 'required';
              return null;
            },
          ),
          // Not a FunctionExpression, so it is evaluated while the tree is built
          // and `analyze` keeps counting it. It must survive untouched.
          GestureDetector(
            onTap: _enabled ? _toggleA : _toggleB,
            child: const Text('toggle'),
          ),
          ElevatedButton(onPressed: _handleSubmit, child: const Text('submit')),
          ElevatedButton(
            onPressed: () {
              // A local function only this handler calls.
              void deepInHandler() => debugPrint('$_title');
              deepInHandler();
              HandlerOnlyService().submit('inline');
            },
            child: const Text('inline'),
          ),
        ],
      ),
    );
  }
}
