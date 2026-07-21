import '../../domain/entities/analysis_result_entity.dart';
import '../data_sources/sets/state_class_instance_set.dart';
import '../data_sources/sets/tree_features_set.dart';

class AnalysisResultModel extends AnalysisResultEntity {
  AnalysisResultModel({
    required super.instanceId,
    required super.filePath,
    required super.stateClassName,
    required super.treeNonConstWidgetCount,
    required super.treeMaxWidgetNestingDepth,
    required super.treeListRenderingStrategy,
    required super.rootBuildReturnsConstWidget,
    required super.treeConstWidgetCount,
    required super.helperReferenceCount,
    required super.usesLayoutDependentBuilder,
    required super.treeCyclomaticComplexity,
    required super.treeIterationCount,
    required super.treeMaxIterationNestingDepth,
    required super.iterationWidgetCount,
    required super.valueObjectAllocCount,
    required super.helperWidgetCount,
    required super.helperMaxWidgetNestingDepth,
  });

  factory AnalysisResultModel.fromEntity(AnalysisResultEntity entity) {
    return AnalysisResultModel(
      instanceId: entity.instanceId,
      filePath: entity.filePath,
      stateClassName: entity.stateClassName,
      treeNonConstWidgetCount: entity.treeNonConstWidgetCount,
      treeMaxWidgetNestingDepth: entity.treeMaxWidgetNestingDepth,
      treeListRenderingStrategy: entity.treeListRenderingStrategy,
      rootBuildReturnsConstWidget: entity.rootBuildReturnsConstWidget,
      treeConstWidgetCount: entity.treeConstWidgetCount,
      helperReferenceCount: entity.helperReferenceCount,
      usesLayoutDependentBuilder: entity.usesLayoutDependentBuilder,
      treeCyclomaticComplexity: entity.treeCyclomaticComplexity,
      treeIterationCount: entity.treeIterationCount,
      treeMaxIterationNestingDepth: entity.treeMaxIterationNestingDepth,
      iterationWidgetCount: entity.iterationWidgetCount,
      valueObjectAllocCount: entity.valueObjectAllocCount,
      helperWidgetCount: entity.helperWidgetCount,
      helperMaxWidgetNestingDepth: entity.helperMaxWidgetNestingDepth,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'instanceId': instanceId,
      'filePath': filePath,
      'stateClassName': stateClassName,
      'treeNonConstWidgetCount': treeNonConstWidgetCount,
      'treeMaxWidgetNestingDepth': treeMaxWidgetNestingDepth,
      'treeListRenderingStrategy': treeListRenderingStrategy,
      'rootBuildReturnsConstWidget': rootBuildReturnsConstWidget.toInt(),
      'treeConstWidgetCount': treeConstWidgetCount,
      'helperReferenceCount': helperReferenceCount,
      'usesLayoutDependentBuilder': usesLayoutDependentBuilder.toInt(),
      'treeCyclomaticComplexity': treeCyclomaticComplexity,
      'treeIterationCount': treeIterationCount,
      'treeMaxIterationNestingDepth': treeMaxIterationNestingDepth,
      'iterationWidgetCount': iterationWidgetCount,
      'valueObjectAllocCount': valueObjectAllocCount,
      'helperWidgetCount': helperWidgetCount,
      'helperMaxWidgetNestingDepth': helperMaxWidgetNestingDepth,
    };
  }

  factory AnalysisResultModel.fromTreeFeatures({
    required TreeFeaturesSet treeFeatures,
    required StateClassInstance state,
    required String filePath,
  }) {
    return AnalysisResultModel(
      instanceId: state.instanceId,
      filePath: filePath,
      stateClassName: state.stateClassName,
      treeNonConstWidgetCount: treeFeatures.treeNonConstWidgetCount,
      treeMaxWidgetNestingDepth: treeFeatures.treeMaxWidgetNestingDepth,
      treeListRenderingStrategy: treeFeatures.treeListRenderingStrategy,
      rootBuildReturnsConstWidget: treeFeatures.rootBuildReturnsConstWidget,
      treeConstWidgetCount: treeFeatures.treeConstWidgetCount,
      helperReferenceCount: treeFeatures.helperReferenceCount,
      usesLayoutDependentBuilder: treeFeatures.usesLayoutDependentBuilder,
      treeCyclomaticComplexity: treeFeatures.treeCyclomaticComplexity,
      treeIterationCount: treeFeatures.treeIterationCount,
      treeMaxIterationNestingDepth: treeFeatures.treeMaxIterationNestingDepth,
      iterationWidgetCount: treeFeatures.iterationWidgetCount,
      valueObjectAllocCount: treeFeatures.valueObjectAllocCount,
      helperWidgetCount: treeFeatures.helperWidgetCount,
      helperMaxWidgetNestingDepth: treeFeatures.helperMaxWidgetNestingDepth,
    );
  }
}

extension BoolToIntExtension on bool {
  int toInt() => this ? 1 : 0;
}
