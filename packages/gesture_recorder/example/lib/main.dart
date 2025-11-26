import 'dart:developer';

import 'package:example/shared_preferences.dart' as persistence;
import 'package:flutter/material.dart';
import 'package:gesture_recorder/gesture_recorder.dart';

void main() {
  runApp(GestureRecorder(child: const MyApp()));

  // for more detailed example
  // runApp(GestureRecorder(child: const DrawingCanvasExample()));
  // runApp(GestureRecorder(child: const ListDetailExample()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CounterApp();
  }
}

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _counter = 0;
  RecordedGestureData? _recordedData;

  Future<void> _toggleRecordState(RecordState recordState) async {
    switch (recordState) {
      case RecordState.none:
        if (_recordedData != null) {
          await GestureRecorder.replay(context, _recordedData!);
        } else {
          GestureRecorder.start(context);
        }
      case RecordState.recording:
        final data = await GestureRecorder.stop(context);
        setState(() {
          _recordedData = data;
        });
      case RecordState.playing:
        // do nothing
        break;
    }
  }

  Future<void> _saveData() async {
    if (_recordedData == null) return;
    final success = await persistence.saveRecordedData(_recordedData!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(success ? 'Data saved successfully' : 'Failed to save data'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _restoreData() async {
    final data = await persistence.fetchRecordedData();
    if (mounted) {
      if (data != null) {
        setState(() {
          _recordedData = data;
        });
        final serialized = data.toJson();
        postEvent(
            'ext.gesture_recorder.pushRecordedData', {'value': serialized});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No saved data found'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordState = GestureRecorder.stateOf(context);
    final hasHistory = _recordedData != null;
    return MaterialApp(
      title: 'Flutter Demo',
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('You have pushed the button this many times:'),
              Text(
                '$_counter',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 48),
              Text(
                recordState.recordStatusText(hasHistory),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: recordState.recordColor(hasHistory),
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: recordState == RecordState.playing
                    ? null
                    : () => _toggleRecordState(recordState),
                icon: Icon(recordState.recordIcon(hasHistory)),
                label: Text(
                  recordState == RecordState.recording
                      ? 'Stop Recording'
                      : hasHistory
                          ? 'Replay'
                          : 'Start Recording',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: recordState.recordColor(hasHistory),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: (hasHistory &&
                            recordState != RecordState.recording &&
                            recordState != RecordState.playing)
                        ? _saveData
                        : null,
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: (recordState != RecordState.recording &&
                            recordState != RecordState.playing)
                        ? _restoreData
                        : null,
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasHistory) ...[
                const SizedBox(height: 16),
                Text(
                  'Events: ${_recordedData!.events.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Screen size: ${_recordedData!.screenSize.width.toStringAsFixed(0)} x ${_recordedData!.screenSize.height.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => setState(() => _counter++),
          tooltip: 'Increment',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

extension on RecordState {
  IconData recordIcon(bool hasHistory) => switch (this) {
        RecordState.none =>
          hasHistory ? Icons.play_arrow : Icons.fiber_manual_record,
        RecordState.recording => Icons.stop,
        RecordState.playing => Icons.play_arrow,
      };

  Color recordColor(bool hasHistory) => switch (this) {
        RecordState.none => hasHistory ? Colors.green : Colors.red,
        RecordState.recording => Colors.grey,
        RecordState.playing => Colors.blue,
      };

  String recordStatusText(bool hasHistory) => switch (this) {
        RecordState.none => hasHistory ? 'Ready to replay' : 'Ready to record',
        RecordState.recording => 'Recording...',
        RecordState.playing => 'Playing...',
      };
}
