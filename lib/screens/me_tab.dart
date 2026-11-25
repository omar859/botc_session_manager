import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../widgets/character_ability_sheet.dart';
import '../widgets/character_picker_dialog.dart'
    show teamColor, alignmentColor, alignmentLabel;
import '../widgets/player_note_dialog.dart';
import '../widgets/character_avatar.dart';

class MeTab extends StatelessWidget {
  const MeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final myChar = provider.myCharacter;
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight + 8;
    final players = provider.room?.players ?? {};
    final noteEntries = provider.playerNotes.entries
        .where((e) => players.containsKey(e.key))
        .map((e) => MapEntry(players[e.key]!, e.value))
        .toList()
      ..sort((a, b) =>
          a.key.name.toLowerCase().compareTo(b.key.name.toLowerCase()));

    return ListView(
      padding: EdgeInsets.fromLTRB(0, topInset, 0, 16),
      children: [
        ListTile(
          leading: myChar == null
              ? const CircleAvatar(
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.theater_comedy, color: Colors.white),
                )
              : CharacterAvatar(
                  character: myChar,
                  radius: 20,
                  ringColor: alignmentColor(provider.myAlignment),
                ),
          title: const Text('My Character'),
          subtitle: Text(
            myChar == null
                ? 'Not assigned yet by the Storyteller'
                : '${myChar.name} · ${alignmentLabel(provider.myAlignment)}',
          ),
          onTap: myChar == null
              ? null
              : () => showCharacterAbilitySheet(context, myChar),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('My Bluffs (${provider.myBluffs.length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (provider.myBluffs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('The Storyteller has not sent you any bluffs yet.',
                style: TextStyle(color: Colors.grey)),
          )
        else
          for (int i = 0; i < provider.myBluffs.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in provider.myBluffs[i])
                    _bluffChip(context, provider, id),
                ],
              ),
            ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('My Notes (${noteEntries.length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (noteEntries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No notes yet. Add one from the Table tab.',
                style: TextStyle(color: Colors.grey)),
          )
        else
          for (final entry in noteEntries)
            ListTile(
              leading: const Icon(Icons.sticky_note_2, color: Colors.amber),
              title: Text(entry.key.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entry.value.text.isNotEmpty)
                    Text(entry.value.text,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                  NoteTagRow(
                    tags: entry.value.tags,
                    scriptCharacters:
                        provider.room?.scriptCharacters ?? const [],
                  ),
                ],
              ),
              onTap: () => showPlayerNoteDialog(context,
                  playerId: entry.key.id, playerName: entry.key.name),
            ),
      ],
    );
  }

  Widget _bluffChip(
      BuildContext context, GameProvider provider, String characterId) {
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
