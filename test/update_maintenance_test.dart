import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/features/updates/data/app_updates.dart';
import 'package:so_account/features/updates/presentation/update_controller.dart';

class _PendingTransport implements UpdateTransport {
  Completer<UpdateResponse>? pending;
  int calls = 0;
  bool cancelled = false;
  @override
  Future<UpdateResponse> get(Uri uri) {
    calls++;
    pending = Completer<UpdateResponse>();
    return pending!.future;
  }

  @override
  void cancel() => cancelled = true;
}

class _Updates extends UpdateController {
  _Updates(UpdateTransport transport)
    : super(service: AppUpdateService(transport)) {
    supported = android = true;
    currentBuild = 19;
  }
  @override
  Future<void> initialize() async {}
}

void main() {
  test('data cleanup waits for cancelled update work and blocks new checks until released', () async {
    final transport = _PendingTransport();
    final controller = _Updates(transport);
    addTearDown(controller.dispose);
    final check = controller.check(manual: true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.checking, isTrue);
    var paused = false;
    final pause = controller.pauseForDataMaintenance().then(
      (_) => paused = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.cancelled, isTrue);
    expect(paused, isFalse);
    transport.pending!.completeError(const SocketException('cancelled'));
    await check;
    await pause;
    expect(controller.busy, isFalse);
    await controller.check(manual: true);
    expect(transport.calls, 1);
    controller.finishDataMaintenance(resetSettings: true);
    final next = controller.check(manual: true);
    await Future<void>.delayed(Duration.zero);
    expect(transport.calls, 2);
    transport.pending!.complete(UpdateResponse(404, const Stream.empty()));
    await next;
    expect(controller.message, '当前已是最新正式版本');
  });
}
