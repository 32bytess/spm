# State Performance Metrics (SPM)

SPM is a Dart/Flutter command-line tool for analyzing Flutter rebuild scopes, validating structure-only widget mutations, and collecting profile-mode rebuild measurements.

It supports rebuild-performance analysis workflows by providing:

- static feature extraction from Flutter `State.build()` trees;
- recursive traversal of reachable helper methods and custom child widgets;
- validation of base/mutation pairs for structure-only changes;
- temporary profiler injection for profile-mode rebuild measurement;
- JSONL outputs for downstream dataset construction and modeling.

For full documentation, please visit our [Project Wiki](https://github.com/albertoodev/spm/wiki).

## Commands

```bash
dart run bin/spm.dart analyze -o static.jsonl /path/to/flutter/project
dart run bin/spm.dart validate --base base.dart --mutation mutation.dart --deps dependencies.dart --json
dart run bin/spm.dart inject -j static.jsonl /path/to/flutter/project
dart run bin/spm.dart run -j static.jsonl -r /path/to/flutter/project --flutter drive --target=integration_test/integration_test.dart
dart run bin/spm.dart isolate -o isolated_widgets /path/to/flutter/project
```

## Installation

Use SPM as a Git dependency from a Flutter project:

```yaml
dev_dependencies:
  spm:
    git:
      url: https://github.com/albertoodev/spm.git
```

Then run:

```bash
flutter pub get
```

## Repository Layout

```text
bin/        CLI entry point
lib/        SPM implementation
test/       unit tests and fixtures
```

## Related Artifact

SPM can be used on its own or together with the companion `benchmark_container` repository, which contains a benchmark harness, sample corpus, measured dataset artifacts, and modeling scripts.
