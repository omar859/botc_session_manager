import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/player.dart';
import '../widgets/player_note_dialog.dart';

/// Lists every player there's a note about, so notes don't have to be
/// looked up one player at a time. This screen is opened from two places
/// with two different meanings of "note":
///  - admin_panel.dart (the storyteller) passes [useAdminNotes] = true to
///    read the host-authoritative Player.adminNotes.
///  - lobby_screen.dart (a player) uses the default false, reading that
///    device's own local, private playerNotes map about other players.
class NotesSummaryScreen extends StatelessWidget {
  final bool useAdminNotes;
  const NotesSummaryScreen({super.key, this.useAdminNotes = false});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final playersMap = provider.room?.players ?? <String, Player>{};
    final scriptCharacters = provider.room?.scriptCharacters ?? const [];

    final List<MapEntry<Player, PlayerNote>> entries;
    if (useAdminNotes) {
      entries = playersMap.values
          .where((p) => !p.adminNotes.isEmpty)
          .map((p) => MapEntry(p, p.adminNotes))
          .toList();
    } else {
      entries = provider.playerNotes.entries
          .where((e) => playersMap.containsKey(e.key))
          .map((e) => MapEntry(playersMap[e.key]!, e.value))
          .toList();
    }
    entries.sort(
        (a, b) => a.key.name.toLowerCase().compareTo(b.key.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('My Notes')),
      body: entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No notes yet.\nTap the note icon next to a player\'s name to add one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final player = entries[idx].key;
                final note = entries[idx].value;
                return ListTile(
                  leading: const Icon(Icons.sticky_note_2, color: Colors.amber),
                  title: Text(player.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (note.text.isNotEmpty)
                        Text(
                          note.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      NoteTagRow(
                        tags: note.tags,
                        scriptCharacters: scriptCharacters,
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => showPlayerNoteDialog(context,
                      playerId: player.id,
                      playerName: player.name,
                      useAdminNotes: useAdminNotes),
                );
              },
            ),
    );
  }
}
