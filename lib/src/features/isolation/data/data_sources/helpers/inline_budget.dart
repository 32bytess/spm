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
class InlineBudget {
  InlineBudget({this.maxDeclarations = 200, this.maxCharacters = 200000});

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

  /// How many third-party declarations were inlined.
  int get inlinedDeclarations => _declarations;

  /// Whether the budget ran out, so some third-party UI was shimmed that would
  /// otherwise have been inlined.
  bool get exhausted => _exhausted;

  /// Records an inlined declaration of [length] characters.
  ///
  /// Returns false once the budget is spent, and stays false from then on: a
  /// small declaration arriving after a large one blew the cap must not slip
  /// through, or the output depends on traversal order.
  bool take(int length) {
    if (_exhausted) return false;
    if (_declarations + 1 > maxDeclarations ||
        _characters + length > maxCharacters) {
      _exhausted = true;
      return false;
    }
    _declarations++;
    _characters += length;
    return true;
  }
}
