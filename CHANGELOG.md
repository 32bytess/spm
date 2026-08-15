# Changelog

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
