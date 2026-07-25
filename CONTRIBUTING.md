# Contributing to SPM

Thanks for considering a contribution. SPM is still pre-1.0, so changes are welcome, but please keep pull requests focused and easy to review.

## Setup

```bash
git clone https://github.com/albertoodev/spm.git
cd spm
dart pub get
```

Requirements:

- Dart SDK 3.9 or newer
- Flutter 3.3 or newer

## Local Checks

Run these before opening a pull request:

```bash
dart format .
dart analyze
dart test
dart pub publish --dry-run
```

The package should publish cleanly from a committed worktree. If the dry run only warns about uncommitted files, commit your changes and run it again.

## Code Guidelines

- Keep implementation libraries under `lib/src/`.
- Keep the supported public API limited to `package:spm/spm.dart` unless a new public API is intentional.
- Add or update tests for behavior changes.
- Update the wiki when changing CLI flags, JSON fields, event names, validation codes, or architecture.
- Prefer small pull requests scoped to one feature area.

For the full project conventions, see the wiki:

- Architecture: https://github.com/albertoodev/spm/wiki/Architecture
- Development: https://github.com/albertoodev/spm/wiki/Development
- Contributing: https://github.com/albertoodev/spm/wiki/Contributing

## Pull Requests

Please include:

- what changed;
- why it changed;
- tests or commands you ran;
- any docs that were updated.

