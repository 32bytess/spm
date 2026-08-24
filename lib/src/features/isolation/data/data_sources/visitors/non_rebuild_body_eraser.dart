import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:spm/src/core/rebuild_path.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/skeletonizer.dart';

/// Empties the body of every closure that cannot run during a rebuild.
///
/// `spm analyze` prunes these bodies before it counts anything, so nothing
/// inside one can move a feature. `spm isolate` copied them anyway and paid for
/// it twice: the crawl carried whole navigation targets and stood in for the
/// services they call, and the file then failed to analyse over code the
/// metrics never read. A file carrying an error-severity diagnostic is skipped
/// outright, so that cost is a lost sample rather than a wrong row.
///
/// Paired with the gate in `DependencyExtractorVisitor.visitFunctionExpression`.
/// Neither half works alone: erasing without gating carries dependencies for
/// source that is gone, and gating without erasing leaves the names in the file
/// with nothing to resolve against.
///
/// ## What replaces the body
///
/// An empty block wherever the closure returns nothing, and a throw wherever it
/// returns a value. `{}` completes normally with null, which a
/// `String? validator` tolerates and a `Future<bool> confirmDismiss` does not;
/// a body that always throws satisfies every return type because it never
/// completes normally, which is the reasoning `ShimEmitter` applies to a
/// stand-in method body.
///
/// The distinction is not pedantry, because not every slot here is a user
/// interaction. `AppConstants.nonRebuildCallbackHosts` also covers `then`,
/// `addListener`, `addPostFrameCallback`, `scheduleMicrotask`, `Timer` and
/// `Future.delayed`, and those bodies do run, moments after the scope mounts.
/// Throwing in one of them would trade an analyzer error for an uncaught
/// exception around the first frame, which no analyzer run would report. They
/// are void-returning almost without exception, so they take the empty-block
/// branch and stay harmless.
///
/// The `async` / `sync*` modifier is kept, so the closure's own type does not
/// change; only the code inside it does.
class NonRebuildBodyEraser extends SourceRewriter {
  /// Left where a body was removed, so the edit is visible in the output and
  /// countable from it.
  static const String marker = '/* spm: non-rebuild body erased */';

  @override
  final List<Replacement> replacements = [];

  /// Bodies erased across every node this rewriter has been run over.
  ///
  /// Not cleared by [reset], which drops the previous node's edits: the count
  /// is reported once per scope, and a scope is skeletonised in many pieces.
  int erasedBodies = 0;

  @override
  void reset() => replacements.clear();

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (!isNonRebuildCallback(node)) {
      super.visitFunctionExpression(node);
      return;
    }

    final body = node.body;
    // An empty or external body has nothing to erase, and nothing inside it to
    // descend into either.
    if (body is! BlockFunctionBody && body is! ExpressionFunctionBody) return;

    final modifier = [
      if (body.keyword != null) body.keyword!.lexeme,
      if (body.star != null) body.star!.lexeme,
    ].join();
    final closureType = node.staticType;
    final filler =
        completesWithNoValue(
          closureType is FunctionType ? closureType.returnType : null,
        )
        ? ''
        : ' throw UnimplementedError();';

    // The whole body is replaced, arrow bodies included: `=> expr` becomes a
    // block, which is legal in every position a function body is.
    replacements.add(
      Replacement(body.offset, body.length, '$modifier{ $marker$filler }'),
    );
    erasedBodies++;

    // Do not descend. What is left inside is unreachable source, and an edit
    // nested inside this one could not survive the right-to-left pass.
  }

  /// Whether an empty body would satisfy [returnType].
  ///
  /// For a closure this is read from its own inferred type, which downward
  /// inference took from the slot it sits in, so `onPressed: () { … }` answers
  /// `void` and `validator: (v) { … }` answers `String?`.
  ///
  /// One `Future` layer is unwrapped, because an `async` body keeps its
  /// modifier and an empty one completes with `Future<Null>`.
  ///
  /// A type that did not resolve answers false. The throw compiles against
  /// anything; the empty block does not, and an unusable file is the more
  /// expensive of the two mistakes.
  static bool completesWithNoValue(DartType? returnType) {
    if (returnType == null) return false;

    var type = returnType;
    if (type is InterfaceType &&
        type.element.name == 'Future' &&
        type.typeArguments.length == 1) {
      type = type.typeArguments.single;
    }

    return type is VoidType || type is DynamicType || type.isDartCoreNull;
  }
}
