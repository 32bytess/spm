# Scope Performance Metrics (SPM)

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23171328.svg)](https://doi.org/10.5281/zenodo.23171328)

SPM finds rebuild scopes in Flutter projects and records the work performed by their build trees.
It handles `State.build()` methods, consumer widgets, and builder callbacks from packages such as
Bloc, Riverpod, and GetX.

Use the CLI to:

- extract static build-tree metrics as JSONL;
- check that a widget mutation changes structure without changing content or state;
- instrument `State` classes and collect profile-mode rebuild measurements;
- extract a rebuild scope into a smaller widget for isolated profiling, and check that the result
  reaches a frame.

The [project wiki](https://github.com/32bytess/spm/wiki) contains the command reference, JSONL
schemas, metric definitions, and architecture notes. The package is published on
[pub.dev](https://pub.dev/packages/spm).

## Project status

SPM pairs static build-tree metrics with profile-mode `buildSpan` measurements. Since 0.8.0,
`spm screen` uses those static metrics to screen a UI change without running or profiling the app.
It compares the working tree against a stored snapshot and, for every rebuild scope whose metrics
moved, gives two verdicts on the direction of its rebuild cost: a count rule (more non-const
widgets means likely slower) and a frozen random forest over eight metric deltas.

The verdicts are a direction, never a build time. The forest was trained on measurements from one
device, and neither verdict has been evaluated with developers or in CI. Treat a flag as a reason to
measure, not as a measurement.

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
spm isolate -o isolated_widgets -j map.jsonl /path/to/flutter/project
spm screen snapshot lib/                      # store a baseline for the current commit
spm screen compare lib/ --fail-on either      # screen the working tree against it
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
tool/        regenerates the embedded screening model
wiki/        separate Git repository for the project wiki
```

## Citing

If you use SPM in research, cite it with the metadata in [CITATION.cff](CITATION.cff). GitHub's
"Cite this repository" button reads the same file.

SPM is archived on Zenodo. [10.5281/zenodo.23171328](https://doi.org/10.5281/zenodo.23171328)
always resolves to the latest release; cite
[10.5281/zenodo.23171329](https://doi.org/10.5281/zenodo.23171329) for version 0.8.0 specifically.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
