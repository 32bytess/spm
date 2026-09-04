import 'package:path/path.dart' as p;

/// Whether [path] is the project rooted at [root] or sits inside it.
///
/// Three callers ask this while deciding whether a reference is the project's
/// own code or something it depends on, and each used to carry its own copy of
/// the same two comparisons. They agree today; two of them disagreeing would
/// mean a declaration inlined by one gate and stood in for by another, which
/// is the failure the shared answer removes.
///
/// [p.isWithin] is false for the root itself, so the equality check is not
/// redundant: a scope declared in the root directory is project-local.
bool isWithinRoot(String root, String path) =>
    p.isWithin(root, path) || p.equals(root, path);
