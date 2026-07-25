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
spm analyze -o static.jsonl /path/to/flutter/project
spm validate --base base.dart --mutation mutation.dart --deps dependencies.dart --json
spm inject -j static.jsonl /path/to/flutter/project
spm run -j static.jsonl -r /path/to/flutter/project --flutter drive --target=integration_test/integration_test.dart
spm isolate -o isolated_widgets /path/to/flutter/project
```

## Installation

Install the CLI globally:

```bash
dart pub global activate spm
```

Or add it to a Flutter project for local use:

```bash
flutter pub add dev:spm
dart run spm:spm analyze -o static.jsonl /path/to/flutter/project
```

Flutter code that is instrumented by SPM imports the public API with
`import 'package:spm/spm.dart';`.

## Repository Layout

```text
bin/        CLI entry point
lib/spm.dart public Flutter integration API
lib/src/    SPM implementation
test/       unit tests and fixtures
```

## Related Artifact

SPM can be used on its own or together with the companion `benchmark_container` repository, which contains a benchmark harness, sample corpus, measured dataset artifacts, and modeling scripts.

## Contributing

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and the [Project Wiki](https://github.com/albertoodev/spm/wiki/Contributing).
