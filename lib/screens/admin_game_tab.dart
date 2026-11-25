import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/room_state.dart';
import '../models/script_character.dart';
import 'bluffs_manager_screen.dart';
import '../widgets/character_picker_dialog.dart'
    show showMultiCharacterPickerDialog;
import '../services/script_library.dart';

class AdminGameTab extends StatelessWidget {
  final void Function(String chatId) onOpenWatch;
  final void Function(String key) onOpenNeighborWatch;
  const AdminGameTab({
    super.key,
    required this.onOpenWatch,
    required this.onOpenNeighborWatch,
  });
  Future<void> _showAnnouncementDialog(
      BuildContext context, GameProvider provider, RoomState room) async {
    final controller = TextEditingController();
    bool sendToAll = true;
    final selected = <String>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Send Announcement'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Message to show as a pop-up...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Send to all players'),
                    value: sendToAll,
                    onChanged: (v) => setState(() => sendToAll = v),
                  ),
                  if (!sendToAll)
                    SizedBox(
                      height: 220,
                      child: ListView(
                        children: [
                          for (final p in room.players.values)
                            CheckboxListTile(
                              dense: true,
                              title: Text(p.name),
                              value: selected.contains(p.id),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  selected.add(p.id);
                                } else {
                                  selected.remove(p.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                if (!sendToAll && selected.isEmpty) return;
                provider.sendAnnouncement(
                    text, sendToAll ? null : selected.toList());
                Navigator.pop(dialogContext);
              },
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCountdownDialog(BuildContext context, GameProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Start Countdown'),
        content: const Text('Choose how long players have to talk privately.'),
        actions: [
          for (final minutes in [1, 2, 3, 5, 10])
            TextButton(
              onPressed: () {
                provider.startCountdown(minutes * 60);
                Navigator.pop(context);
              },
              child: Text('$minutes min'),
            ),
        ],
      ),
    );
  }

  void _confirmReveal(BuildContext context, GameProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reveal all characters?'),
        content: const Text(
          'This will broadcast every player\'s character to every device. '
          'Only do this when the game is over.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              provider.revealGame();
              Navigator.pop(context);
            },
            child: const Text('Reveal'),
          ),
        ],
      ),
    );
  }

  void _confirmForceCloseAll(BuildContext context, GameProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Force close ALL private chats?'),
        content: const Text(
            'Every active private chat at the table will end immediately.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              provider.forceCloseAllChats();
              Navigator.pop(context);
            },
            child: const Text('Close All'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendBluffs(
      BuildContext context, GameProvider provider, RoomState room) async {
    if (room.scriptCharacters.isEmpty) return;
    if (room.players.isEmpty) return;
    final characterIds = await showMultiCharacterPickerDialog(
      context,
      characters: room.scriptCharacters,
      title: 'Select Bluffs',
    );
    if (characterIds == null || characterIds.isEmpty) return;
    if (!context.mounted) return;
    final targetPlayerId = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Send bluffs to…'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView(
            children: [
              for (final entry in room.players.entries)
                ListTile(
                  leading: const Icon(Icons.person, size: 20),
                  title: Text(entry.value.name),
                  onTap: () => Navigator.pop(context, entry.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (targetPlayerId == null) return;
    provider.adminSendBluffs(characterIds, targetPlayerId);
  }

  Future<void> _selectFabled(
      BuildContext context, GameProvider provider, RoomState room) async {
    final official = await ScriptLibrary.instance.loadAllOfficialCharacters();
    if (!context.mounted) return;

    final charactersById = <String, ScriptCharacter>{
      for (final character in official) character.id: character,
      for (final character in room.scriptCharacters)
        if (character.team == 'fabled') character.id: character,
    };
    final fabled = charactersById.values
        .where((character) => character.team == 'fabled')
        .toList();

    final picked = await showMultiCharacterPickerDialog(
      context,
      characters: fabled,
      title: 'Select Fables',
      initialSelection: provider.activeFabled.map((c) => c.id).toSet(),
      onlyTeam: 'fabled',
      actionNoun: 'fable',
    );
    if (picked == null) return;
    provider.setActiveFabled([
      for (final id in picked)
        if (charactersById[id] != null) charactersById[id]!,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final room = provider.room!;
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight + 8;

    return ListView(
      padding: EdgeInsets.fromLTRB(0, topInset, 0, 24),
      children: [
        const _SectionHeader('Live Controls'),
        SwitchListTile(
          title: const Text('Chat Locked'),
          value: room.chatMode == ChatMode.locked,
          onChanged: (v) =>
              provider.setChatMode(v ? ChatMode.locked : ChatMode.open),
        ),
        SwitchListTile(
          title: const Text('Neighbor Restriction'),
          value: room.neighborRestriction,
          onChanged: (v) => provider.setNeighborRestriction(v),
        ),
        SwitchListTile(
          title: const Text('Night Phase'),
          value: provider.isNight,
          onChanged: (v) => provider.setNight(v),
        ),
        ListTile(
          leading: const Icon(Icons.timer),
          title: const Text('Start Countdown'),
          onTap: () => _showCountdownDialog(context, provider),
        ),
        if (provider.countdownEndTime != null)
          ListTile(
            leading: const Icon(Icons.timer_off),
            title: const Text('Cancel Countdown'),
            onTap: () => provider.cancelCountdown(),
          ),
        ListTile(
          leading: const Icon(Icons.volume_off),
          title: const Text('Stop Sound'),
          subtitle: const Text('Silences the alarm on every device right now',
              style: TextStyle(fontSize: 11)),
          onTap: () => provider.stopCountdownSound(),
        ),
        const Divider(),
        const _SectionHeader('Announcements'),
        ListTile(
          leading: const Icon(Icons.campaign),
          title: const Text('Send Announcement'),
          subtitle: const Text('Pop-up message to all or selected players',
              style: TextStyle(fontSize: 11)),
          onTap: () => _showAnnouncementDialog(context, provider, room),
        ),
        const Divider(),

        const _SectionHeader('Bluffs'),
        ListTile(
          leading: const Icon(Icons.casino),
          title: const Text('Send Bluffs'),
          subtitle: Text(
            room.scriptCharacters.isEmpty || room.players.isEmpty
                ? 'Need players + script'
                : 'Send private bluffs to a player',
            style: const TextStyle(fontSize: 11),
          ),
          enabled: room.scriptCharacters.isNotEmpty && room.players.isNotEmpty,
          onTap: () => _sendBluffs(context, provider, room),
        ),
        ListTile(
          leading: const Icon(Icons.casino_outlined),
          title: const Text('Manage Bluffs'),
          subtitle: Builder(builder: (_) {
            final withBluffs =
                room.playerBluffs.values.where((s) => s.isNotEmpty).length;
            return Text(
                withBluffs == 0
                    ? 'No bluffs sent yet'
                    : '$withBluffs player(s) have bluffs',
                style: const TextStyle(fontSize: 11));
          }),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const BluffsManagerScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('Choose Fables'),
          subtitle: Text(provider.activeFabled.isEmpty
              ? 'No fables selected'
              : provider.activeFabled.map((c) => c.name).join(' · ')),
          onTap: () => _selectFabled(context, provider, room),
        ),
        const Divider(),

        const _SectionHeader('Active Private Chats'),
        if (room.privateChats.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('None active',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          )
        else
          for (final chat in room.privateChats.values)
            ListTile(
              dense: true,
              title: Text('Chat (${chat.playerCount})'),
              subtitle: Text(
                  chat.participants
                      .map((pid) => room.players[pid]?.name ?? pid)
                      .join(', '),
                  style: const TextStyle(fontSize: 11)),
              onTap: () => onOpenWatch(chat.sessionId),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => provider.forceCloseChat(chat.sessionId),
              ),
            ),
        const Divider(),

        const _SectionHeader('Neighbor DMs (read-only)'),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Players message their neighbors directly with no approval step — every message still passes through here.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey),
          ),
        ),
        if (room.neighborDmThreads.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No neighbor DMs yet',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          )
        else
          for (final entry in room.neighborDmThreads.entries)
            Builder(builder: (context) {
              final key = entry.key;
              final messages = entry.value;
              final unread = provider.hasUnreadNeighborDmThread(key);
              final last = messages.isNotEmpty ? messages.last : null;
              final parts = key.split('|');
              final nameA =
                  room.players[parts.isNotEmpty ? parts[0] : '']?.name ??
                      'Unknown';
              final nameB =
                  room.players[parts.length > 1 ? parts[1] : '']?.name ??
                      'Unknown';
              return ListTile(
                dense: true,
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.swap_horiz, size: 18),
                    if (unread)
                      Positioned(
                        right: -3,
                        top: -3,
                        child: Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                                color: Colors.red, shape: BoxShape.circle)),
                      ),
                  ],
                ),
                title: Text('$nameA ↔ $nameB',
                    style: const TextStyle(fontSize: 13)),
                subtitle: last == null
                    ? Text('${messages.length} message(s)',
                        style: const TextStyle(fontSize: 11))
                    : Row(
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 90),
                            child: Text('${last.senderName}: ',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            child: Text(last.text,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                onTap: () => onOpenNeighborWatch(key),
              );
            }),

        const SizedBox(height: 24),

        // ---- Danger Zone: visually separated from everything above ----
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.redAccent, width: 1.4),
            borderRadius: BorderRadius.circular(12),
            color: Colors.redAccent.withOpacity(0.06),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.redAccent, size: 18),
                  SizedBox(width: 6),
                  Text('Danger Zone',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.visibility, color: Colors.redAccent),
                  label: const Text('Reveal Characters',
                      style: TextStyle(color: Colors.redAccent)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => _confirmReveal(context, provider),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                  label: const Text('Force Close ALL Chats',
                      style: TextStyle(color: Colors.redAccent)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => _confirmForceCloseAll(context, provider),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
    );
  }
}
