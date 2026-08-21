import 'package:analyzer/dart/ast/ast.dart';

/// One import the isolated file has to carry.
///
/// Identity is the pair of [uri] and [prefix], not the URI alone: the same
/// library reached under two different prefixes needs two directives, and Dart
/// accepts that. Rendering a set of pre-formatted strings, which is what this
/// replaced, could not express the pair, so any path that did not have the
/// original directive in hand emitted a prefixless import and every prefixed
/// reference in the transplanted body died.
class ImportRequest {
  /// The library URI exactly as it will be written.
  final String uri;

  /// The `as` prefix the transplanted code writes, when there is one.
  final String? prefix;

  /// A rendered `show`/`hide` clause, or null for an unrestricted import.
  final String? combinators;

  const ImportRequest({required this.uri, this.prefix, this.combinators});

  /// The pair that decides whether two requests are the same import.
  String get key => '$uri as ${prefix ?? ''}';

  /// Renders the directive in the order Dart's grammar requires: the URI, then
  /// the prefix, then the combinators.
  String render() {
    final buffer = StringBuffer("import '$uri'");
    if (prefix != null) buffer.write(' as $prefix');
    if (combinators != null) buffer.write(' $combinators');
    buffer.write(';');
    return buffer.toString();
  }
}

/// Gathers the imports of one transplant and renders them as a file header.
///
/// Requests arrive from three places that never see each other: the dependency
/// visitor's directive match, its URI-only fallback, and the textual prefix
/// rescan the transplant runs over every unit it copied code from. All three
/// feed this, so a prefix learned by any one of them survives.
class ImportCollector {
  /// Keyed by [ImportRequest.key], insertion order irrelevant since [render]
  /// sorts.
  final Map<String, ImportRequest> _requests = {};

  /// Keys whose combinators have to be dropped, either because two requests
  /// disagreed about them or because one request wanted the whole library.
  ///
  /// Widening an import can only make more names resolve. Narrowing it cannot,
  /// and the transplant routinely pulls in a symbol through a re-export that
  /// the original `show` list never named, so disagreement resolves towards the
  /// unrestricted import.
  final Set<String> _unrestricted = {};

  /// Records an import of [uri], optionally prefixed and restricted.
  void add(String uri, {String? prefix, String? combinators}) {
    if (uri.isEmpty) return;
    final request = ImportRequest(
      uri: uri,
      prefix: prefix,
      combinators: combinators,
    );
    final existing = _requests[request.key];
    if (existing == null) {
      _requests[request.key] = request;
      if (combinators == null) _unrestricted.add(request.key);
      return;
    }
    if (existing.combinators != combinators) _unrestricted.add(request.key);
  }

  /// Records the import [directive] declares, preserving its prefix and
  /// combinators.
  ///
  /// `deferred` is deliberately dropped. A deferred import demands a
  /// `loadLibrary()` call before any name behind it may be read, and the
  /// generated `build` never makes one, so copying the keyword across turns a
  /// working import into a fresh error.
  void addDirective(ImportDirective directive, {String? uriOverride}) {
    final uri = uriOverride ?? directive.uri.stringValue;
    if (uri == null || uri.isEmpty) return;
    final combinators = directive.combinators.isEmpty
        ? null
        : directive.combinators.map((c) => c.toSource()).join(' ');
    add(uri, prefix: directive.prefix?.name, combinators: combinators);
  }

  /// Every directive, one per line, sorted so two runs over the same input
  /// produce the same bytes. `dart:` libraries come first, as the SDK's own
  /// style orders them.
  String render() {
    final lines =
        _requests.values
            .map(
              (r) => _unrestricted.contains(r.key)
                  ? ImportRequest(uri: r.uri, prefix: r.prefix)
                  : r,
            )
            .map((r) => r.render())
            .toList()
          ..sort(_compare);
    return lines.join('\n');
  }

  static int _compare(String a, String b) {
    final aSdk = a.startsWith("import 'dart:");
    final bSdk = b.startsWith("import 'dart:");
    if (aSdk != bSdk) return aSdk ? -1 : 1;
    return a.compareTo(b);
  }
}
