import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:spm/src/core/constants/app_constants.dart';
import 'package:spm/src/core/types.dart';

/// Launches a `flutter` subprocess and manages its I/O streams.
///
class FlutterProcessRunner {
  final Process _process;
  final StreamSubscription<List<int>> _stdinSub;
  final AsyncVoid _ioFlush;

  /// Resolves to the WebSocket-form Dart VM service URI once found in stdout,
  /// or `null` if the process exits without printing one.
  final Future<String?> vmUri;

  FlutterProcessRunner._({
    required Process process,
    required StreamSubscription<List<int>> stdinSub,
    required this.vmUri,
    required AsyncVoid ioFlush,
  }) : _process = process,
       _stdinSub = stdinSub,
       _ioFlush = ioFlush;

  static Future<FlutterProcessRunner> start(
    String repoRoot,
    List<String> args,
  ) async {
    final process = await Process.start(
      'flutter',
      args,
      workingDirectory: repoRoot,
    );

    final stdinSub = stdin.listen(
      (data) => process.stdin.add(data),
      onError: (_) => process.stdin.close(),
    );

    final vmUriCompleter = Completer<String?>();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    _listenAndScan(process.stdout, stdout, vmUriCompleter, stdoutDone);
    _listenAndScan(process.stderr, stderr, vmUriCompleter, stderrDone);

    return FlutterProcessRunner._(
      process: process,
      stdinSub: stdinSub,
      vmUri: vmUriCompleter.future,
      ioFlush: Future.wait([stdoutDone.future, stderrDone.future]),
    );
  }

  /// Completes with the exit code of the Flutter process.
  Future<int> get exitCode => _process.exitCode;

  /// Waits for stdout and stderr streams to finish flushing.
  AsyncVoid get ioFlush => _ioFlush;

  /// Cancels the stdin subscription.
  AsyncVoid dispose() => _stdinSub.cancel();

  // -- private helpers ----------------------

  /// Echoes [stream] to [sink] and watches the lines going by for the Dart VM
  /// service URI, completing [vmUriCompleter] with the first one seen.
  ///
  /// Both streams are scanned by one function on purpose. They used to have a
  /// listener each, and the copies drifted: the stdout one tracked "found it"
  /// in a local flag rather than asking the completer. Since the two share a
  /// completer, a URI printed to stderr first left that flag false, so stdout
  /// went on to complete an already-completed completer and throw out of a
  /// stream callback. Asking [vmUriCompleter] is the guard that cannot drift.
  static void _listenAndScan(
    Stream<List<int>> stream,
    IOSink sink,
    Completer<String?> vmUriCompleter,
    Completer<void> done,
  ) {
    var lineBuf = '';

    stream.listen(
      (bytes) {
        sink.add(bytes);

        if (vmUriCompleter.isCompleted) return;
        lineBuf += utf8.decode(bytes, allowMalformed: true);
        while (lineBuf.contains('\n')) {
          final idx = lineBuf.indexOf('\n');
          final line = lineBuf.substring(0, idx);
          lineBuf = lineBuf.substring(idx + 1);

          final match = _vmServiceUriPattern.firstMatch(line);
          if (match != null) {
            vmUriCompleter.complete(_toWsUri(match.group(1)!));
            break;
          }
        }
      },
      onDone: () {
        if (!vmUriCompleter.isCompleted) vmUriCompleter.complete(null);
        done.complete();
      },
      onError: (_) {
        if (!vmUriCompleter.isCompleted) vmUriCompleter.complete(null);
        done.complete();
      },
    );
  }

  /// Converts an HTTP/HTTPS URI to its WebSocket equivalent.
  static String _toWsUri(String httpUri) {
    var uri = httpUri.trim();
    if (uri.startsWith('https://')) {
      uri = 'wss://${uri.substring('https://'.length)}';
    } else if (uri.startsWith('http://')) {
      uri = 'ws://${uri.substring('http://'.length)}';
    }
    if (!uri.endsWith('/ws')) {
      uri = uri.endsWith('/') ? '${uri}ws' : '$uri/ws';
    }
    return uri;
  }

  static final _vmServiceUriPattern = RegExp(
    AppConstants.vmServiceUriRegExp,
    caseSensitive: false,
  );
}
