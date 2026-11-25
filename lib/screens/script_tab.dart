import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/script_character.dart';
import '../widgets/character_picker_dialog.dart' show teamColor;
import '../widgets/character_ability_sheet.dart';
import '../widgets/character_avatar.dart';

enum _ScriptSection { characters, nightOrder, images }

class ScriptTab extends StatefulWidget {
  const ScriptTab({super.key});
  @override
  State<ScriptTab> createState() => _ScriptTabState();
}

class _ScriptTabState extends State<ScriptTab> {
  _ScriptSection _section = _ScriptSection.characters;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final characters = provider.room?.scriptCharacters ?? [];
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight + 8;

    return Column(
      children: [
        SizedBox(height: topInset),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<_ScriptSection>(
            segments: const [
              ButtonSegment(
                  value: _ScriptSection.characters, label: Text('Characters')),
              ButtonSegment(
                  value: _ScriptSection.nightOrder, label: Text('Night Order')),
              ButtonSegment(
                  value: _ScriptSection.images, label: Text('Images')),
            ],
            selected: {_section},
            onSelectionChanged: (s) => setState(() => _section = s.first),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (_section) {
            _ScriptSection.characters => _buildCharacters(characters),
            _ScriptSection.nightOrder => _buildNightOrder(provider, characters),
            _ScriptSection.images => _buildImages(provider),
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
      GameProvider provider, List<ScriptCharacter> characters) {
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
                _nightList(firstNight, (c) => c.firstNightReminder,
                    'No characters in this script wake on the first night.'),
                _nightList(otherNights, (c) => c.otherNightReminder,
                    'No characters in this script wake on other nights.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nightList(List<ScriptCharacter> list,
      String Function(ScriptCharacter) reminderOf, String emptyMessage) {
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
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: teamColor(c.team),
            child: Text('${idx + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          title: Text(c.name),
          subtitle: reminder.isEmpty
              ? Text(ScriptCharacter.teamLabel(c.team),
                  style: TextStyle(fontSize: 11, color: teamColor(c.team)))
              : Text(reminder, style: const TextStyle(fontSize: 12)),
        );
      },
    );
  }

  Widget _buildImages(GameProvider provider) {
    List<String> urls = [];
    if (provider.isHost) {
      final room = provider.room;
      if (room != null) {
        urls = room.scriptImagePaths
            .map((f) =>
                'http://${provider.hostIp}:${provider.hostPort}/script/$f')
            .toList();
      }
    } else {
      urls = provider.scriptImageUrls;
    }
    if (urls.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No script images have been uploaded for this game yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: PhotoViewGallery.builder(
        itemCount: urls.length,
        builder: (context, index) => PhotoViewGalleryPageOptions(
          imageProvider: NetworkImage(urls[index]),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          heroAttributes: PhotoViewHeroAttributes(tag: urls[index]),
        ),
        scrollPhysics: const BouncingScrollPhysics(),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (context, event) =>
            const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
