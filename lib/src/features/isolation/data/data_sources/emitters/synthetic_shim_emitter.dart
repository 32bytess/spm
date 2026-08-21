/// Emits stand-ins for references the analyzer could not resolve at all.
///
/// [ShimEmitter] works from elements, so it can only stand in for a symbol the
/// analyzer resolved. That covers a project whose dependencies are installed.
/// It covers nothing in a project whose `pub get` failed, which is routine for
/// an old revision checked out of history: every third-party name has a null
/// element, so it reaches no branch of the dependency visitor, produces no
/// import and no shim, and survives into the output as a dangling reference.
///
/// The same gap shows up in a fully resolved project whenever the extension
/// that defines a member lives in a package the transplant refuses to import.
/// `context.read<T>()` is the case that matters most, since provider and
/// flutter_bloc between them account for a large share of real scopes.
///
/// Everything here is reconstructed from syntax, so it renders `dynamic` and
/// never claims to know a type. The one exception is widget-ness, for the
/// reason [ShimEmitter] gives: a stand-in whose chain does not reach `Widget`
/// moves an allocation from `widgetCount` to `valueObjectAllocCount`, so a
/// constructor call in a widget position is stood in for by a widget.
class SyntheticShimEmitter {
  /// The live set of names the isolated file declares by inlining. Read at
  /// [render] time so a name inlined after the request still wins.
  SyntheticShimEmitter(this._alreadyDeclared);

  final Set<String> _alreadyDeclared;

  /// Extension members to declare, keyed by the type they extend and then by
  /// member name.
  final Map<String, Map<String, _ExtensionMember>> _extensionMembers = {};

  /// Names read as values but declared nowhere.
  final Set<String> _globals = {};

  /// Unresolved constructor calls, keyed by the type name they name.
  final Map<String, _SyntheticClass> _classes = {};

  /// Records `receiver.name(...)` or `receiver.name` where [onType] is the
  /// receiver's static type and [name] resolved to nothing.
  void requestExtensionMember(
    String onType,
    String name, {
    required bool isGetter,
    int typeArgumentCount = 0,
    List<String> positional = const [],
    List<String> named = const [],
  }) {
    if (!_isIdentifier(name) || onType.isEmpty) return;
    final members = _extensionMembers[onType] ??= {};
    final existing = members[name];
    final member = _ExtensionMember(
      name: name,
      isGetter: isGetter,
      typeArgumentCount: typeArgumentCount,
      positionalCount: positional.length,
      named: named.toSet(),
    );
    members[name] = existing == null ? member : existing.merge(member);
  }

  /// Records a bare identifier read as a value but declared nowhere.
  void requestGlobal(String name) {
    if (_isIdentifier(name)) _globals.add(name);
  }

  /// Records a constructor call on an unresolved type.
  ///
  /// [isWidget] comes from the call's position in the tree, not from anything
  /// the analyzer knew.
  void requestClass(
    String name, {
    required bool isWidget,
    int typeArgumentCount = 0,
    int positionalCount = 0,
    List<String> named = const [],
  }) {
    if (!_isIdentifier(name)) return;
    final existing = _classes[name];
    final request = _SyntheticClass(
      name: name,
      isWidget: isWidget,
      typeArgumentCount: typeArgumentCount,
      minPositional: positionalCount,
      maxPositional: positionalCount,
      named: named.toSet(),
    );
    _classes[name] = existing == null ? request : existing.merge(request);
  }

  /// The names this emitter would declare, excluding any already spoken for.
  Set<String> get declaredNames => {
    ..._globals.where((n) => !_alreadyDeclared.contains(n)),
    ..._classes.keys.where((n) => !_alreadyDeclared.contains(n)),
  };

  /// Renders every stand-in, or an empty string when there are none.
  ///
  /// [reserved] holds names another emitter is about to declare, so the two
  /// never collide.
  String render({Set<String> reserved = const {}}) {
    bool taken(String name) =>
        _alreadyDeclared.contains(name) || reserved.contains(name);

    final bodies = <String>[];

    final extendedTypes = _extensionMembers.keys.toList()..sort();
    for (final onType in extendedTypes) {
      final members = _extensionMembers[onType]!;
      final names = members.keys.toList()..sort();
      final rendered = names.map((n) => members[n]!.render()).toList();
      if (rendered.isEmpty) continue;
      bodies.add(
        'extension _Spm${_sanitize(onType)}Shim on $onType {\n'
        '${rendered.join('\n')}\n'
        '}',
      );
    }

    final classNames = _classes.keys.toList()..sort();
    for (final name in classNames) {
      if (taken(name)) continue;
      bodies.add(_classes[name]!.render());
    }

    final globals =
        _globals.where((n) => !taken(n) && !_classes.containsKey(n)).toList()
          ..sort();
    for (final name in globals) {
      bodies.add('late dynamic $name;');
    }

    if (bodies.isEmpty) return '';
    return '''

// Stand-ins for references the analyzer could not resolve, either because the
// symbol lives in a package this file does not import or because the source
// project's own dependencies were not installed. Reconstructed from the call
// sites, so every type here is `dynamic`.
${bodies.join('\n\n')}
''';
  }

  static String _sanitize(String type) {
    final letters = type.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (letters.isEmpty) return 'Type';
    return '${letters[0].toUpperCase()}${letters.substring(1)}';
  }

  static final RegExp _identifier = RegExp(r'^[a-zA-Z_$][a-zA-Z0-9_$]*$');

  /// Words that read as identifiers but cannot be declared as one.
  ///
  /// `void` is the one that matters: a `NamedType` naming it carries no
  /// element, exactly like an unresolved type, so it arrived here and was
  /// declared as `class void {}`, which does not parse.
  static const Set<String> _reserved = {
    'void',
    'dynamic',
    'null',
    'true',
    'false',
    'this',
    'super',
    'Function',
    'Never',
    'covariant',
    'required',
    'late',
    'default',
    'new',
    'const',
    'final',
    'var',
    'return',
    'class',
    'extends',
    'is',
    'as',
    'in',
    'if',
    'else',
    'for',
    'while',
    'switch',
    'case',
    'try',
    'catch',
    'throw',
    'assert',
    'enum',
    'typedef',
    'mixin',
    'extension',
    'with',
    'implements',
  };

  static bool _isIdentifier(String name) =>
      _identifier.hasMatch(name) && !_reserved.contains(name);
}

/// One member of a synthesised extension.
class _ExtensionMember {
  const _ExtensionMember({
    required this.name,
    required this.isGetter,
    required this.typeArgumentCount,
    required this.positionalCount,
    required this.named,
  });

  final String name;
  final bool isGetter;
  final int typeArgumentCount;
  final int positionalCount;
  final Set<String> named;

  /// Widens this member to cover [other] as well.
  ///
  /// A member reached both as a getter and as a call is rendered as the call,
  /// since `read` used as a torn-off value is far rarer than `read()`.
  _ExtensionMember merge(_ExtensionMember other) => _ExtensionMember(
    name: name,
    isGetter: isGetter && other.isGetter,
    typeArgumentCount: typeArgumentCount > other.typeArgumentCount
        ? typeArgumentCount
        : other.typeArgumentCount,
    positionalCount: positionalCount > other.positionalCount
        ? positionalCount
        : other.positionalCount,
    named: {...named, ...other.named},
  );

  String render() {
    if (isGetter) {
      return '  dynamic get $name => throw UnimplementedError();';
    }
    final typeParams = typeArgumentCount == 0
        ? ''
        : '<${List.generate(typeArgumentCount, (i) => 'T$i').join(', ')}>';
    final parameters = <String>[
      for (var i = 0; i < positionalCount; i++) 'dynamic a$i',
      if (named.isNotEmpty)
        '{${(named.toList()..sort()).map((n) => 'dynamic $n').join(', ')}}',
    ];
    return '  dynamic $name$typeParams(${parameters.join(', ')}) =>'
        ' throw UnimplementedError();';
  }
}

/// A class reconstructed from the constructor calls that name it.
class _SyntheticClass {
  const _SyntheticClass({
    required this.name,
    required this.isWidget,
    required this.typeArgumentCount,
    required this.minPositional,
    required this.maxPositional,
    required this.named,
  });

  final String name;
  final bool isWidget;
  final int typeArgumentCount;
  final int minPositional;
  final int maxPositional;
  final Set<String> named;

  _SyntheticClass merge(_SyntheticClass other) => _SyntheticClass(
    name: name,
    isWidget: isWidget || other.isWidget,
    typeArgumentCount: typeArgumentCount > other.typeArgumentCount
        ? typeArgumentCount
        : other.typeArgumentCount,
    minPositional: minPositional < other.minPositional
        ? minPositional
        : other.minPositional,
    maxPositional: maxPositional > other.maxPositional
        ? maxPositional
        : other.maxPositional,
    named: {...named, ...other.named},
  );

  /// A parameter list wide enough for every call site that was seen.
  ///
  /// With no named arguments anywhere the spread between the narrowest and
  /// widest call is expressed exactly, as required positionals followed by
  /// optional ones. Dart has no way to combine optional positional parameters
  /// with named ones, so when both appear the positionals are pinned at the
  /// narrowest call and a wider one is left to fail. That is the one case this
  /// renderer cannot cover.
  String _parameters() {
    if (named.isEmpty) {
      final required = [for (var i = 0; i < minPositional; i++) 'dynamic a$i'];
      final optional = [
        for (var i = minPositional; i < maxPositional; i++) 'dynamic a$i',
      ];
      return [
        ...required,
        if (optional.isNotEmpty) '[${optional.join(', ')}]',
      ].join(', ');
    }

    final sorted = named.toList()..sort();
    final namedParams = sorted.map(
      (n) => (isWidget && n == 'key') ? 'super.key' : 'dynamic $n',
    );
    return [
      for (var i = 0; i < minPositional; i++) 'dynamic a$i',
      '{${namedParams.join(', ')}}',
    ].join(', ');
  }

  String render() {
    final typeParams = typeArgumentCount == 0
        ? ''
        : '<${List.generate(typeArgumentCount, (i) => 'T$i').join(', ')}>';
    final header = isWidget
        ? 'class $name$typeParams extends StatelessWidget'
        : 'class $name$typeParams';
    final body = <String>['  const $name(${_parameters()});'];
    if (isWidget) {
      body.add(
        '  @override\n'
        '  Widget build(BuildContext context) => const SizedBox.shrink();',
      );
    }
    return '$header {\n${body.join('\n')}\n}';
  }
}
