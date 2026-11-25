import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../widgets/character_ability_sheet.dart' show showCharacterAbilitySheet;
import '../widgets/character_picker_dialog.dart' show teamColor;

/// Shows every bluff set the Storyteller has sent this player, most-recent
/// last, each rendered as a row of tappable character chips (tap → that
/// character's ability sheet — same widget used everywhere else in the
/// app). This is reachable directly from the lobby app bar (see the badge
/// button in LobbyScreen) rather than being buried behind the drawer, so
/// it's always one tap away instead of something a player has to
/// remember happened once in chat.
class BluffsScreen extends StatelessWidget {
  const BluffsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final bluffSets = provider.myBluffs;

    return Scaffold(
      appBar: AppBar(title: const Text('My Bluffs')),
      body: bluffSets.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'The Storyteller has not sent you any bluffs yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: bluffSets.length,
              separatorBuilder: (_, __) => const Divider(height: 24),
              itemBuilder: (ctx, idx) {
                final set = bluffSets[idx];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bluff set ${idx + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in set) _BluffChip(characterId: id),
                      ],
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _BluffChip extends StatelessWidget {
  final String characterId;
  const _BluffChip({required this.characterId});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<GameProvider>();
    final character = provider.characterById(characterId);
    final label = character?.name ?? characterId;
    return ActionChip(
      label: Text(label),
      avatar: CircleAvatar(
        radius: 9,
        backgroundColor:
            character != null ? teamColor(character.team) : Colors.grey,
      ),
      onPressed: character == null
          ? null
          : () => showCharacterAbilitySheet(context, character),
    );
  }
}
