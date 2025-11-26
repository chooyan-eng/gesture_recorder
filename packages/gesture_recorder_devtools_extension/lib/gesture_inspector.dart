import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gesture_recorder_devtools_extension/device_communicator.dart';
import 'package:gesture_recorder_devtools_extension/ide_communicator.dart';

class GestureInspector extends StatefulWidget {
  const GestureInspector({
    super.key,
    required this.data,
    required this.deviceCommunicator,
  });

  final Map<String, dynamic> data;
  final DeviceCommunicator deviceCommunicator;

  @override
  State<GestureInspector> createState() => _GestureInspectorState();
}

class _GestureInspectorState extends State<GestureInspector> {
  final _ideCommunicator = IdeCommunicator();

  bool _isPlaying = false;
  int _currentEventIndex = 0;
  final List<_TouchPoint> _visiblePoints = [];
  Timer? _replayTimer;
  Timer? _fadeTimer;

  double? _scale;
  final _replayAreaKey = GlobalKey();

  void _calculateScale() {
    final replayAreaSize = _replayAreaKey.currentContext?.size;
    if (replayAreaSize == null) return;

    final deviceWidth =
        (widget.data['screenSize']['width'] as num?)?.toDouble() ?? 0.0;

    _scale = replayAreaSize.width / deviceWidth;
  }

  @override
  void dispose() {
    _replayTimer?.cancel();
    _fadeTimer?.cancel();
    super.dispose();
  }

  void _startReplay() {
    if (_isPlaying) return;

    setState(() {
      _isPlaying = true;
      _currentEventIndex = 0;
      _visiblePoints.clear();
    });

    // Start periodic timer to fade out old points
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _visiblePoints.removeWhere((point) {
          return now.difference(point.timestamp).inMilliseconds > 500;
        });
      });
    });

    _playNextEvent();
  }

  void _stopReplay() {
    _replayTimer?.cancel();
    _fadeTimer?.cancel();
    setState(() {
      _isPlaying = false;
      _currentEventIndex = 0;
      _visiblePoints.clear();
    });
  }

  void _playNextEvent() {
    final events = widget.data['events'] as List?;
    if (events == null || _currentEventIndex >= events.length) {
      _stopReplay();
      return;
    }

    final event = events[_currentEventIndex] as Map<String, dynamic>;
    final packet = event['packet'] as Map<String, dynamic>;
    final data = packet['data'] as List;
    final timeSincePrevious = Duration(
      microseconds: (event['timeSincePrevious'] as num?)?.toInt() ?? 0,
    );

    // Wait for the time since previous event
    if (timeSincePrevious.inMilliseconds > 0 && _currentEventIndex > 0) {
      _replayTimer = Timer(timeSincePrevious, () {
        if (mounted && _isPlaying) {
          _processEvent(data);
          _currentEventIndex++;
          _playNextEvent();
        }
      });
    } else {
      _processEvent(data);
      _currentEventIndex++;
      _playNextEvent();
    }
  }

  void _processEvent(List data) {
    setState(() {
      for (final pointerData in data) {
        final pointer = pointerData as Map<String, dynamic>;
        final x = (pointer['physicalX'] as num?)?.toDouble() ?? 0.0;
        final y = (pointer['physicalY'] as num?)?.toDouble() ?? 0.0;
        final change = pointer['change'] as int? ?? 0;

        // PointerChange enum: 4=down, 5=move, 6=up
        Color color;
        if (change == 4) {
          // down
          color = Colors.blue;
        } else if (change == 5) {
          // move
          color = Colors.green;
        } else if (change == 6) {
          // up
          color = Colors.red;
        } else {
          color = Colors.grey;
        }

        _visiblePoints.add(
          _TouchPoint(x: x, y: y, color: color, timestamp: DateTime.now()),
        );
      }
    });
  }

  Future<void> _saveToWorkspace() async {
    try {
      // Generate timestamp-based filename
      final now = DateTime.now();
      final timestamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final fileName = 'gesture_$timestamp.json';

      await _ideCommunicator.saveToWorkspace(
        data: JsonEncoder.withIndent('  ').convert(widget.data), // pretty print
        fileName: fileName,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving file: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _replayOnDevice() async {
    try {
      final jsonString = JsonEncoder().convert(widget.data);
      await widget.deviceCommunicator.replayGestureOnDevice(jsonString);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Replaying on device'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error replaying on device: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = widget.data['screenSize'] as Map<String, dynamic>;
    final deviceWidth = (screenSize['width'] as num?)?.toDouble() ?? 0.0;
    final deviceHeight = (screenSize['height'] as num?)?.toDouble() ?? 0.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateScale();
    });

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: AspectRatio(
                  aspectRatio: deviceWidth / deviceHeight,
                  child: Container(
                    key: _replayAreaKey,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                    ),
                    child: CustomPaint(
                      painter: _TouchPainter(
                        points: _visiblePoints,
                        deviceWidth: deviceWidth,
                        deviceHeight: deviceHeight,
                        scale: _scale ?? 0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Controller',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _isPlaying ? _stopReplay : _startReplay,
                  icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                  label: Text(_isPlaying ? 'Stop' : 'Replay'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed:
                      widget.deviceCommunicator.isConnected &&
                          !widget.data.isEmpty
                      ? _replayOnDevice
                      : null,
                  icon: const Icon(Icons.phone_android),
                  label: const Text('Replay on Device'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed:
                      widget.deviceCommunicator.isConnected &&
                          !widget.data.isEmpty
                      ? () {
                          _replayOnDevice();
                          _startReplay();
                        }
                      : null,
                  icon: const Icon(Icons.phone_android),
                  label: const Text('Replay Both'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: widget.data.isEmpty ? null : _saveToWorkspace,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),

                if (_isPlaying)
                  Text(
                    'Playing event ${_currentEventIndex + 1}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TouchPoint {
  const _TouchPoint({
    required this.x,
    required this.y,
    required this.color,
    required this.timestamp,
  });

  final double x;
  final double y;
  final Color color;
  final DateTime timestamp;
}

class _TouchPainter extends CustomPainter {
  _TouchPainter({
    required this.points,
    required this.deviceWidth,
    required this.deviceHeight,
    required this.scale,
  });

  final List<_TouchPoint> points;
  final double deviceWidth;
  final double deviceHeight;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final point in points) {
      final paint = Paint()
        ..color = point.color
        ..style = PaintingStyle.fill;

      // Draw circle at the touch point
      canvas.drawCircle(Offset(point.x * scale, point.y * scale), 8.0, paint);

      // Draw a subtle outer ring
      final ringPaint = Paint()
        ..color = point.color.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(
        Offset(point.x * scale, point.y * scale),
        16.0,
        ringPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_TouchPainter oldDelegate) {
    // Repaint when points list changes
    return points.length != oldDelegate.points.length;
  }
}
