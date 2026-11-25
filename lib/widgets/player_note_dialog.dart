import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/player.dart';
import '../models/script_character.dart';
import 'character_picker_dialog.dart' show teamColor;

/// Opens a dialog to edit only the free-text note for [playerName].
///
/// A note is free text PLUS a set of quick-select "tags" (see
/// showPlayerTagPickerDialog below). This dialog handles the free-text
/// part only, preserving any existing tags.
///
/// By default this edits a PLAYER's private, local-only note about
/// another player (GameProvider.playerNotes) — never sent anywhere.
///
/// Pass [useAdminNotes] = true for the storyteller's own notes about a
/// player instead. Those are host-authoritative (GameProvider.adminNotes
/// / Player.adminNotes) rather than device-local, but are still never
/// broadcast to that player or anyone else.
Future<void> showPlayerNoteTextDialog(
  BuildContext context, {
  required String playerId,
  required String playerName,
  bool useAdminNotes = false,
}) async {
  final provider = context.read<GameProvider>();
  final existing = useAdminNotes
      ? provider.getAdminNoteFor(playerId)
      : provider.getNoteFor(playerId);
  final controller = TextEditingController(text: existing.text);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Note: $playerName'),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(
          hintText: 'e.g. "claimed to be the Chambermaid"',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final note = PlayerNote(
              text: controller.text.trim(),
              tags: existing.tags,
            );
            if (useAdminNotes) {
              provider.setAdminNoteFor(playerId, note);
            } else {
              provider.setNoteFor(playerId, note);
            }
            Navigator.pop(dialogContext);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Opens a dialog to edit only the quick-select tags for [playerName].
///
/// Tags come from the currently-imported script's reminder tokens (the
/// Poisoner's "Poisoned", the Witch's "Cursed", a generic "Dead" — see
/// ScriptCharacter.reminders/remindersGlobal). The dialog shows a Wrap
/// of FilterChips, each colored by its source character's team.
///
/// By default this edits a PLAYER's private, local-only note; pass
/// [useAdminNotes] = true for the storyteller's own notes.
Future<void> showPlayerTagPickerDialog(
  BuildContext context, {
  required String playerId,
  required String playerName,
  bool useAdminNotes = false,
}) async {
  final provider = context.read<GameProvider>();
  final existing = useAdminNotes
      ? provider.getAdminNoteFor(playerId)
      : provider.getNoteFor(playerId);
  final selected = <String>{...existing.tags};
  final available =
      ScriptCharacter.allTags(provider.room?.scriptCharacters ?? const []);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text('Tags: $playerName'),
        content: available.isEmpty
            ? const Text('No script imported yet.',
                style: TextStyle(color: Colors.grey))
            : SizedBox(
                width: double.maxFinite,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.45),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final entry in available)
                          FilterChip(
                            label: Text(entry.key,
                                style: const TextStyle(fontSize: 12)),
                            avatar: CircleAvatar(
                              radius: 7,
                              backgroundColor: teamColor(entry.value.team),
                            ),
                            selected: selected.contains(entry.key),
                            onSelected: (sel) => setState(() {
                              sel
                                  ? selected.add(entry.key)
                                  : selected.remove(entry.key);
                            }),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final note = PlayerNote(
                text: existing.text,
                tags: selected.toList(),
              );
              if (useAdminNotes) {
                provider.setAdminNoteFor(playerId, note);
              } else {
                provider.setNoteFor(playerId, note);
              }
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Read-only row of tag chips for showing an already-saved note's tags
/// wherever a note is displayed (NotesSummaryScreen, etc.). Looks each
/// tag up against the CURRENT script to color it; a tag that no longer
/// matches anything (script changed since the note was written) still
/// renders, just in neutral grey, rather than silently disappearing.
class NoteTagRow extends StatelessWidget {
  final List<String> tags;
  final List<ScriptCharacter> scriptCharacters;
  const NoteTagRow({
    super.key,
    required this.tags,
    required this.scriptCharacters,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final byTag = <String, ScriptCharacter>{};
    for (final entry in ScriptCharacter.allTags(scriptCharacters)) {
      byTag[entry.key] = entry.value;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final tag in tags)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (byTag[tag] != null
                        ? teamColor(byTag[tag]!.team)
                        : Colors.grey)
                    .withOpacity(0.22),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: byTag[tag] != null
                      ? teamColor(byTag[tag]!.team)
                      : Colors.grey,
                  width: 0.8,
                ),
              ),
              child: Text(tag, style: const TextStyle(fontSize: 10)),
            ),
        ],
      ),
    );
  }
}

/// Backward-compatible entry point — several screens (MeTab,
/// NotesSummaryScreen, etc.) still call this single combined name.
/// Routes to the text-only dialog, since these read-only summary
/// screens already render tags separately via NoteTagRow and only
/// need the text-editing flow when tapped.
Future<void> showPlayerNoteDialog(
  BuildContext context, {
  required String playerId,
  required String playerName,
  bool useAdminNotes = false,
}) {
  return showPlayerNoteTextDialog(
    context,
    playerId: playerId,
    playerName: playerName,
    useAdminNotes: useAdminNotes,
  );
}
