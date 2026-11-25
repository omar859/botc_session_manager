import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'character_picker_dialog.dart' show alignmentColor, alignmentLabel;
import '../providers/game_provider.dart';

/// Shared "glossy card" popup used for the character/alignment reveal,
/// Storyteller announcements, and the winner declaration — one
/// consistent look instead of three near-duplicate dialog builders.
Future<void> showGlowPopup(
  BuildContext context, {
  required Color accent,
  required Widget icon,
  String? eyebrow,
  required String title,
  String? subtitle,
  Widget? body,
  required List<Widget> actions,
  bool barrierDismissible = false,
}) {
  return showDialog(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                  accent.withOpacity(0.26), const Color(0xFF1E1E2E)),
              const Color(0xFF1E1E2E),
            ],
            stops: const [0.0, 0.42],
          ),
          border: Border.all(color: accent.withOpacity(0.55), width: 1.3),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(0.16),
                border: Border.all(color: accent, width: 2.2),
                boxShadow: [
                  BoxShadow(
                      color: accent.withOpacity(0.55),
                      blurRadius: 26,
                      spreadRadius: 1.5),
                ],
              ),
              child: Center(child: icon),
            ),
            if (eyebrow != null) ...[
              const SizedBox(height: 14),
              Text(
                eyebrow,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.3,
                    color: accent),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ],
            if (body != null) ...[
              const SizedBox(height: 16),
              body,
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                for (int i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: actions[i]),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Winner declaration — same visual family, blue glow for Good, red
/// glow for Evil, shown on every device (including the Storyteller's
/// own screen) once the Storyteller declares a winner.
Future<void> showWinnerPopup(BuildContext context, String alignment,
    {required VoidCallback onClosed}) async {
  final provider = context.read<GameProvider>();
  final generation = provider.newGameGeneration;
  void dismissForNewGame() {
    if (!context.mounted || provider.newGameGeneration == generation) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) navigator.pop();
  }

  final accent = alignmentColor(alignment);
  provider.addListener(dismissForNewGame);
  try {
    await showGlowPopup(
      context,
      accent: accent,
      icon: Icon(alignment == 'evil' ? Icons.whatshot : Icons.shield,
          color: accent, size: 34),
      title: '${alignmentLabel(alignment).toUpperCase()} WINS',
      subtitle: 'The game has ended.',
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: accent, foregroundColor: Colors.black),
          onPressed: () {
            Navigator.pop(context);
            onClosed();
          },
          child: const Text('Close',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  } finally {
    provider.removeListener(dismissForNewGame);
  }
}
