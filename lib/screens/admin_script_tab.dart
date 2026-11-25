import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/script_character.dart';
import '../widgets/character_picker_dialog.dart' show teamColor;
import '../widgets/character_ability_sheet.dart';
import '../widgets/team_distribution_row.dart';
import '../widgets/character_avatar.dart';

enum _AdminScriptSection { characters, nightOrder, images }

class AdminScriptTab extends StatefulWidget {
  const AdminScriptTab({super.key});
  @override
  State<AdminScriptTab> createState() => _AdminScriptTabState();
}

class _AdminScriptTabState extends State<AdminScriptTab> {
  _AdminScriptSection _section = _AdminScriptSection.characters;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final room = provider.room!;
    final characters = room.scriptCharacters;
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight + 8;

    return Column(
      children: [
        SizedBox(height: topInset),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: Text(characters.isEmpty
                      ? 'Import Script'
                      : 'Re-import Script'),
                  onPressed: () async {
                    final ok = await provider.importScript();
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(provider.lastError ??
                                'Could not import that script.')),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        if (characters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${characters.length} characters loaded',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        TeamDistributionRow(room: room),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<_AdminScriptSection>(
            segments: const [
              ButtonSegment(
                  value: _AdminScriptSection.characters,
                  label: Text('Characters')),
              ButtonSegment(
                  value: _AdminScriptSection.nightOrder,
                  label: Text('Night Order')),
              ButtonSegment(
                  value: _AdminScriptSection.images, label: Text('Images')),
            ],
            selected: {_section},
            onSelectionChanged: (s) => setState(() => _section = s.first),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (_section) {
            _AdminScriptSection.characters => _buildCharacters(characters),
            _AdminScriptSection.nightOrder =>
              _buildNightOrder(provider, room, characters),
            _AdminScriptSection.images => _buildImages(provider, room),
          },
        ),
      ],
    );
  }

  Widget _buildCharacters(List<ScriptCharacter> characters) {
    if (characters.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No script has been imported yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    child: Text(ScriptCharacter.teamLabel(team),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: teamColor(team))),
                  ),
                  for (final c in byTeam[team]!)
                    ListTile(
                      leading: CharacterAvatar(character: c, radius: 20),
                      title: Text(c.name),
                      subtitle: Text(c.ability,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => showCharacterAbilitySheet(context, c),
                    ),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNightOrder(
      GameProvider provider, room, List<ScriptCharacter> characters) {
    if (characters.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No script has been imported yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    final playerNameByCharacterId = <String, String>{};
    for (final entry in room.assignedCharacters.entries) {
      final player = room.players[entry.key];
      if (player != null) playerNameByCharacterId[entry.value] = player.name;
    }
    final firstNight = characters.where((c) => c.firstNight > 0).toList()
      ..sort((a, b) => a.firstNight.compareTo(b.firstNight));
    final otherNights = characters.where((c) => c.otherNight > 0).toList()
      ..sort((a, b) => a.otherNight.compareTo(b.otherNight));

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
              tabs: [Tab(text: 'First Night'), Tab(text: 'Other Nights')]),
          Expanded(
            child: TabBarView(
              children: [
                _nightList(
                    firstNight,
                    (c) => c.firstNightReminder,
                    'No characters in this script wake on the first night.',
                    playerNameByCharacterId),
                _nightList(
                    otherNights,
                    (c) => c.otherNightReminder,
                    'No characters in this script wake on other nights.',
                    playerNameByCharacterId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nightList(
      List<ScriptCharacter> list,
      String Function(ScriptCharacter) reminderOf,
      String emptyMessage,
      Map<String, String> playerNameByCharacterId) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey)),
        ),
      );
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (ctx, idx) {
        final c = list[idx];
        final reminder = reminderOf(c);
        final playerName = playerNameByCharacterId[c.id];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: teamColor(c.team),
            child: Text('${idx + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
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
              if (playerName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Wake: $playerName',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber)),
                ),
            ],
          ),
          isThreeLine: reminder.length > 40 || playerName != null,
        );
      },
    );
  }

  Widget _buildImages(GameProvider provider, room) {
    final scriptFiles = room.scriptImagePaths as List<String>;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.add_photo_alternate),
          label: const Text('Add Script Image'),
          onPressed: () async {
            final picker = ImagePicker();
            final picked = await picker.pickImage(source: ImageSource.gallery);
            if (picked != null) provider.addScriptImage(picked.path);
          },
        ),
        const SizedBox(height: 12),
        if (scriptFiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No script images uploaded yet.',
                style: TextStyle(color: Colors.grey)),
          )
        else
          for (final f in scriptFiles)
            Card(
              child: ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(f, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => provider.removeScriptImage(f),
                ),
              ),
            ),
      ],
    );
  }
}
