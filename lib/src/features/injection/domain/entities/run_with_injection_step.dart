import 'package:spm/src/features/injection/domain/use_cases/run_with_injection_use_case.dart';

/// Represents the current execution phase of [RunWithInjectionUseCase].
///
enum RunWithInjectionStep { analyzing, injecting, running, reverting }
