import 'package:spm/src/features/injection/domain/entities/run_app_event.dart';
import 'package:spm/src/features/injection/domain/entities/run_with_injection_step.dart';
import 'package:spm/src/features/injection/domain/use_cases/run_with_injection_use_case.dart';

/// Event type emitted by [RunWithInjectionUseCase].
sealed class RunWithInjectionEvent {}

/// Emitted at the start of each pipeline phase.
class StepChangedEvent extends RunWithInjectionEvent {
  final RunWithInjectionStep step;
  StepChangedEvent(this.step);
}

/// Wraps a [RunAppEvent] emitted by the running Flutter process.
class AppRunEvent extends RunWithInjectionEvent {
  final RunAppEvent event;
  AppRunEvent(this.event);
}
