/// Which files a rebuild scope's metrics were actually computed from, and which
/// of them could not be read.
///
/// A scope's 14 metrics are NOT a function of the file that declares it. The
/// extractor follows helper methods and getters across libraries and runs a BFS
/// over custom child widgets, merging each child's `build()` into the totals. So
/// editing a widget two files away moves the numbers while the scope's own file
/// is untouched.
///
/// That matters twice over:
///
///  * **Mining.** Selecting commits by "touched the scope's file" silently drops
///    real edits, and drops them non-randomly, hardest in well-composed code,
///    where child trees are deepest.
///  * **Correctness.** A closure file that will not resolve makes the row wrong
///    rather than absent: an unreadable child contributes nothing and its whole
///    subtree vanishes from the totals, while a child that resolves *with*
///    errors has its types come back null and its widgets classify as value
///    objects. Neither shows up in the scanned/skipped counts, because those
///    guard only the file being scanned.
///
/// [unresolvedDependencies] is what makes the second case visible. A row whose
/// list is non-empty is incomplete by an unknown amount, and comparing it
/// against another revision measures resolution state rather than a human edit.
typedef ClosureSet = ({
  /// Files whose contents contributed to the metrics, the declaring file
  /// included. Absolute paths as the extractor saw them.
  List<String> dependencyFiles,

  /// Closure libraries that could not be read: unresolvable, or resolved while
  /// carrying an error-severity diagnostic. Paths where one is known, library
  /// URIs otherwise.
  List<String> unresolvedDependencies,
});

/// What [TreeExtractor.extract] returns: the feature vector, plus the evidence
/// needed to decide whether that vector can be trusted.
typedef ExtractionSet<T> = ({T features, ClosureSet closure});
