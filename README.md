# Scope Performance Metrics (SPM)

SPM finds rebuild scopes in Flutter projects and records the work performed by their build trees.
It handles `State.build()` methods, consumer widgets, and builder callbacks from packages such as
Bloc, Riverpod, and GetX.

Use the CLI to:

- extract static build-tree metrics as JSONL;
- check that a widget mutation changes structure without changing content or state;
- instrument `State` classes and collect profile-mode rebuild measurements;
- extract a rebuild scope into a smaller widget for isolated profiling.

The [project wiki](https://github.com/32bytess/spm/wiki) contains the command reference, JSONL
schemas, metric definitions, and architecture notes. The package is published on
[pub.dev](https://pub.dev/packages/spm).

## Project status

SPM pairs static build-tree metrics with profile-mode `buildSpan` measurements. For 1.0.0, the goal
is to use those static metrics to screen a UI change without running or profiling the app. The
binary result will indicate whether UI-thread frame build duration is stable or faster (`0`) or
slower (`1`). This classifier is not available in the current release.

## Install

Install the executable globally:

```bash
dart pub global activate spm
```

Or add SPM to a Flutter project as a development dependency:

```bash
flutter pub add dev:spm
dart run spm:spm analyze -o static.jsonl /path/to/flutter/project
```

Instrumented Flutter code imports the public API from `package:spm/spm.dart`.

## Commands

```bash
spm analyze -o static.jsonl /path/to/flutter/project
spm validate --base base.dart --mutation mutation.dart --deps dependencies.dart --json
spm inject -j static.jsonl /path/to/flutter/project
spm run -j static.jsonl -r /path/to/flutter/project --flutter drive --target=integration_test/integration_test.dart
spm isolate -o isolated_widgets /path/to/flutter/project
```

Start with the wiki's [Getting Started](https://github.com/32bytess/spm/wiki/Getting-Started)
page for an end-to-end run. See [example/spm_example.dart](example/spm_example.dart) for
the smallest public API example.

## Repository layout

```text
bin/         CLI entry point
lib/spm.dart supported Flutter integration API
lib/src/     internal implementation
test/        tests and fixtures
wiki/        separate Git repository for the project wiki
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
