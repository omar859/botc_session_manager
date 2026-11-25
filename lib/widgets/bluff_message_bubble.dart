import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import 'character_ability_sheet.dart' show showCharacterAbilitySheet;
import 'character_avatar.dart';

/// Renders a storyteller "bluff" message — a list of character IDs the
/// storyteller (as the demon) is claiming are the not-in-play characters.
/// Shown as a distinct deep-purple bubble with tappable character chips;
/// tapping a chip opens that character's ability sheet (same sheet used
/// everywhere else in the app).
///
/// Always left-aligned: bluffs only ever come from the Storyteller, so
/// there's no "isMine" variant.
class BluffMessageBubble extends StatelessWidget {
  final List<String> bluffs;
  final String senderName;

  const BluffMessageBubble({
    super.key,
    required this.bluffs,
    this.senderName = 'Storyteller',
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<GameProvider>();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.85,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withOpacity(0.35),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: Colors.deepPurple.withOpacity(0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎭', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  '$senderName — Bluffs',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final id in bluffs) _buildChip(context, provider, id),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(
      BuildContext context, GameProvider provider, String characterId) {
    final character = provider.characterById(characterId);
    final label = character?.name ?? characterId;
    return ActionChip(
      label: Text(label),
      avatar: character != null
          ? CharacterAvatar(character: character, radius: 8)
          : const CircleAvatar(radius: 8, backgroundColor: Colors.grey),
      onPressed: character == null
          ? null
          : () => showCharacterAbilitySheet(context, character),
    );
  }
}
