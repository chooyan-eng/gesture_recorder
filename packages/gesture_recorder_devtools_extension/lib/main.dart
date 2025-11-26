import 'dart:async';
import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'package:gesture_recorder_devtools_extension/device_communicator.dart';
import 'package:gesture_recorder_devtools_extension/gesture_inspector.dart';
import 'package:gesture_recorder_devtools_extension/saved_files_dialog.dart';

void main() {
  runApp(DevToolsExtension(child: const GestureRecorderExtension()));
}

class GestureRecorderExtension extends StatelessWidget {
  const GestureRecorderExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gesture Recorder DevTools',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const GestureRecorderExtensionHome(),
    );
  }
}

class GestureRecorderExtensionHome extends StatefulWidget {
  const GestureRecorderExtensionHome({super.key});

  @override
  State<GestureRecorderExtensionHome> createState() =>
      _GestureRecorderExtensionHomeState();
}

class _GestureRecorderExtensionHomeState
    extends State<GestureRecorderExtensionHome> {
  final _deviceCommunicator = DeviceCommunicator();

  Map<String, dynamic>? _parsedData;
  String? _error;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _deviceCommunicator.dispose();
    super.dispose();
  }

  bool _isConnected = false;

  Future<void> _init() async {
    // First thing to do is awaiting the vmService.
    await _deviceCommunicator.init(
      onConnected: () {
        setState(() => _isConnected = true);
      },
    );

    _deviceCommunicator.listenGestureData((data) {
      setState(() {
        _parsedData = jsonDecode(data);
        // Reset recording state when new data arrives (after stop)
        _isRecording = false;
      });
    });
  }

  void _openSavedFilesDialog() {
    showDialog(
      context: context,
      builder: (context) => SavedFilesDialog(
        deviceCommunicator: _deviceCommunicator,
        onFileLoaded: (data) {
          setState(() {
            _parsedData = data;
            _error = null;
          });
        },
      ),
    );
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;

    try {
      await _deviceCommunicator.startGestureOnDevice();
      setState(() {
        _isRecording = true;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Started recording on device'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting recording: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    try {
      await _deviceCommunicator.stopGestureOnDevice();
      setState(() {
        _isRecording = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stopped recording on device'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error stopping recording: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gesture Recorder'),
        actions: [
          if (_isConnected)
            IconButton(
              icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow),
              onPressed: _isRecording ? _stopRecording : _startRecording,
              tooltip: _isRecording
                  ? 'Stop recording on device'
                  : 'Start recording on device',
              color: _isRecording ? Colors.red : Colors.green,
            ),
          IconButton(
            icon: const Icon(Icons.folder),
            onPressed: _openSavedFilesDialog,
            tooltip: 'Open saved files',
          ),
        ],
      ),
      body: switch ((_isConnected, _error, _parsedData)) {
        (false, _, _) => _Message(
          icon: Icons.link_off,
          title: 'Waiting for connection',
          subtitle: 'Run an app with GestureRecorder to begin.',
        ),
        (true, String error, _) => _Message(
          icon: Icons.error_outline,
          title: 'Error',
          subtitle: error,
          color: Colors.red.shade300,
        ),

        (true, _, null) => _Message(
          icon: Icons.gesture,
          title: 'No recorded data yet',
          subtitle: 'Record gestures in your app to see them here.',
        ),

        (true, _, Map<String, dynamic> data) => GestureInspector(
          data: data,
          deviceCommunicator: _deviceCommunicator,
        ),
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: color ?? Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
