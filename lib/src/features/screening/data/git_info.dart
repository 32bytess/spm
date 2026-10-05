import 'dart:io';

/// The few git facts `spm screen` needs, read with the `git` executable.
class GitInfo {
  final String root;
  final String head;
  final bool dirty;

  GitInfo._(this.root, this.head, this.dirty);

  /// Null when [directory] is not inside a git work tree or git is missing.
  static Future<GitInfo?> of(String directory) async {
    final root = await _git(directory, ['rev-parse', '--show-toplevel']);
    final head = await _git(directory, ['rev-parse', 'HEAD']);
    if (root == null || head == null) return null;
    final status = await _git(root, [
      'status',
      '--porcelain',
      '--untracked-files=normal',
      '--',
      '.',
      ':(exclude).spm',
    ]);
    return GitInfo._(root, head, (status ?? '').isNotEmpty);
  }

  /// Whether [commit] is [head] or one of its ancestors.
  Future<bool> isAncestorOfHead(String commit) async {
    final r = await Process.run('git', [
      'merge-base',
      '--is-ancestor',
      commit,
      head,
    ], workingDirectory: root);
    return r.exitCode == 0;
  }

  static Future<String?> _git(String dir, List<String> args) async {
    try {
      final r = await Process.run('git', args, workingDirectory: dir);
      return r.exitCode == 0 ? (r.stdout as String).trim() : null;
    } on ProcessException {
      return null;
    }
  }
}
