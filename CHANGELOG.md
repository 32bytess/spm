# Changelog

## 0.6.0

Everything since 0.5.2. Two changes carry the release, and both are about `isolate` writing a file
that describes the code it came from. A transplanted StatefulWidget now brings its `State`'s
dependencies with it, and a third-party widget now arrives with its own tree instead of an empty
stand-in. Alongside them, several things that reported success without having earned it now say so
instead.

Output from 0.6.0 cannot be pooled with 0.5.2's: the same scope produces a different file and, where
a package widget is involved, different metrics.

### Added

- `--inline-third-party`, on by default. `--no-inline-third-party` stands every third-party symbol
  in, which is what `isolate` did up to 0.5.2.
- Three mapping JSONL fields, all omitted unless they apply: `inlinedThirdPartyDeclarations` counts
  the third-party declarations carried into a file; `thirdPartyInlineTruncated` marks a scope that
  reached the per-scope budget; `thirdPartyInlineReverted` marks a scope where carrying the code
  analysed worse than standing it in, so the stood-in version was kept. The last two both say the
  file describes a smaller tree than the code it came from builds.
- `helpers/ui_surface.dart` holds the predicate that decides whether a declaration can produce UI,
  in both an AST form and an element-model form, so the transplant's inline gate and the dependency
  visitor's gate cannot drift apart. `helpers/inline_budget.dart` and
  `helpers/flutter_namespace.dart` hold the two limits described below.

### Changed

- The dependency gate now asks "is this the SDK" rather than "is this project-local". The SDK is
  imported, anything that can produce UI is carried as source whether it is repo-local or
  third-party, and everything else becomes a declaration-only stand-in. A third-party
  `StatefulWidget` arrives with its companion `State`, which is the half that matters, since that is
  where the build body lives. A stood-in widget has an empty `build`, so a file full of them
  describes a tree the app never built and cannot be read or run as the scope it came from.
- Carrying third-party source is bounded, unlike the repo-local kind, at 200 declarations or 200,000
  characters per scope. A repo-local closure is bounded by the repository already; a third-party one
  is not, and a scope holding a single state-management builder reaches a widget from which the
  crawl walks into the package's own machinery.
- Carrying is undone per scope when it does not pay. After the output is verified, any scope that
  carried third-party source and still does not analyse is extracted a second time with that source
  stood in for, and whichever version has fewer errors is kept. A package widget generic over a type
  bounded by one of the package's own classes is the shape that needs this: carrying the widget
  brings its real bound along, and the repo-local class that satisfies that bound in the application
  is a stand-in here with no supertype at all, so a file that type-checked against a stand-in's
  `dynamic` stops type-checking. Rather than keep a list of packages that behave this way, both
  answers are analysed and the better one wins, which makes the guarantee exact: no scope ends up
  with more errors than `--no-inline-third-party` would have given it.
- A third-party declaration whose name `package:flutter/material.dart` also exports is stood in for
  rather than carried. A local declaration shadows the import either way, but an empty stand-in
  named `Card` only costs the subtree under each `Card(...)`, where a carried one puts a body under
  every use of the name, including the uses that meant Flutter's.
- The same-file rule, "within a file take everything", was written about project files and now
  applies to package units as well, so it takes the budget and the material-name check with it.
  Without that, a package's own declarations entered through a door the third-party gate does not
  watch.
- `SvgPicture` and `CachedNetworkImage` are no longer in the set of image constructions rewritten to
  `Image.asset('assets/placeholder.png')`. They are widgets from packages, and substituting one
  widget for another was hiding whatever those packages build. The rewrite now requires an SDK-owned
  element, so Flutter's own `Image`, `AssetImage`, `NetworkImage`, `FileImage`, `MemoryImage`,
  `DecorationImage`, `FadeInImage` and `RawImage` still take the placeholder, because an isolated
  file has no assets directory and no network.
- Resolving a dependency's unit is guarded. A third-party reference points at a file outside the
  project rather than inside it, and an unreadable one now costs a stand-in instead of the whole
  scope.
- Unused imports are no longer pruned from the output. The pruner was line based, and `dart format`
  wraps a long `show` clause across lines, so pruning one could leave the rest of the clause behind
  and turn a warning into a parse error. Removing it also removes the re-analysis round trip that
  was the most likely way to reach the verifier's swallowed-diagnostics bug listed under Fixed. An
  unused import is a warning, never an error, so it does not stop `analyze` from reading the file;
  prune it downstream over an AST if the output needs to be clean of them.
- The mapping JSONL ends every line, `analyze`'s output always did.
- Passing the same directory twice no longer isolates every scope in it twice. The per-input
  directory filter it replaces could not admit a context twice for distinct inputs anyway: the
  analyzer roots each context at an included path and merges overlapping ones.
- The walk up to the nearest `.dart_tool/package_config.json` is now one helper,
  `helpers/package_config.dart`, shared by the extractor and the verifier instead of living only in
  the verifier.
- The isolation tests share one transplant run per file rather than repeating it for every test.

### Fixed

- The companion `State` of an inlined StatefulWidget was copied and never visited, so nothing it
  referenced reached the dependency crawl: no stand-in, no import, no cross-file reference. A
  `State` body is where a StatefulWidget keeps everything it depends on, which is what made this
  expensive: a widget whose data types are named only inside its `State` had the code that names
  them carried across and a declaration for none of them. The companion is visited under its own
  class rather than the widget's, so a reference to one of its own methods reads as a member of the
  class that declares it.
- A widget stand-in carried `createState` and `debugFillProperties`, both of which only the
  framework calls and neither of which a stand-in can honour. `createState` returns `State<T>`,
  whose bound is `StatefulWidget`, against a stand-in deliberately collapsed to `StatelessWidget`,
  so standing in for a stateful widget produced a bound violation on the stand-in's own signature.
  `debugFillProperties` names `DiagnosticPropertiesBuilder`, which `package:flutter/material.dart`
  does not export, since `widgets.dart` re-exports foundation as `show Brightness, UniqueKey`.
- Deciding whether an import already provides a name walked the export graph, which ignores `show`
  and `hide`. The analyzer says as much in its own doc comment on `exportedLibraries`, and Flutter
  is built out of those clauses: `widgets.dart` re-exports foundation as
  `show Brightness, UniqueKey`, so every foundation symbol reached from a file importing only
  `material.dart` matched material, and the fallback that would have written the real import never
  ran. The question is now asked of the export namespace, which is the one that honours the clauses.
  `DiagnosticPropertiesBuilder`, `Diagnosticable`, `kDebugMode` and `compute` are all this shape.
- A builder given a tear-off rather than an inline closure was a scope to `isolate` and not to
  `analyze`. There is no callback body at the creation site, so the transplant fell through to its
  expression fallback and returned the function itself where a `Widget` belongs: a file that can
  never analyse clean, a row in the mapping, and a count in the summary, for a scope `analyze` never
  reports. `findBuilderArgument` now returns only a `FunctionExpression`, so both commands take the
  rule from one place.
- The verifier reported a file it could not analyse as a file with no errors. Every failure to
  fetch diagnostics was swallowed and became an empty diagnostic list, which is indistinguishable
  from a clean run. It now reports `verified: false`, which is what the unverified and clean split
  existed to express.
- `sourceDependenciesResolved` could only ever be false once per checkout. An existing
  `package_config.json` was taken as proof that resolution had happened, and the minimal config
  `isolate` writes when `pub get` fails satisfies that check, so the flag fired on the run that
  created the file and never again. Walking a repository's history, where a worktree keeps its
  `.dart_tool` across checkouts, that is every revision after the first. A config `isolate` wrote
  itself now counts as unresolved, and a directory with no pubspec and no config above it does too.
  **Counts of this flag taken from output written by 0.5.2 or earlier are floors.**
- `isolate` accepted a directory that does not exist and reported success over zero scopes. A
  missing path resolves to a context rooted at the nearest real package above it, whose files are
  then all filtered out, so a typo read exactly like a project with no rebuild scopes in it. An
  input that produces no analysis context at all is now an error too.
- The set of projects whose dependencies failed to resolve was never cleared between calls. The
  data source is a lazy singleton, so a second `isolate()` in the same process still carried the
  first one's verdict and marked `sourceDependenciesResolved: false` on rows from a project that
  resolved perfectly well. Only the CLI, which runs one isolation per process, was unaffected.

### Notes

- Carrying a package widget does **not** make an isolated row match the in-place row, which is the
  obvious guess and the wrong one. `BuildMetricsVisitor` does record a non-SDK widget as a custom
  child, but `TreeExtractor` then asks `AnalysisContextCollection.contextFor` for its file, and that
  throws for any path outside the analyzed roots, which is where a package's source sits. The child
  is dropped and its subtree with it, so `analyze` never counted a package widget's tree in place
  either. A row that carried one therefore counts **more** than the same scope does in place, not
  less. Isolated and in-place numbers are not comparable across that boundary in either direction.

## 0.5.2

`isolate` now analyses what it wrote before it reports success, so every run says how many of its
files a later `spm analyze` can actually read. The fixes below all change what `isolate` writes.
Files produced by 0.5.1 and earlier carry imports of packages that were never meant to be there and
references to names nothing declares, so they cannot be pooled with 0.5.2 output.

### Fixed

- The gate that decides which libraries an isolated file may import tested `package:flutter` without
  the trailing slash, so every pub package whose name begins with `flutter` passed as an SDK
  library. `flutter_bloc`, `flutter_riverpod`, `flutter_secure_storage`, `flutter_localizations`,
  `flutter_scale_kit` and `fluttertoast` were among them: each was imported back into the isolated
  file instead of being stood in for, leaving output that only resolves inside the project it came
  from. Sizing extensions such as `.sp` and `.w` were the visible half of this, since the import
  that was supposed to define them does not exist where the file is read.
- Import prefixes were dropped. A scope whose source read `import 'dart:math' as math;` was written
  out with a plain `import 'dart:math';`, so every `math.pi` and `math.Random()` in the transplanted
  body became an undefined name. Prefixes, `show` clauses and `hide` clauses now travel with the
  import, including prefixes from the other files a transplant copied code from. A `deferred` import
  is deliberately not copied: the generated `build` never calls `loadLibrary()`.
- The branch that matched a reference back to the import directive it came through read the
  directive's element under two names the current analyzer does not expose, so it threw and was
  skipped for every import. Every import fell to a fallback that rebuilds the directive from the
  library's URI alone, which is where the prefixes and combinators were being lost.
- A declaration written in a `part` file was reported against the file that defines the library, so
  the same-file lookup searched a unit that does not declare it, found nothing, and marked the name
  handled on the way out. Private widgets declared in a part were left undefined, which does not
  merely fail to compile: `analyze` skips the subtree of a child widget it cannot reach, so the row
  is wrong rather than absent.
- A same-file lookup that found nothing, and a cross-file reference whose file did not resolve, both
  used to leave the name dangling. Each now falls back to a declaration-only stand-in.
- A stand-in carried only the members the crawl happened to reach, so a controller could arrive with
  `removeListener` and without `addListener`. Members are now recorded against the type the code
  names rather than the type that declares them, which is what was losing every member inherited
  from a Flutter base class such as `ChangeNotifier`, and a type that declares 40 members or fewer
  comes across whole.

### Added

- References the analyzer resolves to nothing now get stand-ins rebuilt from the call sites. Two
  situations produce them: an extension defined in a package the isolated file may not import, which
  is what `context.read<T>()`, `context.watch<T>()` and `context.select<T, R>()` are, and a source
  project whose own `pub get` never succeeded, where no third-party name resolves at all. An
  unresolved constructor call in a widget position is stood in for by a widget, so the allocation is
  still counted as one.
- `isolate` analyses the files it wrote, in the same process, before reporting. Imports nothing uses
  are removed, and each mapping row gains `verified`, `errorCount`, `warningCount`, `topCodes`,
  `unresolvedImports` and `unresolvedNames`. The run prints how many files analyse clean, which is
  the number that decides how much of the output `analyze` can read.
- A row carries `sourceDependenciesResolved: false` when the project it came from had no resolvable
  dependencies, so a consumer can exclude or re-run those rows instead of treating their metrics
  as comparable. The condition is logged as an error when it happens rather than passing silently.
- The output directory gets a `pubspec.yaml` and a `.dart_tool/package_config.json` borrowed from
  the source project, so the isolated files resolve `package:flutter` where they now sit.

## 0.5.1

### Fixed

- `isolate` read an extension type's name through `ExtensionTypeDeclaration.primaryConstructor`,
  which analyzer 14 deprecates in favour of `namePart`. Since the package supports analyzer 13 as
  well, where `namePart` does not exist on that node, the name now comes from the declaration's
  `ClassNamePart` child, which both versions expose. Behaviour is unchanged; the deprecation warning
  that cost points on the pub.dev static analysis report is gone.

## 0.5.0

Every fix below changes what `isolate` writes, and the first one changes the metrics `analyze`
reads back out of it, so results from 0.4.0 and 0.5.0 cannot be compared or pooled.

### Fixed

- `isolate` discarded part of what its own dependency crawl resolved. The cross-file loop recursed
  into each inlined declaration with a new visitor and then read only that visitor's list of
  further cross-file references, dropping every declaration it had resolved inside the file it was
  already reading. The base class of an inlined widget is the case that mattered: a widget is
  inlined precisely because its resolved supertype chain reaches `Widget`, so emitting the subclass
  without its base left the chain broken. That is not only a compile error. `analyze` decides
  between a widget and a value object by walking that chain, so the allocation moved into
  `valueObjectAllocCount` and its whole build subtree went missing from the metrics.
- A rebuild scope's own constructor was copied verbatim into the generated `_GeneratedWidgetState`,
  where its name no longer matches the enclosing class and Dart reads it as a bodiless method. The
  constructor is now dropped, and fields it used to initialise are marked `late` so dropping it does
  not leave them unassigned. Both field formal parameters and initialiser lists are recognised.
  Consumer and builder scopes were hit hardest, because converting one into a `State` harness
  carried its widget constructor across.
- Default values written with the pre-Dart-3 separator, `{int flex: 2}` and `[double size: 8]`, are
  rewritten to use `=`. Repository code old enough to use the colon form used to be copied verbatim
  into a file that a modern SDK then refuses to parse.
- The symbols the generated `initState` assigns from are now declared in the isolated file. A lifted
  field was seeded from `fixtureWallets` and a captured global from `fooValue`, but nothing declared
  either name, so the file carried an undefined-name error and `analyze` skipped it. Each is
  declared `late` and left unassigned on purpose: a fabricated default would be measured as though
  it were the value that was really there.
- Members reached through an extension, such as `10.sp` or `context.h`, were dropped by the
  dependency crawl, which matched only members enclosed by a class. Extensions are now matched too.

### Changed

- `isolate` no longer drops the dependencies it does not inline. A declaration that can build UI is
  inlined whole, which now includes a class that is not a widget itself but declares a member
  returning one, since `analyze` walks the body of every widget-returning helper a scope calls.
  Everything else, including third-party symbols that were previously excluded outright, gets a
  declaration-only stand-in: the name, the members the scope actually reaches, and nothing else.
  Bodies throw and constants are `null`.
- A stand-in mirrors whether the original was a widget, so a third-party widget still classifies as
  a widget and a value object still classifies as a value object. It cannot reproduce that widget's
  own `build` body, so an isolated scope that instantiates a third-party widget reports a smaller
  tree than the same scope measured inside its original project.
- The isolated file's layout is unchanged. Stand-ins and seeds are appended to the same file rather
  than written to a separate dependencies file, so output paths and the mapping JSONL are the same
  as before.

## 0.4.0

### Added

Every `analyze` row now reports the files its metrics were computed from, and whether all of them
could be read.

- Three columns appended after the 14 metrics, so column order for existing consumers is unchanged:
  `dependencyFiles`, `unresolvedDependencies`, and `closureResolved` (`1`/`0`). Paths are relative
  to the analyzed project root and sorted; closure entries outside that root, such as the SDK and
  the pub cache, are dropped, since neither is editable by a commit in the analyzed repository.
- `dependencyFiles` lists the transitive closure a row actually depends on, the declaring file
  included. A scope's metrics are not a function of `filePath`: helper methods and getters resolve
  across libraries, and every custom child widget's `build()` is merged into the totals. Selecting
  revisions by "touched the declaring file" therefore drops real changes, and drops them hardest in
  well-composed code, where child trees are deepest.
- `unresolvedDependencies` lists closure libraries that could not be read, by path where one is
  known and by library URI otherwise. A non-empty list means the row is incomplete by an unknown
  amount rather than absent, so it can be rejected downstream.

### Fixed

- A closure library that resolves while carrying an error-severity diagnostic is now recorded as
  unresolved. Such a library resolves its types to null, so its widgets classify as value objects
  and its subtree lands in the wrong metrics. The scanned/skipped counts in the run summary never
  caught this: they guard only the file being scanned, not the files its metrics are read from.
  The index is still built, so the numbers this release emits are unchanged; what changes is that
  the row now says the numbers are untrustworthy.
- The library cache records its verdict alongside the index, and every lookup is attributed to the
  scope that made it. The cache lives for a whole run, so a second scope reaching a broken library
  through a cache hit used to be recorded as clean, and a shared dependency appeared only on the
  first row that touched it.
- `isolate` lifts the bindings a rebuild scope closed over. A builder callback reads parameters and
  locals of the method it sits in, and a scope on a package-supplied base class such as `GetView`
  reads members it inherits; neither travels with the transplanted source, so the isolated file
  referenced names nothing declared.
- Lifting a promoted parameter to a field costs it its promotion, because Dart does not promote
  fields. References whose promoted type was a proper subtype of the declared type are now wrapped,
  so `state.wallets` becomes `(state as WalletLoaded).wallets` and the isolated file still compiles.
- A field named `context` is no longer copied onto the generated `State`, where it shadowed
  `State.context` and broke the output.
- Stripping nullability from a lifted field's type touched the whole type string, rewriting
  `(Wallet?, Wallet?)` to `(Wallet, Wallet)` and `Map<String, int?>` to `Map<String, int>`. Only the
  trailing `?` is dropped now.
- `monitorDataFlow` and `monitorPerformance` returned their completer's future from inside a `try`,
  which `lints_core` flags and which never routed a rejection through that `catch` anyway. The
  return moved after the block; the guarded statements and the error path are unchanged.

### Changed

- `isolate` generates an `initState` that seeds every lifted field from a conventionally named
  symbol: field `wallets` is assigned `fixtureWallets`, and a cross-file project global `foo` is
  assigned `fooValue`. The names a scope needs are predictable instead of being rediscovered per
  scope. A scope that brought its own `initState` keeps it.
- `isolate` runs `dart format` over its output directory. The transplant concatenates fragments that
  keep their original indentation, so two runs used to differ in layout as well as in code.
  Formatting failures are ignored: an unparseable scope is still written out for inspection.
- `TreeExtractor.extract` returns an `ExtractionSet<TreeFeaturesSet>` record, pairing the feature
  set with its closure. This type is internal to `lib/src/`; the public API is unchanged.

## 0.3.0

### Fixed

Six build-tree metric defects, found by checking extracted values against what the analyzed source
actually does. Every one of them changes numbers that 0.2.0 emitted, so metrics from the two
versions cannot be compared or pooled.

- Helpers returning a collection of widgets were skipped. `List<Widget> _buildRows()` and
  `List<DropdownMenuItem<T>> _buildItems()` are widget factories, but the return type had to be a
  `Widget` subtype for the reference to count, and `List` is not one, so the reference went
  uncounted and the body was never read. SDK collection methods such as `toList` and `cast` stay
  excluded: their type says `List<Widget>` but they build nothing.
- A `const` swap inside a helper body moved no metric. Helper const widgets were added to
  `helperWidgetCount` alongside non-const ones, which erased the distinction. Const widgets in a
  helper now count toward `treeConstWidgetCount`, and `helperWidgetCount` covers non-const helper
  widgets only, matching how build bodies were already split.
- List widgets other than `ListView` and `GridView` were left unclassified. `ReorderableListView`,
  `PageView`, and `ListWheelScrollView` are now classified by constructor, and `AnimatedList`,
  `AnimatedGrid`, and the remaining sliver lists are treated as lazy by contract. Their lazy
  builders also mark the widgets they build as per-element cost.
- Sliver laziness ignored the delegate. `SliverList(delegate: SliverChildListDelegate([...]))`
  builds every child up front and is now eager (2). A builder delegate stays lazy (1).
- `List.generate` read as a single allocation. It is a factory constructor, so the `generate` case
  in the method-invocation path never saw it. It now counts as iteration, and the widgets its
  callback builds count as per-element cost.
- Local functions lost their per-element attribution. A local function declared above a loop and
  invoked inside it was read at its declaration site, outside any iteration scope, so a row built
  per element looked like a one-off. Bodies are now read at the first call site. A local function
  that is never referenced is still read once, at the end of the traversal.

### Changed

- `rootBuildReturnsConstWidget` now requires every top-level return to be const. A single const
  return used to set it, so a build that returns a full tree on its common path and
  `const SizedBox.shrink()` from a loading guard was recorded as a const build.

## 0.2.0

### Changed

- Documented the planned 1.0.0 static screening direction: classify UI changes as stable or faster
  (`0`) or slower (`1`) from build-tree metrics without running or profiling the app.

### Removed

- **Breaking:** Removed the legacy `package:spm/features/profiler/presentation/` compatibility
  exports. Import `SpmState` and `SpmProfiler` from `package:spm/spm.dart`.

## 0.1.2

### Added

- `example/spm_example.dart`, named to match pub.dev's package-example convention, so the package
  page renders an Example tab.

### Changed

- Filled in missing dartdoc coverage on `SpmProfiler` and its exported libraries.
- Tightened prose across README and CONTRIBUTING.

## 0.1.1

### Changed

- Declared Android as the only supported platform, so the pub.dev package page lists Android alone.

## 0.1.0

`analyze` now extracts metrics from every rebuild scope, not only `State` subclasses.

### Added

- `analyze` emits a row for each rebuild scope: `State` subclasses, `ConsumerWidget` /
  `HookConsumerWidget` classes, and the inline builder callbacks of `BlocBuilder`, `BlocSelector`,
  `BlocConsumer`, `Consumer`, `Selector`, `Obx`, `GetX`, `GetBuilder`, and `Observer`, the same
  kinds `isolate` detects.
- `--scope-types` / `-s` on `analyze` (repeatable) narrows the emitted kinds;
  `-s State` reproduces the previous output.
- New `scopeType` column on every JSONL row, and a per-type breakdown in the run summary.

### Changed

- **Breaking (JSONL):** the `stateClassName` column is now `scopeName`. `inject` reads either
  spelling, so manifests produced by earlier versions still work; other downstream consumers must
  be updated.
- `inject` skips manifest rows whose `scopeType` is not `State`, so a full-scope `analyze` output
  can be passed to it unchanged.
- Scope detection is shared between `analyze` and `isolate` instead of duplicated: the kind lists
  live in `AppConstants` and the predicates in the analysis feature's scope detector.
- SPM now stands for **Scope Performance Metrics** (was "State Performance Metrics"), matching what
  the tool measures. The package, the `spm` executable, and every public identifier are unchanged.

### Notes

- Scopes nest, and their metrics overlap on purpose: a `State` row counts the widgets built inside
  its nested builder callbacks *and* each callback gets its own row. Aggregations that sum rows per
  file should filter by `scopeType`.
- `instanceId` values for `State` scopes are unchanged, so existing joins with runtime profiler
  data still hold.

## 0.0.3

- Export `SpmProfiler` from the public `package:spm/spm.dart` API.
- Add compatibility export paths for profiler imports under `package:spm/features/profiler/presentation/`.
- Restore support for benchmark and integration-test code that imports `SpmState` and `SpmProfiler` through the profiler presentation path.

## 0.0.2

- Add a public API example for `SpmState`.
- Document the `SpmState` constructor for subclass usage.
- Widen the analyzer dependency constraint.
- Link the published pub.dev package from the README and wiki.

## 0.0.1

- Initial pub.dev release of SPM.
- Adds CLI commands for Flutter rebuild analysis, validation, profiler injection, profile-mode runs, and rebuild-scope isolation.
