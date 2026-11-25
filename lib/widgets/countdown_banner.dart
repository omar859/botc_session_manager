import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

/// Floating countdown card — same top-left "tiny card" treatment as
/// the private-chat/join-chat request banners, stacked below both so
/// none overlap. Lives in the outer Stack (not inside any specific
/// chat body), so it stays visible and keeps ticking no matter which
/// bottom-nav tab the player or Storyteller is currently on.
class CountdownFloatingCard extends StatefulWidget {
  const CountdownFloatingCard({super.key});
  @override
  State<CountdownFloatingCard> createState() => _CountdownFloatingCardState();
}

class _CountdownFloatingCardState extends State<CountdownFloatingCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      context.read<GameProvider>().maybeFireCountdownAlarm();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final endTime = context.watch<GameProvider>().countdownEndTime;
    if (endTime == null) return const SizedBox.shrink();

    final remaining = endTime.difference(DateTime.now());
    final done = remaining.isNegative;
    final label = done
        ? "Time's up!"
        : '${remaining.inMinutes.toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';

    return Positioned(
      top: MediaQuery.of(context).padding.top + 84,
      left: 8,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                done ? Colors.red.withOpacity(0.28) : const Color(0xFF2A2A3D),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(done ? '⏰' : '⏳', style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
