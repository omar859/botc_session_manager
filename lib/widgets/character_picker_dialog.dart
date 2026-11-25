import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/script_character.dart';
import '../providers/game_provider.dart';
import '../services/script_library.dart';
import 'character_avatar.dart';
import 'character_ability_sheet.dart' show showCharacterAbilitySheet;

Color teamColor(String team) {
  switch (team) {
    case 'townsfolk':
      return Colors.blue;
    case 'outsider':
      return Colors.cyan;
    case 'minion':
      return Colors.orange;
    case 'demon':
      return Colors.red;
    case 'traveler':
      return Colors.purple;
    case 'fabled':
      return Colors.amber;
    case 'custom':
      return Colors.teal;
    default:
      return Colors.grey;
  }
}

// NEW: alignment is binary and deliberately overrides the usual
// multi-team palette wherever a specific player's assignment is shown
// — good is always the Townsfolk blue, evil is always the Demon red,
// regardless of the character's actual team. A "good" Imp shows blue;
// an "evil" Townsfolk (rare, but the Storyteller can set it) shows red.
Color alignmentColor(String? alignment) =>
    alignment == 'evil' ? Colors.red : Colors.blue;

String alignmentLabel(String? alignment) =>
    alignment == 'evil' ? 'Evil' : 'Good';

/// Opens a picker over [characters] (grouped by team) and returns the
/// chosen character's id, a free-typed custom label (prefixed so callers
/// can tell it apart if needed), or null if cancelled. Pass [currentValue]
/// to pre-select/highlight what's already set, and [allowClear] to show a
/// "Clear" action.
Future<String?> showCharacterPickerDialog(
  BuildContext context, {
  required List<ScriptCharacter> characters,
  required String title,
  String? currentValue,
  bool allowClear = true,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CharacterPickerDialog(
      characters: characters,
      title: title,
      currentValue: currentValue,
      allowClear: allowClear,
    ),
  );
}

/// Multi-select variant of the character picker. Returns the chosen list
/// of character IDs (empty list if the user confirmed with nothing
/// selected, or null if they cancelled). Used by the storyteller's "Send
/// Bluffs" action — the demon claims a set of not-in-play characters.
Future<List<String>?> showMultiCharacterPickerDialog(
  BuildContext context, {
  required List<ScriptCharacter> characters,
  required String title,
  Set<String>? initialSelection,
  String? onlyTeam,
  String actionNoun = 'bluff',
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _MultiCharacterPickerDialog(
      characters: characters,
      title: title,
      initialSelection: initialSelection ?? const {},
      onlyTeam: onlyTeam,
      actionNoun: actionNoun,
    ),
  );
}

class _MultiCharacterPickerDialog extends StatefulWidget {
  final List<ScriptCharacter> characters;
  final String title;
  final Set<String> initialSelection;
  final String? onlyTeam;
  final String actionNoun;

  const _MultiCharacterPickerDialog({
    required this.characters,
    required this.title,
    required this.initialSelection,
    this.onlyTeam,
    this.actionNoun = 'bluff',
  });

  @override
  State<_MultiCharacterPickerDialog> createState() =>
      _MultiCharacterPickerDialogState();
}

class _MultiCharacterPickerDialogState
    extends State<_MultiCharacterPickerDialog> {
  final _searchController = TextEditingController();
  String _query = '';
  late final Set<String> _selected = Set<String>.from(widget.initialSelection);

  bool _showAllCharacters = false;
  List<ScriptCharacter>? _allOfficialCharacters;
  bool _loadingAll = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _ensureAllLoaded() async {
    if (_allOfficialCharacters != null || _loadingAll) return;
    setState(() => _loadingAll = true);
    final list = await ScriptLibrary.instance.loadAllOfficialCharacters();
    if (!mounted) return;
    setState(() {
      _allOfficialCharacters = list;
      _loadingAll = false;
    });
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rawSource = _showAllCharacters
        ? (_allOfficialCharacters ?? const <ScriptCharacter>[])
        : widget.characters;
    final sourceList = widget.onlyTeam == null
        ? rawSource
        : rawSource.where((c) => c.team == widget.onlyTeam).toList();

    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? sourceList
        : sourceList
            .where((c) => c.name.toLowerCase().contains(query))
            .toList();

    final byTeam = <String, List<ScriptCharacter>>{};
    for (final c in filtered) {
      byTeam.putIfAbsent(c.team, () => []).add(c);
    }

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('Clear'),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search characters...',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Show all characters',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Switch(
                  value: _showAllCharacters,
                  onChanged: (v) {
                    setState(() => _showAllCharacters = v);
                    if (v) _ensureAllLoaded();
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Hold a character to see its ability',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: (_showAllCharacters && _loadingAll)
                  ? const Center(child: CircularProgressIndicator())
                  : (sourceList.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No script imported yet.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final team in ScriptCharacter.teamOrder)
                              if (byTeam[team]?.isNotEmpty == true) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 4),
                                  child: Text(
                                    ScriptCharacter.teamLabel(team),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: teamColor(team),
                                    ),
                                  ),
                                ),
                                for (final c in byTeam[team]!)
                                  ListTile(
                                    dense: true,
                                    leading: CharacterAvatar(
                                        character: c, radius: 15),
                                    title: Text(c.name),
                                    trailing: _selected.contains(c.id)
                                        ? const Icon(Icons.check_circle,
                                            color: Colors.deepPurple)
                                        : const Icon(Icons.circle_outlined,
                                            color: Colors.grey),
                                    selected: _selected.contains(c.id),
                                    onTap: () => _toggle(c.id),
                                    onLongPress: () =>
                                        showCharacterAbilitySheet(context, c),
                                  ),
                              ],
                          ],
                        )),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: Text(_selected.isEmpty
              ? 'Done'
              : 'Set ${_selected.length} ${widget.actionNoun}${_selected.length == 1 ? '' : 's'}'),
        ),
      ],
    );
  }
}

class _CharacterPickerDialog extends StatefulWidget {
  final List<ScriptCharacter> characters;
  final String title;
  final String? currentValue;
  final bool allowClear;

  const _CharacterPickerDialog({
    required this.characters,
    required this.title,
    required this.currentValue,
    required this.allowClear,
  });

  @override
  State<_CharacterPickerDialog> createState() => _CharacterPickerDialogState();
}

class _CharacterPickerDialogState extends State<_CharacterPickerDialog> {
  final _searchController = TextEditingController();
  String _query = '';
  // NEW: when on, browse every official character from roles.json
  // instead of only the characters in the currently-imported script —
  // lets the Storyteller assign a character that isn't in this
  // session's script at all.
  bool _showAllCharacters = false;
  List<ScriptCharacter>? _allOfficialCharacters;
  bool _loadingAll = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _ensureAllLoaded() async {
    if (_allOfficialCharacters != null || _loadingAll) return;
    setState(() => _loadingAll = true);
    final list = await ScriptLibrary.instance.loadAllOfficialCharacters();
    if (!mounted) return;
    setState(() {
      _allOfficialCharacters = list;
      _loadingAll = false;
    });
  }

  Future<void> _pickCustom() async {
    final nameController = TextEditingController();
    final abilityController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom character'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Name', hintText: 'e.g. "Widow"'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: abilityController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Ability (optional)',
                  hintText: 'What does this character do?',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, {
              'name': nameController.text.trim(),
              'ability': abilityController.text.trim(),
            }),
            child: const Text('Use this'),
          ),
        ],
      ),
    );
    final name = result?['name'];
    if (name != null && name.isNotEmpty && mounted) {
      final ability = result?['ability'] ?? '';
      final custom = ScriptCharacter(
        id: name,
        name: name,
        team: 'custom',
        ability: ability.isEmpty ? '(No ability text provided.)' : ability,
      );
      context.read<GameProvider>().registerKnownCharacter(custom);
      Navigator.pop(context, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourceList = _showAllCharacters
        ? (_allOfficialCharacters ?? const <ScriptCharacter>[])
        : widget.characters;

    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? sourceList
        : sourceList
            .where((c) => c.name.toLowerCase().contains(query))
            .toList();

    final byTeam = <String, List<ScriptCharacter>>{};
    for (final c in filtered) {
      byTeam.putIfAbsent(c.team, () => []).add(c);
    }

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search characters...',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            // NEW: toggle between "this script only" and "every
            // official character" — a search-friendly way to assign
            // something outside the imported script.
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Show all characters',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Switch(
                  value: _showAllCharacters,
                  onChanged: (v) {
                    setState(() => _showAllCharacters = v);
                    if (v) _ensureAllLoaded();
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Hold a character to see its ability',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: (_showAllCharacters && _loadingAll)
                  ? const Center(child: CircularProgressIndicator())
                  : (sourceList.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No script imported yet.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final team in ScriptCharacter.teamOrder)
                              if (byTeam[team]?.isNotEmpty == true) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 4),
                                  child: Text(
                                    ScriptCharacter.teamLabel(team),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: teamColor(team),
                                    ),
                                  ),
                                ),
                                for (final c in byTeam[team]!)
                                  ListTile(
                                    dense: true,
                                    leading: CharacterAvatar(
                                        character: c, radius: 15),
                                    title: Text(c.name),
                                    selected: c.id == widget.currentValue,
                                    onTap: () {
                                      // Registered regardless of source — cheap,
                                      // and guarantees the ability/flavor is
                                      // resolvable locally the instant it's picked,
                                      // not just once a network round-trip returns.
                                      context
                                          .read<GameProvider>()
                                          .registerKnownCharacter(c);
                                      Navigator.pop(context, c.id);
                                    },
                                    onLongPress: () =>
                                        showCharacterAbilitySheet(context, c),
                                  ),
                              ],
                          ],
                        )),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.allowClear && widget.currentValue != null)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Clear'),
          ),
        TextButton(
          onPressed: _pickCustom,
          child: const Text('Custom...'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
