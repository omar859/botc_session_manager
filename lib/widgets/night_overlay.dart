import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../services/sound_service.dart';

class NightOverlay extends StatelessWidget {
  const NightOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final isNight = context.select<GameProvider, bool>((p) => p.isNight);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: isNight ? 0.55 : 0.0,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
        child: const ColoredBox(color: Colors.black),
      ),
    );
  }
}

class DayNightSoundListener extends StatefulWidget {
  const DayNightSoundListener({super.key});

  @override
  State<DayNightSoundListener> createState() => _DayNightSoundListenerState();
}

class _DayNightSoundListenerState extends State<DayNightSoundListener> {
  bool _wasNight = false;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final isNight = context.select<GameProvider, bool>((p) => p.isNight);
    final isHost = context.select<GameProvider, bool>((p) => p.isHost);
    if (!_initialized) {
      _initialized = true;
      _wasNight = isNight;
      if (isNight && !isHost) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) SoundService.instance.playNightAmbience();
        });
      }
    }
    if (isNight != _wasNight) {
      _wasNight = isNight;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (isNight && !isHost) {
          SoundService.instance.playNightAmbience();
        } else {
          SoundService.instance.stopNightAmbience();
        }
      });
    }
    return const SizedBox.shrink();
  }
}
