# Changelog

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
