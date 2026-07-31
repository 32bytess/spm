# Contributing to SPM

SPM is still pre-1.0, so focused fixes and small feature additions are welcome. The wiki's
[Contributing](https://github.com/32bytess/spm/wiki/Contributing) page explains where each type of
change belongs; this file covers the repository gate.

## Set up the repository

```bash
git clone https://github.com/32bytess/spm.git
cd spm
dart pub get
```

You need Dart 3.9.2 or newer and Flutter 3.3 or newer.

## Check a change

Run the full local gate before opening a pull request:

```bash
dart format .
dart analyze
dart test
dart pub publish --dry-run
```

The package must publish from a committed worktree. If the dry run reports only uncommitted files,
commit the intended changes and run it again.

## Keep the change contained

- Put implementation libraries under `lib/src/`.
- Keep the supported public API in `package:spm/spm.dart` unless the change deliberately adds a new
  public surface.
- Add or update tests for changed behavior. Use hand-written fakes rather than mocks.
- Update the wiki when changing CLI flags, JSON fields, event names, validation codes, or
  architecture.
- Prefer one feature area per pull request.

The `wiki/` directory is a separate Git repository. Commit its changes there as well as any changes
in the main repository.

## Describe the pull request

Explain what changed, why it changed, which checks you ran, and which documentation you updated. If
documentation was unnecessary, say why.
