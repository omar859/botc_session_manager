import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import 'character_ability_sheet.dart' show showCharacterAbilitySheet;
import 'character_avatar.dart';
import 'character_picker_dialog.dart' show teamColor;

/// "Pill inside a pill": one outer Fabled pill, with one inner pill per
/// Fabled currently in play. Tapping an inner pill opens the normal
/// ability sheet. Renders nothing when no Fabled are active.
class FabledStrip extends StatelessWidget {
  const FabledStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final fabled = context.watch<GameProvider>().activeFabled;
    if (fabled.isEmpty) return const SizedBox.shrink();
    final accent = teamColor('fabled');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: accent.withOpacity(0.45), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 16, color: accent),
            const SizedBox(width: 6),
            Text('FABLED',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: accent)),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in fabled)
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => showCharacterAbilitySheet(context, c),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: accent.withOpacity(0.7)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CharacterAvatar(character: c, radius: 11),
                            const SizedBox(width: 6),
                            Text(c.name,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
