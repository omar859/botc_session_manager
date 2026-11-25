import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/script_character.dart';
import '../widgets/character_picker_dialog.dart' show teamColor;
import '../widgets/character_ability_sheet.dart';

/// Lists every character in the currently-imported script, grouped by
/// team, with a search box. This is separate from ScriptViewer (which
/// shows the script as an uploaded image) — this reads the actual
/// imported JSON data, so it works even if no image was ever uploaded.
class ScriptCharactersScreen extends StatefulWidget {
  const ScriptCharactersScreen({super.key});

  @override
  State<ScriptCharactersScreen> createState() => _ScriptCharactersScreenState();
}

class _ScriptCharactersScreenState extends State<ScriptCharactersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final characters = provider.room?.scriptCharacters ?? [];
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? characters
        : characters
            .where((c) => c.name.toLowerCase().contains(query))
            .toList();

    final byTeam = <String, List<ScriptCharacter>>{};
    for (final c in filtered) {
      byTeam.putIfAbsent(c.team, () => []).add(c);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(characters.isEmpty
            ? 'Script Characters'
            : 'Script Characters (${characters.length})'),
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
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search characters...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final team in ScriptCharacter.teamOrder)
                        if (byTeam[team]?.isNotEmpty == true) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              ScriptCharacter.teamLabel(team),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: teamColor(team),
                              ),
                            ),
                          ),
                          for (final c in byTeam[team]!)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: teamColor(c.team),
                                child: Text(
                                  c.name.isNotEmpty
                                      ? c.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(c.name),
                              subtitle: Text(
                                c.ability,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () =>
                                  showCharacterAbilitySheet(context, c),
                            ),
                        ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
