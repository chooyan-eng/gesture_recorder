import 'dart:convert';
import 'dart:developer' as devtools;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'recorded_data.dart';
import 'serialization.dart';

/// The state of the gesture recorder.
enum RecordState { none, recording, playing }

/// A widget that records all the gesture events happening during recording.
///
/// [GestureRecorder] captures all the gesture events reported by the platform and
/// expose [RecordedGestureData] as a result of recording.
///
/// [GestureRecorder] must be placed at the root (or almost root) of the widget tree
/// so that its descendant can call [start], [stop], and [replay] methods
/// by finding [GestureRecorder] as the result of traversing [BuildContext].
///
/// Once the value of [RecordedGestureData] is obtained by [stop] method,
/// you can replay the recorded events by calling [replay] method with passing the value as-is.
class GestureRecorder extends StatefulWidget {
  const GestureRecorder({super.key, required this.child});

  /// The child widget.
  final Widget child;

  /// Returns the current state of the gesture recorder.
  /// Once the state changes, the dependent widgets are rebuilt.
  static RecordState stateOf(BuildContext context) {
    final state =
        context.dependOnInheritedWidgetOfExactType<_GestureRecorderScope>();
    assert(
      state != null,
      'GestureRecorder must be used within a GestureRecorder',
    );
    return state!.state;
  }

  static _GestureRecorderState _of(BuildContext context) {
    final state = context.findAncestorStateOfType<_GestureRecorderState>();
    assert(
      state != null,
      'GestureRecorder must be used within a GestureRecorder',
    );
    return state!;
  }

  /// Starts recording gesture events.
  static void start(BuildContext context) async {
    _of(context)._start();
  }

  /// Stops recording gesture events and returns the recorded event data.
  static Future<RecordedGestureData> stop(BuildContext context) async {
    return _of(context)._stop();
  }

  /// Replays the recorded gesture events.
  /// [recordedData] is typically obtained by [stop] method.
  static Future<void> replay(
    BuildContext context,
    RecordedGestureData recordedData,
  ) async {
    return _of(context)._replay(recordedData);
  }

  /// Creates [_GestureRecorderState] instance for Flutter framework.
  @override
  State<GestureRecorder> createState() => _GestureRecorderState();
}

/// The state of the gesture recorder.
/// This operates a recording and replaying of gesture events.
class _GestureRecorderState extends State<GestureRecorder> {
  final List<RecordedEvent> _events = [];
  Size? _screenSize;
  DateTime? _previousTimestamp;
  void Function()? _restoreFunc;
  RecordState _state = RecordState.none;
  static const _devtoolsServiceMethod = 'ext.gesture_recorder.pushRecordedData';
  static const _devtoolsServiceReplay =
      'ext.gesture_recorder.replayRecordedData';
  static const _devtoolsServiceStart = 'ext.gesture_recorder.startRecordedData';
  static const _devtoolsServiceStop = 'ext.gesture_recorder.stopRecordedData';

  void _start() {
    final dispatcher = PlatformDispatcher.instance.onPointerDataPacket;
    if (dispatcher != null) {
      // Capture screen size
      final view = PlatformDispatcher.instance.views.firstOrNull;
      if (view != null) {
        _screenSize = view.physicalSize;
      } else {
        // Fallback to a default size if view is not available
        _screenSize = const Size(0, 0);
      }

      setState(() {
        _state = RecordState.recording;
      });

      _previousTimestamp = null;

      void wrappedFunc(PointerDataPacket packet) {
        final now = DateTime.now();
        final recordedPacket =
            RecordedPointerDataPacket.fromPointerDataPacket(packet);

        Duration timeSincePrevious;
        if (_previousTimestamp == null) {
          timeSincePrevious = Duration.zero;
        } else {
          timeSincePrevious = now.difference(_previousTimestamp!);
        }

        _events.add((
          packet: recordedPacket,
          timeSincePrevious: timeSincePrevious,
        ));

        _previousTimestamp = now;
        dispatcher(packet);
      }

      PlatformDispatcher.instance.onPointerDataPacket = wrappedFunc;
      _restoreFunc =
          () => PlatformDispatcher.instance.onPointerDataPacket = dispatcher;
    }
  }

  RecordedGestureData _stop() {
    setState(() {
      _state = RecordState.none;
    });

    if (_restoreFunc != null) {
      _restoreFunc!();
      _restoreFunc = null;
    }

    final screenSize = _screenSize ?? const Size(0, 0);
    final result = RecordedGestureData(
      events: [..._events],
      screenSize: screenSize,
    );
    _pushRecordedDataToDevTools(result);

    _events.clear();
    _screenSize = null;
    _previousTimestamp = null;

    return result;
  }

  void _pushRecordedDataToDevTools(RecordedGestureData data) {
    final serialized = data.toJson();
    devtools.postEvent(_devtoolsServiceMethod, {'value': serialized});
  }

  Future<void> _replay(RecordedGestureData recordedData) async {
    final dispatcher = PlatformDispatcher.instance.onPointerDataPacket;
    if (dispatcher == null) {
      return;
    }

    setState(() {
      _state = RecordState.playing;
    });

    for (final event in recordedData.events) {
      if (event.timeSincePrevious.inMicroseconds > 0) {
        await Future.delayed(event.timeSincePrevious);
      }
      dispatcher(event.packet.toPointerDataPacket());
    }

    setState(() {
      _state = RecordState.none;
    });
  }

  @override
  void initState() {
    super.initState();
    devtools.registerExtension(_devtoolsServiceReplay,
        (method, parameters) async {
      final value = parameters['data'];

      if (value == null) {
        return devtools.ServiceExtensionResponse.result(jsonEncode({}));
      }

      _replay(value.toData());
      // Respond with a JSON message, in this case no need, so I left it empty.
      return devtools.ServiceExtensionResponse.result(jsonEncode({}));
    });

    devtools.registerExtension(_devtoolsServiceStart,
        (method, parameters) async {
      _start();
      // Respond with a JSON message, in this case no need, so I left it empty.
      return devtools.ServiceExtensionResponse.result(jsonEncode({}));
    });

    devtools.registerExtension(_devtoolsServiceStop,
        (method, parameters) async {
      _stop();
      // Respond with a JSON message, in this case no need, so I left it empty.
      return devtools.ServiceExtensionResponse.result(jsonEncode({}));
    });
  }

  @override
  Widget build(BuildContext context) {
    return _GestureRecorderScope(state: _state, child: widget.child);
  }
}

/// An [InheritedWidget] that provides the current state of the gesture recorder.
class _GestureRecorderScope extends InheritedWidget {
  const _GestureRecorderScope({required super.child, required this.state});

  final RecordState state;

  @override
  bool updateShouldNotify(_GestureRecorderScope oldWidget) {
    return state != oldWidget.state;
  }
}
