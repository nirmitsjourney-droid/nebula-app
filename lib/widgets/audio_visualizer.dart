import 'package:flutter/material.dart';

import '../services/voice_service.dart';
import '../theme/nebula_theme.dart';

/// A 16-bar audio visualizer that reflects [VoiceService.amplitudes].
///
/// Uses solid colors (no gradients/transparency) to match the Material 3 Expressive spec.
class AudioVisualizer extends StatelessWidget {
  const AudioVisualizer({
    super.key,
    required this.voiceService,
    this.height = 80,
    this.barWidth = 4,
    this.barSpacing = 3,
  });

  final VoiceService voiceService;
  final double height;
  final double barWidth;
  final double barSpacing;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voiceService,
      builder: (context, _) {
        final amps = voiceService.amplitudes;
        final isActive = voiceService.state != VoiceState.idle;
        
        // Colors selected from the M3 Palette (Secondary/Teal if speaking, Primary/Purple if listening)
        final color = voiceService.state == VoiceState.speakingAI
            ? NebulaTheme.secondary
            : NebulaTheme.primary;

        return SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(amps.length, (i) {
              final amp = isActive ? amps[i] : 0.05;
              final barHeight = (amp * height).clamp(4.0, height);

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: barSpacing / 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  curve: Curves.easeOut,
                  width: barWidth,
                  height: barHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(barWidth / 2),
                    color: color,
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
