import 'package:example/counter_app.dart';
import 'package:flutter/material.dart';
import 'package:gesture_recorder/gesture_recorder.dart';

void main() {
  runApp(GestureRecorder(child: const MyApp()));

  // for more detailed example
  // runApp(GestureRecorder(child: const DrawingCanvasExample()));
  // runApp(GestureRecorder(child: const CounterApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      home: const CounterApp(title: 'Flutter Demo Home Page'),
    );
  }
}
