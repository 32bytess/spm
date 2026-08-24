# Changelog

## 0.7.0

Everything since 0.6.0. Two things carry the release. `spm analyze` reads a library outside the
analysed directories instead of dropping it and its whole subtree. And both commands stop counting
the code a rebuild cannot run, which is what the body of an `onPressed` is.

Every number `isolate` reported used to stop at `errorCount == 0`, a fact about the analyzer rather
than about the output, and three decisions in the emitters guaranteed that a clean-analysing file
threw before its first frame. Most of what follows is what it takes to make the written file run
rather than merely analyse.

Reading a package library closes the asymmetry the 0.6.0 notes had to state out loud: a transplant
that carried a package widget counted its subtree while the in-place row for the same scope did not,
so the two sides of the comparison were not comparable in either direction.

Output cannot be pooled with 0.6.0's on either side. The emitter produces a different file for the
same scope, and `TreeExtractor` produces different metrics for the same code. That second half is
new: until this release only the isolate output carried a pooling warning.

### Added

- `--[no-]prune-non-rebuild` on `isolate`, on by default. `--no-prune-non-rebuild` reproduces the
  unpruned output, so a run made with and without it is a controlled comparison rather than an
  assertion. Across 179 scopes, pruning takes the files that analyse clean from 25 to 46 and the
  total error count from 2,793 to 1,253, and the 14 feature values are unchanged wherever both
  settings produce a row: 32 of 32 shared scopes byte-identical, which is the invariant the prune is
  allowed to be judged on. Rows go up, 45 to 62, because the files that now analyse contribute their
  own scope. The rows that disappear are duplicate observations of a nested scope that already has a
  transplant of its own.
- `--package-config` on `analyze`. A package version is an input to the metrics now, so two runs
  over one project whose `pubspec.lock` moved between them could differ with no source edit to
  explain it. Pinning one resolved config removes that by construction. The cost is that a subtree
  may be counted against a package version the checkout did not ship with, which is the right trade
  when the question is about the project's own structure.
- `--inline-max-declarations` and `--inline-max-characters` on `isolate`, with the caps raised from
  200 and 200,000 to 2,000 and 2,000,000. The in-place walk has no cap at all now, so a scope that
  exhausts this one undercounts against the row it is meant to be compared with. The counter stays,
  as a number to report rather than a limit to aim at.
- `GeneratedWidget.fixture()`, emitted beside the copied constructor. A scope whose widget declared
  a required field could not be written as `GeneratedWidget()`, and mounting it meant building that
  value first, which is a second fix point outside the fixture block and different for every scope.
  The copied constructor stays, because it is part of the commit's source. A row says which it got
  through `fixtureConstructor`.
- Seven mapping fields on `isolate`. `unseededBindings` names the bindings no value could be built
  for; `fixtureConstructor` says whether the fixture constructor was emitted;
  `droppedLoadingBuilders` counts the one image argument that still cannot come across;
  `carriedUiDeclarations` and `renamedThirdPartyDeclarations` record what was carried and under what
  name; `erasedNonRebuildBodies` counts the closure bodies emptied; and `droppedUnreachableMembers`
  names the members left out. That last one is named rather than counted, because a member missing
  that should not be is the failure mode of the prune and a count cannot say which one. The run also
  reports how many scopes gave their third-party source back.
- Two analyze fields. `packageVersions` records the resolved version of every package the closure
  entered, so the pin above is auditable, and `walkedWidgetClasses` records the non-SDK classes
  walked in place. The second is the other half of a check that could not be computed before: for
  every declaration `analyze` walks, `isolate` has to carry the source, or the two rows describe
  different trees.

### Changed

- A closure a rebuild cannot run is no longer entered by `analyze`. Its widgets, allocations,
  iterations, helper references and decision points stay out of the row, and a custom widget built
  inside it no longer seeds the child traversal. Three shapes qualify: a named argument whose label
  is `on` followed by a capital, a named argument called `validator`, `onError`, `onDone`,
  `onCancel` or `confirmDismiss`, and an argument to `then`, `catchError`, `whenComplete`,
  `addListener`, `addPostFrameCallback`, `scheduleMicrotask`, `Future.delayed` or `Timer`. A
  tear-off in one of those slots is treated the same way, and a local function reachable only from
  one is dropped rather than read at the end of the traversal. **Every feature is smaller than 0.6.0
  reported it for any scope holding a handler**, and the reason is that a handler body is not
  rebuild cost: an `onPressed` that pushes a route used to merge a whole other screen's build tree
  into the scope, charging a rebuild for a page it never renders.
- Everything else is still entered: `builder`, `itemBuilder`, `separatorBuilder`, the builder
  callbacks of the supported scope widgets, positional ones included, and any expression in a
  handler slot that is not itself a closure, since a conditional tear-off is evaluated while the
  tree is built.
- `analyze` reads a library outside the analysed directories. `contextFor` throws `StateError` for
  any path in the pub cache, the throw was swallowed, the entry cached as a miss, and the child
  dropped along with its whole subtree. A per-package-root context collection built against the
  application's own package config fixes it. Nothing walks the cache: only the libraries the
  traversal actually enters are resolved. The framework boundary is unchanged and stays a
  correctness decision rather than a cost one, because the visitor counts every branch of a build
  body rather than the branch that ran.
- A library that resolves with errors is now refused, as one that does not resolve at all already
  was. Its types come back null, so its widgets classify as value objects: the row was wrong rather
  than short, which is the trade the scanned-file gate exists to prevent. Repo-local numbers move
  because of this, and `unresolvedDependencies` names what was refused.
- Carrying a package widget is now what makes the isolated row and the in-place row describe the
  same tree, where up to 0.6.0 it did the opposite. Where they still cannot, the row says so:
  `thirdPartyInlineTruncated`, `thirdPartyInlineReverted`, and `carriedUiDeclarations` against the
  analyze row's `walkedWidgetClasses`.
- Reverting an unprofitable inline is a defect count rather than an achievement. It buys a readable
  file by shrinking the tree, which is the wrong direction when the isolated row and the in-place
  row are meant to describe the same thing. The rate is reported, and such a row is one to exclude
  rather than to compare.
- A third-party declaration whose name `package:flutter/material.dart` also exports is carried under
  a mangled name rather than stood in for, and only the references that resolve to it are rewritten.
  The guard's reasoning is unchanged: an inlined third-party `Card` would put a body under every
  `Card(...)` in the transplanted body, including the ones that meant Flutter's. What changes is
  that honouring it no longer costs the subtree.
- A widget stand-in renders its `child`, `children` or `body` instead of swallowing it. The
  constructor accepted the argument and the class built `const SizedBox.shrink()`, so whatever tree
  was passed in was constructed and then never mounted, laid out or painted. `children` wraps in
  `Stack` and not `Column`: `Column` with a non-literal `children:` pins `treeListRenderingStrategy`
  at its ceiling for every scope reaching such a stand-in, in the transplant and nowhere else.
- Stand-in parameter types are `dynamic`. Rendering a type by its nearest nameable supertype while
  the argument at the call site was a stand-in with none is what produced most of the output's
  error-severity diagnostics. Return and field types degrade too, unless the type reaches `Widget`
  directly or as an iterable's element, which is the property the widget-returning-helper rule
  depends on.
- A non-widget stand-in declares its nearest nameable supertype, which carries generic bounds a
  `dynamic` parameter cannot. Members the supertype supplies are not redeclared beside it.
- A stand-in emits every constructor, whatever the member limit says. The two were gated on the same
  flag, so a type over the limit emitted none unless a reference reached one, and a call site's
  named arguments then landed on the implicit default constructor.
- Bindings carry values instead of throwing. Unassigned `late` seeds, `throw UnimplementedError()`
  bodies and unassigned `late dynamic` globals each threw on first read, and the reads are in
  `initState` and `build`. A `dynamic` binding gets a `_Stub` rather than `null`, because the bodies
  read member chains off these and a null only moves the crash from `initState` into `build`. This
  reverses the emitters' stated preference for throwing over inventing, and the reason it is safe is
  that a value is never measured: the features come from the shape of the build tree, and that shape
  is fixed before any of this executes. Where no value of a binding's type can be built the old form
  stays and the name is reported.
- The image rewrite substitutes the source and keeps the node. Replacing the whole construction
  erased `errorBuilder` subtrees, which in place are walked and counted, and turned an
  `ImageProvider` into a widget, moving the same source out of `valueObjectAllocCount` into
  `treeNonConstWidgetCount` and adding a level of depth. It also put a widget in a provider-typed
  slot, which `BoxDecoration(image:)` and `CircleAvatar(backgroundImage:)` reject.
  `loadingBuilder` has no home on `Image.asset` and is the one argument that still drops; it is
  counted and the file carries a marker where it stood.
- A closure `isolate` transplants into a non-rebuild slot keeps its signature, its `async` modifier
  and its place in the tree, and loses its body. The body becomes an empty block where the closure
  returns nothing and a throw where it returns a value: `{}` completes with null, which a
  `String? validator` tolerates and a `Future<bool> confirmDismiss` does not. The distinction is not
  pedantry. The same family covers `then`, `addListener`, `addPostFrameCallback`,
  `scheduleMicrotask`, `Timer` and `Future.delayed`, and those bodies do run, moments after the
  scope mounts, so throwing in one would trade an analyzer error for an uncaught exception around
  the first frame.
- A member of the scope's class that `build()` cannot reach is dropped. A member only a tear-off
  names keeps its signature and loses its body: the reference is evaluated while the tree is built,
  so the name has to resolve. Carrying those members is what used to pull whole navigation targets
  into the file and stand in for the services they called, and a stand-in whose signature then
  failed to type-check cost the file outright, because `analyze` skips any file carrying an
  error-severity diagnostic.
- `initState` and `didChangeDependencies` are dropped like any other member `build` cannot reach,
  and what they seeded moves to the fixture block. A `late final` field the original `initState`
  assigned is now assigned from a top-level fixture symbol declared at the bottom of the file beside
  the bindings lifted from the application. The generated `initState` does the seeding and nothing
  else, so the network calls, listener registrations and notification setup that used to sit beside
  it, and every stand-in they dragged in, are gone. Keeping those two methods was the first answer
  and it was the wrong one: what they contribute is a value, and supplying a value is something the
  transplant already knew how to do.
- Every dependency is now a `late` binding seeded from the block, not only the ones a dropped member
  used to assign. A field the scope declared with its own value, `int _limit = 20;`, becomes
  `late int _limit;` in the State, `_limit = fixtureLimit;` in the generated `initState`, and
  `int fixtureLimit = 20;` at the top level of the file. The value is relocated, never replaced: a
  list seeded with twenty rows still builds twenty. The fixture block is therefore the whole of a
  scope's initial state, in one region, at the top level of the file, which is what lets two
  revisions of one scope be mounted from identical values.
- `final` is dropped from a hoisted binding. A member the prune keeps may still assign the field,
  and `late final` would make that a second write to a final.
- Three kinds of field stay where they are, and every reason is about not moving a feature. `static`
  and `const` fields, because `treeConstWidgetCount` and `rootBuildReturnsConstWidget` are features
  and a `static const` read inside a `const` constructor stops the call being const the moment it
  becomes a variable. A field whose initialiser needs the instance, such as one reading
  `widget.arguments`, because it cannot be evaluated at the top level. And a field with no nameable
  type, because the fixture declaration has to write the type down.
- A generated default no longer names a type argument the file does not declare. A typed empty list
  against a type nothing carried is an error-severity diagnostic, and the untyped literal infers the
  same thing from the context every one of these sits in. This applies with the prune off too.
- The declared type of a lifted binding is requested from the crawl outright. It is rendered from
  the element model rather than from the copied source, so the crawl used to reach it only by
  accident, through some other mention, and a handler body was often the only one.
- Overlapping source edits resolve outermost-first rather than corrupting each other. Edits now come
  from several independent rewriters, and a nested one could not survive the right-to-left pass.
- The rebuild-path predicate is one helper in `core`, shared by `analyze` and `isolate`, so the two
  commands cannot drift on which callbacks a rebuild runs.

### Fixed

- A prefix from a package the isolated file may not import no longer dangles. An SDK prefix such as
  `dart:math as math` was restored and a package one was not, leaving the prefix undefined. It
  becomes a `dynamic` stand-in, so a call through it compiles with no import at all. Restoring the
  directive instead would be `uri_does_not_exist`, which is error severity too.
- A stand-in no longer writes a parameter named after another library's private field.
- The extractor's per-package-root context collections are released at the end of a run. Each one
  runs a driver scheduler, and left alive they accumulate across runs in the same process, which a
  single CLI invocation never notices and a test suite does.

## 0.6.0

Everything since 0.5.2. Two changes carry the release, and both are about `isolate` writing a file
that describes the code it came from. A transplanted StatefulWidget now brings its `State`'s
dependencies with it, and a third-party widget now arrives with its own tree instead of an empty
stand-in. Alongside them, several things that reported success without having earned it now say so
instead.

Output from 0.6.0 cannot be pooled with 0.5.2's: the same scope produces a different file and, where
a package widget is involved, different metrics.

### Added

- `--inline-third-party`, on by default. `--no-inline-third-party` stands every third-party symbol
  in, which is what `isolate` did up to 0.5.2.
- Three mapping JSONL fields, all omitted unless they apply: `inlinedThirdPartyDeclarations` counts
  the third-party declarations carried into a file; `thirdPartyInlineTruncated` marks a scope that
  reached the per-scope budget; `thirdPartyInlineReverted` marks a scope where carrying the code
  analysed worse than standing it in, so the stood-in version was kept. The last two both say the
  file describes a smaller tree than the code it came from builds.
- `helpers/ui_surface.dart` holds the predicate that decides whether a declaration can produce UI,
  in both an AST form and an element-model form, so the transplant's inline gate and the dependency
  visitor's gate cannot drift apart. `helpers/inline_budget.dart` and
  `helpers/flutter_namespace.dart` hold the two limits described below.

### Changed

- The dependency gate now asks "is this the SDK" rather than "is this project-local". The SDK is
  imported, anything that can produce UI is carried as source whether it is repo-local or
  third-party, and everything else becomes a declaration-only stand-in. A third-party
  `StatefulWidget` arrives with its companion `State`, which is the half that matters, since that is
  where the build body lives. A stood-in widget has an empty `build`, so a file full of them
  describes a tree the app never built and cannot be read or run as the scope it came from.
- Carrying third-party source is bounded, unlike the repo-local kind, at 200 declarations or 200,000
  characters per scope. A repo-local closure is bounded by the repository already; a third-party one
  is not, and a scope holding a single state-management builder reaches a widget from which the
  crawl walks into the package's own machinery.
- Carrying is undone per scope when it does not pay. After the output is verified, any scope that
  carried third-party source and still does not analyse is extracted a second time with that source
  stood in for, and whichever version has fewer errors is kept. A package widget generic over a type
  bounded by one of the package's own classes is the shape that needs this: carrying the widget
  brings its real bound along, and the repo-local class that satisfies that bound in the application
  is a stand-in here with no supertype at all, so a file that type-checked against a stand-in's
  `dynamic` stops type-checking. Rather than keep a list of packages that behave this way, both
  answers are analysed and the better one wins, which makes the guarantee exact: no scope ends up
  with more errors than `--no-inline-third-party` would have given it.
- A third-party declaration whose name `package:flutter/material.dart` also exports is stood in for
  rather than carried. A local declaration shadows the import either way, but an empty stand-in
  named `Card` only costs the subtree under each `Card(...)`, where a carried one puts a body under
  every use of the name, including the uses that meant Flutter's.
- The same-file rule, "within a file take everything", was written about project files and now
  applies to package units as well, so it takes the budget and the material-name check with it.
  Without that, a package's own declarations entered through a door the third-party gate does not
  watch.
- `SvgPicture` and `CachedNetworkImage` are no longer in the set of image constructions rewritten to
  `Image.asset('assets/placeholder.png')`. They are widgets from packages, and substituting one
  widget for another was hiding whatever those packages build. The rewrite now requires an SDK-owned
  element, so Flutter's own `Image`, `AssetImage`, `NetworkImage`, `FileImage`, `MemoryImage`,
  `DecorationImage`, `FadeInImage` and `RawImage` still take the placeholder, because an isolated
  file has no assets directory and no network.
- Resolving a dependency's unit is guarded. A third-party reference points at a file outside the
  project rather than inside it, and an unreadable one now costs a stand-in instead of the whole
  scope.
- Unused imports are no longer pruned from the output. The pruner was line based, and `dart format`
  wraps a long `show` clause across lines, so pruning one could leave the rest of the clause behind
  and turn a warning into a parse error. Removing it also removes the re-analysis round trip that
  was the most likely way to reach the verifier's swallowed-diagnostics bug listed under Fixed. An
  unused import is a warning, never an error, so it does not stop `analyze` from reading the file;
  prune it downstream over an AST if the output needs to be clean of them.
- The mapping JSONL ends every line, `analyze`'s output always did.
- Passing the same directory twice no longer isolates every scope in it twice. The per-input
  directory filter it replaces could not admit a context twice for distinct inputs anyway: the
  analyzer roots each context at an included path and merges overlapping ones.
- The walk up to the nearest `.dart_tool/package_config.json` is now one helper,
  `helpers/package_config.dart`, shared by the extractor and the verifier instead of living only in
  the verifier.
- The isolation tests share one transplant run per file rather than repeating it for every test.

### Fixed

- The companion `State` of an inlined StatefulWidget was copied and never visited, so nothing it
  referenced reached the dependency crawl: no stand-in, no import, no cross-file reference. A
  `State` body is where a StatefulWidget keeps everything it depends on, which is what made this
  expensive: a widget whose data types are named only inside its `State` had the code that names
  them carried across and a declaration for none of them. The companion is visited under its own
  class rather than the widget's, so a reference to one of its own methods reads as a member of the
  class that declares it.
- A widget stand-in carried `createState` and `debugFillProperties`, both of which only the
  framework calls and neither of which a stand-in can honour. `createState` returns `State<T>`,
  whose bound is `StatefulWidget`, against a stand-in deliberately collapsed to `StatelessWidget`,
  so standing in for a stateful widget produced a bound violation on the stand-in's own signature.
  `debugFillProperties` names `DiagnosticPropertiesBuilder`, which `package:flutter/material.dart`
  does not export, since `widgets.dart` re-exports foundation as `show Brightness, UniqueKey`.
- Deciding whether an import already provides a name walked the export graph, which ignores `show`
  and `hide`. The analyzer says as much in its own doc comment on `exportedLibraries`, and Flutter
  is built out of those clauses: `widgets.dart` re-exports foundation as
  `show Brightness, UniqueKey`, so every foundation symbol reached from a file importing only
  `material.dart` matched material, and the fallback that would have written the real import never
  ran. The question is now asked of the export namespace, which is the one that honours the clauses.
  `DiagnosticPropertiesBuilder`, `Diagnosticable`, `kDebugMode` and `compute` are all this shape.
- A builder given a tear-off rather than an inline closure was a scope to `isolate` and not to
  `analyze`. There is no callback body at the creation site, so the transplant fell through to its
  expression fallback and returned the function itself where a `Widget` belongs: a file that can
  never analyse clean, a row in the mapping, and a count in the summary, for a scope `analyze` never
  reports. `findBuilderArgument` now returns only a `FunctionExpression`, so both commands take the
  rule from one place.
- The verifier reported a file it could not analyse as a file with no errors. Every failure to
  fetch diagnostics was swallowed and became an empty diagnostic list, which is indistinguishable
  from a clean run. It now reports `verified: false`, which is what the unverified and clean split
  existed to express.
- `sourceDependenciesResolved` could only ever be false once per checkout. An existing
  `package_config.json` was taken as proof that resolution had happened, and the minimal config
  `isolate` writes when `pub get` fails satisfies that check, so the flag fired on the run that
  created the file and never again. Walking a repository's history, where a worktree keeps its
  `.dart_tool` across checkouts, that is every revision after the first. A config `isolate` wrote
  itself now counts as unresolved, and a directory with no pubspec and no config above it does too.
  **Counts of this flag taken from output written by 0.5.2 or earlier are floors.**
- `isolate` accepted a directory that does not exist and reported success over zero scopes. A
  missing path resolves to a context rooted at the nearest real package above it, whose files are
  then all filtered out, so a typo read exactly like a project with no rebuild scopes in it. An
  input that produces no analysis context at all is now an error too.
- The set of projects whose dependencies failed to resolve was never cleared between calls. The
  data source is a lazy singleton, so a second `isolate()` in the same process still carried the
  first one's verdict and marked `sourceDependenciesResolved: false` on rows from a project that
  resolved perfectly well. Only the CLI, which runs one isolation per process, was unaffected.

### Notes

- Carrying a package widget does **not** make an isolated row match the in-place row, which is the
  obvious guess and the wrong one. `BuildMetricsVisitor` does record a non-SDK widget as a custom
  child, but `TreeExtractor` then asks `AnalysisContextCollection.contextFor` for its file, and that
  throws for any path outside the analyzed roots, which is where a package's source sits. The child
  is dropped and its subtree with it, so `analyze` never counted a package widget's tree in place
  either. A row that carried one therefore counts **more** than the same scope does in place, not
  less. Isolated and in-place numbers are not comparable across that boundary in either direction.

## 0.5.2

`isolate` now analyses what it wrote before it reports success, so every run says how many of its
files a later `spm analyze` can actually read. The fixes below all change what `isolate` writes.
Files produced by 0.5.1 and earlier carry imports of packages that were never meant to be there and
references to names nothing declares, so they cannot be pooled with 0.5.2 output.

### Fixed

- The gate that decides which libraries an isolated file may import tested `package:flutter` without
  the trailing slash, so every pub package whose name begins with `flutter` passed as an SDK
  library. Each one was imported back into the isolated file instead of being stood in for, leaving
  output that only resolves inside the project it came from. Sizing extensions such as `.sp` and
  `.w` were the visible half of this, since the import
  that was supposed to define them does not exist where the file is read.
- Import prefixes were dropped. A scope whose source read `import 'dart:math' as math;` was written
  out with a plain `import 'dart:math';`, so every `math.pi` and `math.Random()` in the transplanted
  body became an undefined name. Prefixes, `show` clauses and `hide` clauses now travel with the
  import, including prefixes from the other files a transplant copied code from. A `deferred` import
  is deliberately not copied: the generated `build` never calls `loadLibrary()`.
- The branch that matched a reference back to the import directive it came through read the
  directive's element under two names the current analyzer does not expose, so it threw and was
  skipped for every import. Every import fell to a fallback that rebuilds the directive from the
  library's URI alone, which is where the prefixes and combinators were being lost.
- A declaration written in a `part` file was reported against the file that defines the library, so
  the same-file lookup searched a unit that does not declare it, found nothing, and marked the name
  handled on the way out. Private widgets declared in a part were left undefined, which does not
  merely fail to compile: `analyze` skips the subtree of a child widget it cannot reach, so the row
  is wrong rather than absent.
- A same-file lookup that found nothing, and a cross-file reference whose file did not resolve, both
  used to leave the name dangling. Each now falls back to a declaration-only stand-in.
- A stand-in carried only the members the crawl happened to reach, so a controller could arrive with
  `removeListener` and without `addListener`. Members are now recorded against the type the code
  names rather than the type that declares them, which is what was losing every member inherited
  from a Flutter base class such as `ChangeNotifier`, and a type that declares 40 members or fewer
  comes across whole.

### Added

- References the analyzer resolves to nothing now get stand-ins rebuilt from the call sites. Two
  situations produce them: an extension defined in a package the isolated file may not import, which
  is what `context.read<T>()`, `context.watch<T>()` and `context.select<T, R>()` are, and a source
  project whose own `pub get` never succeeded, where no third-party name resolves at all. An
  unresolved constructor call in a widget position is stood in for by a widget, so the allocation is
  still counted as one.
- `isolate` analyses the files it wrote, in the same process, before reporting. Imports nothing uses
  are removed, and each mapping row gains `verified`, `errorCount`, `warningCount`, `topCodes`,
  `unresolvedImports` and `unresolvedNames`. The run prints how many files analyse clean, which is
  the number that decides how much of the output `analyze` can read.
- A row carries `sourceDependenciesResolved: false` when the project it came from had no resolvable
  dependencies, so a consumer can exclude or re-run those rows instead of treating their metrics
  as comparable. The condition is logged as an error when it happens rather than passing silently.
- The output directory gets a `pubspec.yaml` and a `.dart_tool/package_config.json` borrowed from
  the source project, so the isolated files resolve `package:flutter` where they now sit.

## 0.5.1

### Fixed

- `isolate` read an extension type's name through `ExtensionTypeDeclaration.primaryConstructor`,
  which analyzer 14 deprecates in favour of `namePart`. Since the package supports analyzer 13 as
  well, where `namePart` does not exist on that node, the name now comes from the declaration's
  `ClassNamePart` child, which both versions expose. Behaviour is unchanged; the deprecation warning
  that cost points on the pub.dev static analysis report is gone.

## 0.5.0

Every fix below changes what `isolate` writes, and the first one changes the metrics `analyze`
reads back out of it, so results from 0.4.0 and 0.5.0 cannot be compared or pooled.

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
  locals of the method it sits in, and a scope on a package-supplied base class reads members it
  inherits; neither travels with the transplanted source, so the isolated file referenced names
  nothing declared.
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
versions cannot be compared or pooled.

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

- Documented the planned 1.0.0 static screening direction: classify UI changes as stable or faster
  (`0`) or slower (`1`) from build-tree metrics without running or profiling the app.

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
  `BlocConsumer`, `Consumer`, `Selector`, `Obx`, `GetX`, `GetBuilder`, and `Observer`, the same
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
