import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/script_character.dart';
import '../widgets/character_picker_dialog.dart' show teamColor;

/// Shows the night order for the currently-imported script — two lists,
/// First Night and Other Nights, each in wake-up order. The order itself
/// is public information at a real table (everyone knows characters wake
/// in some order, even though only the storyteller knows who has which
/// character), so this screen is reachable from both the storyteller's
/// admin panel and every player's own lobby drawer.
///
/// roles.json gives every character an absolute firstNight/otherNight
/// number across the *entire* official character pool (e.g. 2, 10, 13...),
/// which only means "wakes before/after" relative to other numbers — it's
/// not meant to be shown as-is. This screen filters down to just the
/// characters actually in the current script, sorts by that number, and
/// re-numbers them 1st/2nd/3rd/... so what's on screen is the actual
/// running order for tonight, not the raw reference numbers.
///
/// [showPlayerNames] additionally shows which player currently has each
/// character, straight from RoomState.assignedCharacters — the same
/// host-only map that's deliberately never broadcast to anyone. Pass this
/// as true ONLY from the storyteller's own screen (admin_panel.dart). The
/// lobby (a player's own screen) must keep the default false — a player's
/// copy of the room never actually has this data populated in the first
/// place, but the flag defaulting to false is the real safeguard, not
/// that.
class NightOrderScreen extends StatelessWidget {
  final bool showPlayerNames;
  const NightOrderScreen({super.key, this.showPlayerNames = false});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final room = provider.room;
    final characters = room?.scriptCharacters ?? [];

    // characterId -> player name, built only when this screen is allowed
    // to show it at all.
    final Map<String, String> playerNameByCharacterId = {};
    if (showPlayerNames && room != null) {
      for (final entry in room.assignedCharacters.entries) {
        final player = room.players[entry.key];
        if (player != null) {
          playerNameByCharacterId[entry.value] = player.name;
        }
      }
    }

    final firstNight = characters.where((c) => c.firstNight > 0).toList()
      ..sort((a, b) => a.firstNight.compareTo(b.firstNight));
    final otherNights = characters.where((c) => c.otherNight > 0).toList()
      ..sort((a, b) => a.otherNight.compareTo(b.otherNight));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Night Order'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'First Night'),
              Tab(text: 'Other Nights'),
            ],
          ),
        ),
        body: characters.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No script has been imported yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            : TabBarView(
                children: [
                  _NightOrderList(
                    characters: firstNight,
                    reminderOf: (c) => c.firstNightReminder,
                    emptyMessage:
                        'No characters in this script wake on the first night.',
                    playerNameByCharacterId: playerNameByCharacterId,
                  ),
                  _NightOrderList(
                    characters: otherNights,
                    reminderOf: (c) => c.otherNightReminder,
                    emptyMessage:
                        'No characters in this script wake on other nights.',
                    playerNameByCharacterId: playerNameByCharacterId,
                  ),
                ],
              ),
      ),
    );
  }
}

class _NightOrderList extends StatelessWidget {
  final List<ScriptCharacter> characters;
  final String Function(ScriptCharacter) reminderOf;
  final String emptyMessage;
  final Map<String, String> playerNameByCharacterId;

  const _NightOrderList({
    required this.characters,
    required this.reminderOf,
    required this.emptyMessage,
    required this.playerNameByCharacterId,
  });

  @override
  Widget build(BuildContext context) {
    if (characters.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: characters.length,
      itemBuilder: (ctx, idx) {
        final c = characters[idx];
        final reminder = reminderOf(c);
        final playerName = playerNameByCharacterId[c.id];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: teamColor(c.team),
            child: Text(
              '${idx + 1}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          title: Text(c.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              reminder.isEmpty
                  ? Text(ScriptCharacter.teamLabel(c.team),
                      style: TextStyle(fontSize: 11, color: teamColor(c.team)))
                  : Text(reminder, style: const TextStyle(fontSize: 12)),
              // NEW: storyteller-only — who currently has this character,
              // so the storyteller knows exactly who to wake without
              // cross-referencing the seating list separately.
              if (playerName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Wake: $playerName',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                ),
            ],
          ),
          isThreeLine: reminder.length > 40 || playerName != null,
        );
      },
    );
  }
}
