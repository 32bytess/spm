import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/injection/domain/entities/injection_mode.dart';

abstract class InjectionRepository {
  AsyncVoidResult inject(String repoRoot, String jsonPath, InjectionMode mode);
}
