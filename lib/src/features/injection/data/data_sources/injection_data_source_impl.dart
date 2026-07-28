import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:spm/src/core/constants/app_constants.dart';
import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/injection/data/data_sources/helpers/injection_helper.dart';
import 'package:spm/src/features/injection/domain/entities/injection_mode.dart';

import 'injection_data_source.dart';

class InjectionDataSourceImpl implements InjectionDataSource {
  final InjectionHelper _injectionHelper;

  InjectionDataSourceImpl({InjectionHelper? injectionHelper})
    : _injectionHelper = injectionHelper ?? InjectionHelper();

  @override
  AsyncVoid inject(String repoRoot, String jsonPath, InjectionMode mode) async {
    final collection = AnalysisContextCollection(
      includedPaths: [repoRoot],
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );

    String? currentFilePath;
    var currentInjections = <JsonRecord>[];

    AsyncVoid applyInjection() async => await _injectionHelper.applyInjection(
      collection: collection,
      filePath: currentFilePath!,
      targets: currentInjections,
      mode: mode,
    );
    await for (final injection in _injectionHelper.readJsonlStream(jsonPath)) {
      // `analyze` reports every rebuild scope, but only a State subclass can
      // be given an SpmState base class. Rows without a scopeType come from
      // older JSONL files, which only ever contained State scopes.
      final scopeType = injection['scopeType'] as String?;
      if (scopeType != null && scopeType != AppConstants.stateScopeType) {
        continue;
      }

      final filePath = p.join(repoRoot, injection['filePath'] as String);

      if (currentFilePath != null && currentFilePath != filePath) {
        await applyInjection();
        currentInjections = [];
      }

      currentFilePath = filePath;
      currentInjections.add(injection);
    }

    if (currentFilePath != null) {
      await applyInjection();
    }
  }
}
