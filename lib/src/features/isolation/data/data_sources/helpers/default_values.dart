import 'package:analyzer/dart/ast/ast.dart';

/// A value an isolated file can evaluate for a binding of a given type.
///
/// [expression] is Dart source. [nullableType] asks the caller to widen the
/// binding's declared type with a `?` before using the expression, which is how
/// a type nothing here can build still gets a value instead of staying
/// unassigned.
class DefaultValue {
  const DefaultValue(this.expression, {this.nullableType = false});

  /// The source of the value.
  final String expression;

  /// Whether the binding has to be declared nullable to hold it.
  final bool nullableType;
}

/// Builds a runnable value for each type an isolated file declares.
///
/// The emitters used to leave a binding unassigned and a member body throwing,
/// on the argument that an invented value could be mistaken for a real one.
/// That argument holds for types and not for values: the extracted features
/// come from the shape of the build tree, and that shape is fixed before any of
/// this executes. An unassigned `late` binding read from `initState` throws
/// before the first frame, which costs the whole transplant, and a transplant
/// that does not run cannot be measured at all.
///
/// One instance serves one file, because [usesStub] records whether anything
/// reached the `_Stub` fallback and the file only declares `_Stub` when
/// something did.
class DefaultValues {
  DefaultValues({
    Map<String, String> enumConstants = const {},
    Set<String> constructible = const {},
    Set<String>? nameable,
  }) : _enumConstants = {...enumConstants},
       _constructible = {...constructible},
       _nameable = nameable;

  /// The names the file will declare, shared live with the emitters.
  ///
  /// Null means the question cannot be asked, and every type argument is then
  /// written out as it was before this was threaded through.
  final Set<String>? _nameable;

  /// The first constant of each enum the file declares, keyed by enum name.
  final Map<String, String> _enumConstants;

  /// Names the file declares that can be built by writing `Name()`.
  final Set<String> _constructible;

  /// Records that the file declares `enum [name]` whose first constant is
  /// [firstConstant].
  void registerEnum(String name, String firstConstant) {
    _enumConstants[name] = firstConstant;
  }

  /// Records that writing `[name]()` builds something the file declares.
  void registerConstructible(String name) {
    _constructible.add(name);
  }

  bool _usesStub = false;

  /// Whether any value handed out so far was a `_Stub`.
  bool get usesStub => _usesStub;

  /// Types that are widgets by name, so a member handing one out gets a widget.
  ///
  /// Only the names an isolated file can already write. Anything else that
  /// reaches [forType] as a widget arrives through [isWidget], which the caller
  /// answers from the element model.
  static const Set<String> _widgetNames = {
    'Widget',
    'PreferredSizeWidget',
    'StatelessWidget',
    'StatefulWidget',
  };

  /// A value for a binding whose type renders as [renderedType].
  ///
  /// [isWidget] lets a caller holding the resolved type say so when the
  /// rendered name is a subclass this method would not recognise.
  /// Returns null when nothing here can build the type, which leaves the
  /// decision with the caller rather than inventing a cast that throws.
  DefaultValue? forType(String renderedType, {bool isWidget = false}) {
    final type = renderedType.trim();
    if (type.isEmpty || type == 'void') return null;

    if (type == 'dynamic' || type == 'Object' || type == 'Object?') {
      _usesStub = true;
      return const DefaultValue('const _Stub()');
    }
    // A nullable type takes null before anything else is considered. It is the
    // only value guaranteed to be in range, and no member chain reads through a
    // binding the transplanted code already had to null-check.
    if (type.endsWith('?')) return const DefaultValue('null');

    if (isWidget || _widgetNames.contains(type)) {
      return const DefaultValue('const SizedBox.shrink()');
    }

    switch (type) {
      case 'String':
        return const DefaultValue("''");
      case 'bool':
        return const DefaultValue('false');
      case 'int':
        return const DefaultValue('0');
      case 'double':
        return const DefaultValue('0.0');
      case 'num':
        return const DefaultValue('0');
      case 'Duration':
        return const DefaultValue('Duration.zero');
      case 'DateTime':
        return const DefaultValue('DateTime.fromMillisecondsSinceEpoch(0)');
    }

    final generic = _splitGeneric(type);
    if (generic != null) {
      final (name, arguments) = generic;
      switch (name) {
        case 'List':
        case 'Iterable':
          if (arguments.length == 1) {
            return DefaultValue(
              _canName(arguments[0]) ? '<${arguments[0]}>[]' : '[]',
            );
          }
        case 'Set':
          if (arguments.length == 1) {
            return DefaultValue(
              _canName(arguments[0]) ? '<${arguments[0]}>{}' : '{}',
            );
          }
        case 'Map':
          if (arguments.length == 2) {
            return DefaultValue(
              arguments.every(_canName)
                  ? '<${arguments[0]}, ${arguments[1]}>{}'
                  : '{}',
            );
          }
        case 'Future':
          if (arguments.length == 1) {
            final inner = forType(arguments[0]);
            if (inner != null && !inner.nullableType) {
              return DefaultValue(
                'Future<${arguments[0]}>.value(${inner.expression})',
              );
            }
          }
      }
      // A generic the file cannot build is still nameable, so the raw name is
      // what the enum and constructible lookups below should see.
      final constant = _enumConstants[name];
      if (constant != null) return DefaultValue('$name.$constant');
      return null;
    }

    final constant = _enumConstants[type];
    if (constant != null) return DefaultValue('$type.$constant');
    if (_constructible.contains(type)) return DefaultValue('$type()');

    return null;
  }

  /// A value for [renderedType], falling back to a nullable binding.
  ///
  /// Callers that control the binding's declared type use this; callers that do
  /// not, such as an assignment into a field declared elsewhere, use [forType]
  /// and handle the null themselves.
  DefaultValue forTypeOrNull(String renderedType, {bool isWidget = false}) =>
      forType(renderedType, isWidget: isWidget) ??
      const DefaultValue('null', nullableType: true);

  /// Whether the file can write [type] down.
  ///
  /// A generated value used to name its type argument unconditionally, and the
  /// argument came from the element model rather than from anything the file
  /// declares. `<WebDavFile>[]` against a `WebDavFile` nothing carried is an
  /// error-severity diagnostic, and `spm analyze` skips the whole file over it.
  ///
  /// The untyped literal is the safe answer rather than a lesser one: every
  /// place these values are used supplies a context type, so `[]` infers what
  /// `<T>[]` stated.
  bool _canName(String type) {
    final nameable = _nameable;
    if (nameable == null) return true;
    final bare = type.endsWith('?') ? type.substring(0, type.length - 1) : type;
    return _alwaysNameable.contains(bare) || nameable.contains(bare);
  }

  /// Core types every isolated file can name, since all of them import
  /// `package:flutter/material.dart` and it re-exports `dart:core`.
  static const Set<String> _alwaysNameable = {
    'String',
    'bool',
    'int',
    'double',
    'num',
    'Object',
    'dynamic',
    'DateTime',
    'Duration',
    'Widget',
  };

  /// Splits `Map<String, int>` into `('Map', ['String', 'int'])`.
  ///
  /// Nesting is tracked so `Map<String, List<int>>` yields two arguments rather
  /// than three. Returns null when [type] carries no type arguments.
  static (String, List<String>)? _splitGeneric(String type) {
    final open = type.indexOf('<');
    if (open <= 0 || !type.endsWith('>')) return null;
    final name = type.substring(0, open);
    final body = type.substring(open + 1, type.length - 1);

    final arguments = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    for (final rune in body.runes) {
      final char = String.fromCharCode(rune);
      if (char == '<' || char == '(') depth++;
      if (char == '>' || char == ')') depth--;
      if (char == ',' && depth == 0) {
        arguments.add(buffer.toString().trim());
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }
    final last = buffer.toString().trim();
    if (last.isNotEmpty) arguments.add(last);
    return (name, arguments);
  }
}

/// Records what [declaration] can supply, once the file inlines it whole.
///
/// The stand-in emitter answers this for the declarations it writes, and an
/// inlined declaration has nobody else to answer for it: without this a seed
/// typed by a class the file carries in full falls back to an unassigned
/// `late`, which throws on the first read even though `Name()` was right there.
void registerInlinedDeclaration(
  CompilationUnitMember declaration,
  DefaultValues defaults,
) {
  if (declaration is EnumDeclaration) {
    final constants = declaration.body.constants
        .map((constant) => constant.name.lexeme)
        .where((name) => name.isNotEmpty);
    if (constants.isNotEmpty) {
      defaults.registerEnum(
        declaration.namePart.typeName.lexeme,
        constants.first,
      );
    }
    return;
  }
  if (declaration is! ClassDeclaration) return;
  if (declaration.abstractKeyword != null) return;
  final body = declaration.body;
  if (body is! BlockClassBody) return;

  final constructors = body.members.whereType<ConstructorDeclaration>();
  if (constructors.isEmpty) {
    defaults.registerConstructible(declaration.namePart.typeName.lexeme);
    return;
  }
  for (final constructor in constructors) {
    if (constructor.name != null) continue;
    final required = constructor.parameters.parameters.any((p) => p.isRequired);
    if (!required) {
      defaults.registerConstructible(declaration.namePart.typeName.lexeme);
    }
    return;
  }
}
