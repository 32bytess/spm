# Changelog

## 0.5.1

### Fixed

- `isolate` read an extension type's name through `ExtensionTypeDeclaration.primaryConstructor`,
  which analyzer 14 deprecates in favour of `namePart`. Since the package supports analyzer 13 as
  well, where `namePart` does not exist on that node, the name now comes from the declaration's
  `ClassNamePart` child, which both versions expose. Behaviour is unchanged; the deprecation warning
  that cost points on the pub.dev static analysis report is gone.

## 0.5.0

Every fix below changes what `isolate` writes, and the first one changes the metrics `analyze`
reads back out of it, so results from 0.4.0 and 0.5.0 cannot be compared or mixed in one dataset.

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
versions cannot be compared or mixed in one dataset.

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

- Documented SPM's research-dataset origin and planned 1.0.0 static screening direction: classify
  UI changes as stable or faster (`0`) or slower (`1`) from build-tree metrics without running or
  profiling the app.

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
  `BlocConsumer`, `Consumer`, `Selector`, `Obx`, `GetX`, `GetBuilder`, and `Observer` — the same
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
