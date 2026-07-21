import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:spm/core/errors/failures.dart';
import 'package:spm/core/types.dart';
import 'package:spm/features/injection/domain/entities/injection_mode.dart';
import 'package:spm/features/injection/domain/entities/run_app_event.dart';
import 'package:spm/features/injection/domain/entities/run_with_injection_event.dart';
import 'package:spm/features/injection/domain/entities/run_with_injection_step.dart';
import 'package:spm/features/injection/domain/repositories/flutter_analyze_repository.dart';
import 'package:spm/features/injection/domain/repositories/injection_repository.dart';
import 'package:spm/features/injection/domain/repositories/run_app_repository.dart';

class RunWithInjectionUseCase {
  final FlutterAnalyzeRepository flutterAnalyzeRepository;
  final InjectionRepository injectionRepository;
  final RunAppRepository runAppRepository;

  RunWithInjectionUseCase(
    this.flutterAnalyzeRepository,
    this.injectionRepository,
    this.runAppRepository,
  );

  /// Runs the full pipeline and emits progress + app events on a single stream.
  ///
  /// The stream emits [StepChangedEvent]s at each phase transition and
  /// [AppRunEvent]s while the Flutter process is running. On failure the stream
  /// emits a [Left] and closes; on success it closes after the app exits and
  /// injection is reversed.
  RunWithInjectionEventStream call(
    String repoRoot,
    String jsonPath,
    InjectionMode mode,
    List<String> flutterArgs, {
    String? outputPath,
    bool skipInjection = false,
  }) {
    final controller = StreamController<Result<RunWithInjectionEvent>>();
    _execute(
      controller,
      repoRoot,
      jsonPath,
      mode,
      flutterArgs,
      outputPath,
      skipInjection,
    );
    return controller.stream;
  }

  AsyncVoid _execute(
    StreamController<Result<RunWithInjectionEvent>> controller,
    String repoRoot,
    String jsonPath,
    InjectionMode mode,
    List<String> flutterArgs,
    String? outputPath,
    bool skipInjection,
  ) async {
    try {
      // flutter analyze.
      controller.add(Right(StepChangedEvent(RunWithInjectionStep.analyzing)));
      final analyzeResult = await flutterAnalyzeRepository.analyze(repoRoot);
      final analyzeFailure = analyzeResult.fold<Failure?>(
        (f) => f,
        (_) => null,
      );
      if (analyzeFailure != null) {
        controller.add(Left(analyzeFailure));
        return;
      }

      if (!skipInjection) {
        controller.add(Right(StepChangedEvent(RunWithInjectionStep.injecting)));
        final injectResult = await injectionRepository.inject(
          repoRoot,
          jsonPath,
          mode,
        );
        final injectFailure = injectResult.fold<Failure?>(
          (f) => f,
          (_) => null,
        );
        if (injectFailure != null) {
          controller.add(Left(injectFailure));
          return;
        }
      }

      // start the app.
      controller.add(Right(StepChangedEvent(RunWithInjectionStep.running)));
      final runResult = await runAppRepository.runApp(
        repoRoot,
        flutterArgs,
        outputPath: outputPath,
      );
      final runFailure = runResult.fold<Failure?>((f) => f, (_) => null);
      if (runFailure != null) {
        if (!skipInjection) {
          // App failed to start - revert and surface the failure.
          controller.add(
            Right(StepChangedEvent(RunWithInjectionStep.reverting)),
          );
          final removeResult = await injectionRepository.inject(
            repoRoot,
            jsonPath,
            InjectionMode.remove,
          );
          final removeFailure = removeResult.fold<Failure?>(
            (f) => f,
            (_) => null,
          );
          controller.add(
            removeFailure != null
                ? Left(CompoundFailure([runFailure, removeFailure]))
                : Left(runFailure),
          );
        } else {
          controller.add(Left(runFailure));
        }
        return;
      }

      // forward app events.
      final eventStream = runResult.fold<Stream<RunAppEvent>>(
        (_) => const Stream.empty(),
        (s) => s,
      );
      await for (final event in eventStream) {
        controller.add(Right(AppRunEvent(event)));
      }

      if (!skipInjection) {
        controller.add(Right(StepChangedEvent(RunWithInjectionStep.reverting)));
        await injectionRepository.inject(
          repoRoot,
          jsonPath,
          InjectionMode.remove,
        );
      }
    } catch (e, st) {
      controller.addError(e, st);
    } finally {
      await controller.close();
    }
  }
}
