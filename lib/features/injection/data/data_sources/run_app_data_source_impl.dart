import 'dart:async';
import 'dart:io';

import 'package:spm/core/errors/exceptions.dart';
import 'package:spm/core/types.dart';
import 'package:spm/features/injection/data/data_sources/run_app_data_source.dart';
import 'package:spm/features/injection/domain/entities/run_app_event.dart';
import 'helpers/flutter_process_runner.dart';
import 'helpers/profiler_log_writer.dart';
import 'helpers/vm_service_connector.dart';

class RunAppDataSourceImpl implements RunAppDataSource {
  final VmServiceConnector Function() _connectorFactory;
  final ProfilerLogWriter Function(String path) _writerFactory;

  RunAppDataSourceImpl({
    VmServiceConnector Function()? connectorFactory,
    ProfilerLogWriter Function(String path)? writerFactory,
  }) : _connectorFactory = connectorFactory ?? VmServiceConnector.new,
       _writerFactory = writerFactory ?? ProfilerLogWriter.new;

  @override
  Stream<RunAppEvent> runApp(
    String repoRoot,
    List<String> flutterArgs, {
    String? outputPath,
  }) {
    final controller = StreamController<RunAppEvent>();
    _run(controller, repoRoot, flutterArgs, outputPath)
        .catchError((Object e, StackTrace st) {
          final ex = e is RunAppException
              ? e
              : RunAppException(e.toString(), st.toString());
          controller.addError(ex);
        })
        .whenComplete(controller.close);
    return controller.stream;
  }

  AsyncVoid _run(
    StreamController<RunAppEvent> controller,
    String repoRoot,
    List<String> flutterArgs,
    String? outputPath,
  ) async {
    final runner = await FlutterProcessRunner.start(repoRoot, flutterArgs);
    final logWriter = outputPath != null ? _writerFactory(outputPath) : null;
    final vmConnector = _connectorFactory();

    try {
      var vmServiceConnected = false;
      if (logWriter != null) {
        final wsUri = await runner.vmUri;
        if (wsUri != null) {
          stderr.writeln('[spm]: Detected VM service URI: $wsUri');
          vmServiceConnected = await vmConnector.connect(
            wsUri,
            logWriter,
            onProfilerData: (data) => controller.add(ProfilerDataEvent(data)),
          );
        }
        controller.add(VmServiceConnectionEvent(connected: vmServiceConnected));
      }

      final exitCode = await runner.exitCode;
      await runner.ioFlush;

      controller.add(
        RunCompletedEvent(
          eventCount: logWriter?.eventCount ?? 0,
          vmServiceConnected: vmServiceConnected,
          outputPath: outputPath,
          exitCode: exitCode,
        ),
      );
    } finally {
      await runner.dispose();
      await vmConnector.dispose();
      await logWriter?.close();
    }
  }
}
