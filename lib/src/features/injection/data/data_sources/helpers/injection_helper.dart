import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:spm/src/core/constants/app_constants.dart';
import 'package:spm/src/core/errors/exceptions.dart';
import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/injection/data/data_sources/visitors/state_class_finder_visitor.dart';
import 'package:spm/src/features/injection/domain/entities/injection_mode.dart';

class InjectionHelper {
  /// Reads a JSONL file and yields each line as a [JsonRecord].
  ///
  Stream<JsonRecord> readJsonlStream(String filePath) async* {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileNotFoundException('File not found: $filePath');
    }
    if (!filePath.endsWith('.jsonl')) {
      throw FileTypeException('File is not a JSONL file: $filePath');
    }
    final lines = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isNotEmpty) {
        yield jsonDecode(line) as JsonRecord;
      }
    }
  }

  /// Applies/Reverses State class injections to the given file based on the
  /// targets and mode, and writes the modified content back to the file.
  ///
  AsyncVoid applyInjection({
    required AnalysisContextCollection collection,
    required String filePath,
    required List<JsonRecord> targets,
    required InjectionMode mode,
  }) async {
    final file = File(filePath);

    if (!file.existsSync()) {
      throw FileNotFoundException('File not found: $filePath');
    }
    if (!filePath.endsWith('.dart')) {
      throw FileTypeException('File is not a Dart file: $filePath');
    }
    final context = collection.contextFor(filePath);
    final result = await context.currentSession.getResolvedUnit(filePath);
    if (result is ResolvedUnitResult) {
      final originalContent = file.readAsStringSync();
      final String newContent;
      if (mode == InjectionMode.remove) {
        newContent = _removeInjections(originalContent, result, targets);
      } else {
        newContent = _getInjectionsContent(
          content: originalContent,
          result: result,
          targets: targets,
        );
      }
      if (newContent != originalContent) {
        file.writeAsStringSync(newContent);
      }
    }
  }

  /// Replaces `extends State<T>` with `extends SpmState<T>` and inserts the
  /// `instanceId` getter for each target State class. Adds the spm_state import.
  ///
  String _getInjectionsContent({
    required String content,
    required ResolvedUnitResult result,
    required List<JsonRecord> targets,
  }) {
    final classNodes = _resolveTargetClasses(result, targets);

    // Process from highest offset to lowest so prior insertions don't shift
    // the offsets we rely on for later classes.
    classNodes.sort((a, b) => b.$1.offset.compareTo(a.$1.offset));

    bool modified = false;

    for (final (classNode, target) in classNodes) {
      final extendsClause = classNode.extendsClause;
      if (extendsClause == null) continue;

      final superclass = extendsClause.superclass;
      if (superclass.name.lexeme != 'State') continue;

      final id = target['instanceId'] as String;

      final classBody = classNode.body;
      if (classBody is! BlockClassBody) continue;

      // Insert instanceId getter right after `{` (higher offset — do first).
      final insertOffset = classBody.leftBracket.end;
      final getterText = '\n  @override\n  String get instanceId => \'$id\';\n';
      content = content.replaceRange(insertOffset, insertOffset, getterText);

      // Replace the `State` name with `SpmState` in the extends clause
      //    (lower offset — unaffected by the insertion above).
      content = content.replaceRange(
        superclass.name.offset,
        superclass.name.end,
        AppConstants.spmStateClassName,
      );

      modified = true;
    }

    if (modified && !content.contains(AppConstants.spmStateImportLine)) {
      content = '${AppConstants.spmStateImportLine}\n$content';
    }

    return content;
  }

  /// Reverts `extends SpmState<T>` back to `extends State<T>` and removes the
  /// injected `instanceId` getter. Removes the spm_state import.
  ///
  String _removeInjections(
    String content,
    ResolvedUnitResult result,
    List<JsonRecord> targets,
  ) {
    final classNodes = _resolveTargetClasses(
      result,
      targets,
      requireSpmState: false,
    );

    classNodes.sort((a, b) => b.$1.offset.compareTo(a.$1.offset));

    bool modified = false;

    for (final (classNode, _) in classNodes) {
      final extendsClause = classNode.extendsClause;
      if (extendsClause == null) continue;

      final superclass = extendsClause.superclass;
      if (superclass.name.lexeme != AppConstants.spmStateClassName) continue;

      final classBody = classNode.body;
      if (classBody is! BlockClassBody) continue;

      // Find the instanceId getter among the class members.
      MethodDeclaration? instanceIdGetter;
      for (final member in classBody.members) {
        if (member is MethodDeclaration &&
            member.isGetter &&
            member.name.lexeme == 'instanceId') {
          instanceIdGetter = member;
          break;
        }
      }

      // Remove the instanceId getter (higher offset — do first).
      if (instanceIdGetter != null) {
        final removeStart = classBody.leftBracket.end;
        final removeEnd = min(instanceIdGetter.end + 1, content.length);
        content = content.replaceRange(removeStart, removeEnd, '');
      }

      // Replace `SpmState` with `State` in the extends clause
      //    (lower offset — unaffected by the removal above).
      content = content.replaceRange(
        superclass.name.offset,
        superclass.name.end,
        'State',
      );

      modified = true;
    }

    if (modified) {
      content = content.replaceFirst(
        '${AppConstants.spmStateImportLine}\n',
        '',
      );
    }

    return content;
  }

  /// Resolves each target record to its [ClassDeclaration] in the AST.
  /// Throws [StateClassNotFoundException] if a class cannot be found.
  ///
  List<(ClassDeclaration, JsonRecord)> _resolveTargetClasses(
    ResolvedUnitResult result,
    List<JsonRecord> targets, {
    bool requireSpmState = false,
  }) {
    final pairs = <(ClassDeclaration, JsonRecord)>[];

    for (final target in targets) {
      // `stateClassName` is the pre-rebuild-scope name of the same column.
      final className =
          (target['scopeName'] ?? target['stateClassName']) as String;
      final visitor = StateClassFinderVisitor(className);
      result.unit.accept(visitor);

      if (visitor.match == null) {
        throw StateClassNotFoundException(
          'No class named "$className" found in ${result.path}',
        );
      }

      pairs.add((visitor.match!, target));
    }

    return pairs;
  }
}
