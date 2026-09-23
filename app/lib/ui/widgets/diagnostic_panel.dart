import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';

class DiagnosticPanel extends StatelessWidget {
  final int fps;
  final int inferenceTimeMs;

  const DiagnosticPanel({
    super.key,
    this.fps = 0,
    this.inferenceTimeMs = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateModel>(
      builder: (context, appState, child) {
        return Container(
          color: Colors.black87,
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('State: ${appState.currentState.name}', style: const TextStyle(color: Colors.white, fontSize: 12)),
              Text('FPS: $fps', style: const TextStyle(color: Colors.white, fontSize: 12)),
              Text('Inference: ${inferenceTimeMs}ms', style: const TextStyle(color: Colors.white, fontSize: 12)),
              if (appState.errorMessage.isNotEmpty)
                Text('Error: ${appState.errorMessage}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}
