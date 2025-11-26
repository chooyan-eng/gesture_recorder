import 'dart:async';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/rendering.dart';
import 'package:vm_service/vm_service.dart';

/// Helper class to communicate with the device.
class DeviceCommunicator {
  StreamSubscription? _extensionEventSubscription;
  late final VmService _vmService;
  static const _serviceMethod = 'ext.gesture_recorder.pushRecordedData';
  static const _devtoolsServiceStart = 'ext.gesture_recorder.startRecordedData';
  static const _devtoolsServiceStop = 'ext.gesture_recorder.stopRecordedData';
  static const _devtoolsServiceReplay =
      'ext.gesture_recorder.replayRecordedData';

  /// Initialize the device communicator.
  Future<void> init({required VoidCallback onConnected}) async {
    _vmService = await serviceManager.onServiceAvailable;

    serviceManager.connectedState.addListener(() {
      if (serviceManager.connectedState.value.connected) {
        onConnected();
      }
    });
  }

  /// Whether the device is connected.
  bool get isConnected => serviceManager.connectedState.value.connected;

  /// Listen to the gesture data from the device.
  void listenGestureData(ValueChanged<String> onData) {
    // Once we have the vmService, listen to the onExtensionEvent.
    _extensionEventSubscription = _vmService.onExtensionEvent.listen((event) {
      // Check whether the event is the event you need.
      final isUpdateEvent = event.extensionKind == _serviceMethod;
      if (!isUpdateEvent) return;

      // Parse the data you need.
      final data = event.extensionData!.data['value'] as String;
      onData(data);
    });
  }

  /// Replay the given gesture [data] on the device.
  Future<void> replayGestureOnDevice(String data) async {
    await serviceManager.callServiceExtensionOnMainIsolate(
      _devtoolsServiceReplay,
      args: {'data': data},
    );
  }

  /// Start the gesture recording on the device.
  Future<void> startGestureOnDevice() async {
    await serviceManager.callServiceExtensionOnMainIsolate(
      _devtoolsServiceStart,
    );
  }

  /// Stop the gesture recording on the device.
  Future<void> stopGestureOnDevice() async {
    await serviceManager.callServiceExtensionOnMainIsolate(
      _devtoolsServiceStop,
    );
  }

  /// Dispose the device communicator.
  void dispose() {
    _extensionEventSubscription?.cancel();
  }
}
