import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/room_state.dart';
import '../widgets/character_picker_dialog.dart'
    show teamColor, showMultiCharacterPickerDialog;

/// Storyteller-only screen for reviewing every bluff set sent so far,
/// grouped by player, with the ability to delete an individual set (e.g.
/// after correcting a mistaken claim) and to send a new set without
/// leaving this screen. Complements the existing "Send Bluffs" quick
/// action in AdminPanel's drawer, which only ever sends — it has no way
/// to see or undo what's already been sent.
class BluffsManagerScreen extends StatelessWidget {
  const BluffsManagerScreen({super.key});

  Future<void> _sendMore(BuildContext context, GameProvider provider,
      RoomState room, String playerId) async {
    if (room.scriptCharacters.isEmpty) return;
    final characterIds = await showMultiCharacterPickerDialog(
      context,
      characters: room.scriptCharacters,
      title: 'Select Bluffs',
    );
    if (characterIds == null || characterIds.isEmpty) return;
    provider.adminSendBluffs(characterIds, playerId);
  }

  Widget _chip(GameProvider provider, String characterId) {
    final character = provider.characterById(characterId);
    final label = character?.name ?? characterId;
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      avatar: CircleAvatar(
        radius: 8,
        backgroundColor:
            character != null ? teamColor(character.team) : Colors.grey,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final room = provider.room!;
    final entries =
        room.playerBluffs.entries.where((e) => e.value.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Bluffs')),
      body: entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No bluffs have been sent to any player yet.\n'
                  'Use "Send Bluffs" from the menu to send some.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (ctx, i) {
                final playerId = entries[i].key;
                final sets = entries[i].value;
                final playerName =
                    room.players[playerId]?.name ?? 'Unknown player';
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(playerName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            TextButton.icon(
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add'),
                              onPressed: room.scriptCharacters.isEmpty
                                  ? null
                                  : () => _sendMore(
                                      context, provider, room, playerId),
                            ),
                          ],
                        ),
                        for (int setIdx = 0; setIdx < sets.length; setIdx++)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final charId in sets[setIdx])
                                        _chip(provider, charId),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20, color: Colors.redAccent),
                                  tooltip: 'Delete this bluff set',
                                  onPressed: () =>
                                      provider.deleteBluffSet(playerId, setIdx),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
