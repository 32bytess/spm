/// The name of the per-file stand-in value.
const String stubClassName = '_Stub';

/// A value that answers any call, for bindings whose type is `dynamic`.
///
/// `null` is the obvious default for a `dynamic` binding and it does not
/// survive contact with real code. The transplanted bodies read member chains
/// off these bindings, `context.read<ChatProvider>().messages.length` and
/// `widget.arguments.peerId` among them, and every one of those throws
/// `NoSuchMethodError` at the first hop against a null. That moves the crash
/// from `initState` into `build` rather than removing it.
///
/// The members declared here are the ones a build body actually reaches, so a
/// chain, a spread and a `for` over a stubbed collection all terminate.
/// Everything else falls to [noSuchMethod] and comes back as another stub,
/// which keeps a chain alive to its end.
///
/// Two limits, stated rather than discovered. A stub cannot occupy a typed
/// slot, so `Widget`, `int`, `String` and the rest take concrete defaults from
/// `default_values.dart` instead. And a stub iterates over nothing, so a scope
/// whose list comes from a lifted binding builds zero rows: the file mounts and
/// the tree is shallow.
const String stubClassSource =
    '''
class $stubClassName {
  const $stubClassName();

  int get length => 0;
  bool get isEmpty => true;
  bool get isNotEmpty => false;
  Iterator<dynamic> get iterator => const Iterable<dynamic>.empty().iterator;

  dynamic operator [](Object? key) => const $stubClassName();
  dynamic operator +(Object? other) => const $stubClassName();
  bool operator <(Object? other) => false;
  bool operator >(Object? other) => false;
  bool operator <=(Object? other) => false;
  bool operator >=(Object? other) => false;

  @override
  bool operator ==(Object other) => other is $stubClassName;

  @override
  int get hashCode => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => const $stubClassName();

  @override
  String toString() => '';
}
''';

/// The stub declaration wrapped in the banner the other emitters use.
String renderStubClass() => '''

// Stands in for values this file cannot reproduce. Reaching a member on one
// returns another stub rather than throwing, so a build body runs to its end.
$stubClassSource''';
