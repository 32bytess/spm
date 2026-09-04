/// Caps how much third-party source one transplant may inline.
///
/// Repo-local inlining needs no cap: its closure is bounded by the repository,
/// and a scope that reaches every widget in the app was already reaching them
/// before this existed. Third-party inlining has no such bound. A scope holding
/// a state-management builder reaches a widget whose supertype chain is UI, so
/// it is inlined, and from there the crawl walks into the package's own
/// machinery. Charting and state-management packages are the shapes that show
/// it.
///
/// Past the cap the transplant falls back to the stand-in it would have emitted
/// before, which is a smaller tree rather than a broken file. The run records
/// that it happened, since a truncated row and a complete one are not the same
/// measurement and nothing downstream could otherwise tell them apart.
///
/// The caps are far higher than they were, and the reason is that the in-place
/// walk no longer has one: `spm analyze` now reads a third-party library, so
/// every scope that exhausts this budget undercounts against the row it is
/// meant to be compared with. The counter stays, but as a number to report
/// rather than a limit to hit. Where the raised cap still binds, the row is
/// marked, so a reader can exclude it rather than be silently short.
class InlineBudget {
  InlineBudget({
    this.maxDeclarations = defaultMaxDeclarations,
    this.maxCharacters = defaultMaxCharacters,
  });

  /// The default declaration cap.
  static const int defaultMaxDeclarations = 2000;

  /// The default character cap.
  static const int defaultMaxCharacters = 2000000;

  /// The most third-party declarations one transplant may inline.
  final int maxDeclarations;

  /// The most third-party source, in characters, one transplant may inline.
  ///
  /// Counted alongside the declaration cap rather than instead of it: a package
  /// that hands out two thousand-line widgets and one that hands out two
  /// hundred small ones are both worth stopping, and neither limit catches
  /// both.
  final int maxCharacters;

  int _declarations = 0;
  int _characters = 0;
  bool _exhausted = false;
  final Map<String, String> _packages = <String, String>{};

  /// How many third-party declarations were inlined.
  int get inlinedDeclarations => _declarations;

  /// The hosted packages this budget was actually spent on, name to version.
  ///
  /// Populated by [take] rather than by its callers, so it cannot drift from
  /// [inlinedDeclarations]: a declaration is counted and its package recorded
  /// in the same statement, and the two are non-empty together or not at all.
  /// That equivalence is what lets a reader treat an absent map as "this scope
  /// carried no package source" instead of "nobody wrote the recording down".
  ///
  /// Empty for a path or git dependency, whose directory carries no version to
  /// read. Such a dependency still costs budget and still shows in the count,
  /// so a count without a matching entry is the signal that one is in play --
  /// which is why [take] returns the package it recorded, or null.
  Map<String, String> get inlinedPackages => Map.unmodifiable(_packages);

  /// Whether the budget ran out, so some third-party UI was shimmed that would
  /// otherwise have been inlined.
  bool get exhausted => _exhausted;

  /// Records an inlined declaration of [length] characters, read from
  /// [fromPath].
  ///
  /// Returns false once the budget is spent, and stays false from then on: a
  /// small declaration arriving after a large one blew the cap must not slip
  /// through, or the output depends on traversal order.
  ///
  /// [fromPath] is the absolute path the declaration's source was read from,
  /// which for a hosted dependency is inside the pub cache. It is required
  /// rather than optional because the caller that forgets it is exactly the
  /// caller whose inlined package would go unrecorded, and an under-reported
  /// map is worse than no map: downstream reads it as a complete answer.
  bool take(int length, String fromPath) {
    if (_exhausted) return false;
    if (_declarations + 1 > maxDeclarations ||
        _characters + length > maxCharacters) {
      _exhausted = true;
      return false;
    }
    _declarations++;
    _characters += length;
    final package = hostedPackageOf(fromPath);
    if (package != null) _packages[package.name] = package.version;
    return true;
  }
}

/// The `name-version` segment of a pub-cache path, split apart.
///
/// A hosted package resolves to `<cache>/hosted/<host>/<name>-<version>/lib`,
/// and that segment is the only place the version appears in anything the
/// isolation pass already holds. Same shape, and deliberately the same regular
/// expression, as `TreeExtractor._packageVersions` on the analyze side: the two
/// commands must agree about what a package is called before anything can be
/// checked across them.
///
/// Null for a path that carries no such segment, which is what a path
/// dependency, a git dependency and a project-local file all look like.
({String name, String version})? hostedPackageOf(String path) {
  final segment = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)-([0-9][^/\\]*)$');
  for (final part in path.split(RegExp(r'[/\\]'))) {
    final match = segment.firstMatch(part);
    if (match != null) {
      return (name: match.group(1)!, version: match.group(2)!);
    }
  }
  return null;
}
