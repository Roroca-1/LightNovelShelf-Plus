import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// 后台计算 worker：在真实运行期复用单个长驻 isolate，省去高频
/// `Isolate.run` 反复创建/销毁的开销；测试环境退回 `Isolate.run`，
/// 避免常驻 ReceivePort 影响测试进程退出。
class BackgroundWorker {
  const BackgroundWorker._();

  static final bool _inTest = Platform.environment.containsKey('FLUTTER_TEST');

  static _PersistentWorker? _worker;
  static Future<_PersistentWorker>? _starting;

  static Future<R> run<R>(FutureOr<R> Function() computation) {
    if (_inTest) return Isolate.run(computation);
    return _dispatch(computation);
  }

  static Future<R> _dispatch<R>(FutureOr<R> Function() computation) async {
    final worker = await _ensureWorker();
    try {
      return await worker.execute<R>(computation);
    } on _WorkerCrashedException {
      _worker = null;
      final fresh = await _ensureWorker();
      return fresh.execute<R>(computation);
    }
  }

  static Future<_PersistentWorker> _ensureWorker() {
    final active = _worker;
    if (active != null && !active.closed) {
      return Future<_PersistentWorker>.value(active);
    }
    return _starting ??= _PersistentWorker.spawn()
        .then((worker) {
          _worker = worker;
          return worker;
        })
        .whenComplete(() => _starting = null);
  }
}

class _WorkerCrashedException implements Exception {
  const _WorkerCrashedException();
}

class _PersistentWorker {
  _PersistentWorker._(this._isolate, this._sendPort, this._responses) {
    _responses.listen(
      _onMessage,
      onDone: _onClosed,
    );
  }

  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _responses;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  int _nextId = 0;
  bool closed = false;

  static Future<_PersistentWorker> spawn() async {
    final handshake = ReceivePort();
    final exitPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerEntry,
      handshake.sendPort,
      onExit: exitPort.sendPort,
      debugName: 'LightNovelShelfWorker',
    );
    final sendPort = await handshake.first as SendPort;
    handshake.close();

    final responses = ReceivePort();
    sendPort.send(responses.sendPort);
    final worker = _PersistentWorker._(isolate, sendPort, responses);
    exitPort.first.then((_) {
      exitPort.close();
      worker._onClosed();
    });
    return worker;
  }

  Future<R> execute<R>(FutureOr<R> Function() computation) {
    if (closed) {
      return Future<R>.error(const _WorkerCrashedException());
    }
    final id = ++_nextId;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _sendPort.send((id, computation));
    return completer.future.then((value) => value as R);
  }

  void _onMessage(Object? message) {
    if (message is! (int, bool, Object?, StackTrace?)) return;
    final (id, ok, payload, stack) = message;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (ok) {
      completer.complete(payload);
    } else {
      completer.completeError(payload ?? StateError('Worker error'), stack);
    }
  }

  void _onClosed() {
    if (closed) return;
    closed = true;
    _responses.close();
    _isolate.kill(priority: Isolate.immediate);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(const _WorkerCrashedException());
      }
    }
    _pending.clear();
  }

  static void _workerEntry(SendPort initPort) {
    final inbox = ReceivePort();
    initPort.send(inbox.sendPort);
    SendPort? replyPort;
    inbox.listen((message) async {
      if (message is SendPort) {
        replyPort = message;
        return;
      }
      if (message is! (int, FutureOr<Object?> Function())) return;
      final (id, task) = message;
      final out = replyPort;
      if (out == null) return;
      try {
        final result = await task();
        out.send((id, true, result, null));
      } catch (error, stackTrace) {
        out.send((id, false, error, stackTrace));
      }
    });
  }
}
