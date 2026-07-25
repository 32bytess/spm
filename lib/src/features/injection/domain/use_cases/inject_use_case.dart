import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/injection/domain/entities/injection_mode.dart';
import 'package:spm/src/features/injection/domain/repositories/injection_repository.dart';

class InjectUseCase {
  final InjectionRepository repository;

  InjectUseCase(this.repository);

  AsyncVoidResult call(String repoRoot, String jsonPath, InjectionMode mode) =>
      repository.inject(repoRoot, jsonPath, mode);
}
