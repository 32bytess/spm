import 'dart:async';
import 'dart:io';

import 'package:spm/core/constants/app_constants.dart';
import 'package:spm/core/types.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:spm/features/injection/data/data_sources/helpers/profiler_log_writer.dart';

/// Manages the connection to the Dart VM service and subscribes to
/// profiler extension events (`ext.spm.profiler`) posted by
/// `developer.postEvent` in the running Flutter app.
///
class VmServiceConnector {
  VmService? _vmService;
  StreamSubscription<Event>? _extensionSub;

  bool get isConnected => _vmService != null;

  /// Connects to the Dart VM service at [wsUri] and starts listening for
  /// profiler extension events
  ///
  /// [onProfilerData] is called for each captured event, allowing the caller
  /// to also emit the data as a stream event.
  ///
  /// Returns `true` if the connection was established, `false` otherwise.
  Future<bool> connect(
    String wsUri,
    ProfilerLogWriter logWriter, {
    void Function(Map<String, dynamic> data)? onProfilerData,
  }) async {
    try {
      _vmService = await vmServiceConnectUri(wsUri);

      await _vmService!.streamListen(EventStreams.kExtension);
      _extensionSub = _vmService!.onExtensionEvent.listen((event) {
        if (event.extensionKind == AppConstants.vmServiceEventName &&
            event.extensionData != null) {
          final data = event.extensionData!.data;
          logWriter.write(data);
          onProfilerData?.call(data);
        }
      });

      return true;
    } catch (e) {
      stderr.writeln('[spm]: VM service connection error: $e');
      return false;
    }
  }

  /// Cancels the extension stream subscription and disposes the VM service.
  AsyncVoid dispose() async {
    await _extensionSub?.cancel();
    _extensionSub = null;
    await _vmService?.dispose();
    _vmService = null;
  }
}
