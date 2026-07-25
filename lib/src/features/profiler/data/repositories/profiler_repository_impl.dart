import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:spm/src/core/errors/exceptions.dart';
import 'package:spm/src/core/errors/failures.dart';
import 'package:spm/src/core/types.dart';
import 'package:spm/src/features/profiler/data/data_sources/profiler_data_source.dart';
import 'package:spm/src/features/profiler/domain/repositories/profiler_repository.dart';

class ProfilerRepositoryImpl implements ProfilerRepository {
  final ProfilerDataSource _dataSource;
  ProfilerRepositoryImpl(this._dataSource);
  @override
  AsyncVoidResult monitorDataFlow(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logic, {
    required BuildContext context,
  }) async {
    try {
      final data = await _dataSource.monitorDataFlow(
        instanceId,
        setStateFunc,
        logic,
        context: context,
      );
      return Right(data);
    } on InvalidModeException catch (e) {
      return Left(InvalidModeFailure(e.message));
    } on MonitoringAlreadyActiveException catch (e) {
      return Left(MonitoringAlreadyActiveFailure(e.message));
    } on DataflowMonitoringException catch (e) {
      return Left(DataflowMonitoringFailure(e.message));
    } catch (e) {
      return Left(UnknownFailure('An unknown error occurred: $e'));
    }
  }

  @override
  AsyncVoidResult monitorPerformance(
    String instanceId,
    Function(VoidCallback) setStateFunc,
    VoidCallback logicCallback,
  ) async {
    try {
      final data = await _dataSource.monitorPerformance(
        instanceId,
        setStateFunc,
        logicCallback,
      );
      return Right(data);
    } on InvalidModeException catch (e) {
      return Left(InvalidModeFailure(e.message));
    } on MonitoringAlreadyActiveException catch (e) {
      return Left(MonitoringAlreadyActiveFailure(e.message));
    } on PerformanceMonitoringException catch (e) {
      return Left(PerformanceMonitoringFailure(e.message));
    } catch (e) {
      return Left(UnknownFailure('An unknown error occurred: $e'));
    }
  }
}
