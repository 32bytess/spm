import 'package:spm/core/types.dart';
import 'package:spm/features/injection/domain/entities/injection_mode.dart';

abstract class InjectionRepository {
  AsyncVoidResult inject(String repoRoot, String jsonPath, InjectionMode mode);
}
