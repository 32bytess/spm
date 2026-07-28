# Changelog

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
