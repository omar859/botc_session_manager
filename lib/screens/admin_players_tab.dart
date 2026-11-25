import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/room_state.dart';
import '../models/player.dart';
import '../models/script_character.dart';
import '../widgets/player_note_dialog.dart';
import '../widgets/character_picker_dialog.dart';
import '../widgets/character_avatar.dart';
import '../widgets/circular_seating_view.dart';

enum _AdminPlayersView { list, circle }

class AdminPlayersTab extends StatefulWidget {
  final void Function(String playerId) onOpenDm;
  const AdminPlayersTab({super.key, required this.onOpenDm});

  @override
  State<AdminPlayersTab> createState() => _AdminPlayersTabState();
}

class _AdminPlayersTabState extends State<AdminPlayersTab> {
  _AdminPlayersView _view = _AdminPlayersView.list;
  String? _expandedPlayerId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final room = provider.room!;
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight + 8;
    final ordered = room.players.values.toList()
      ..sort((a, b) => a.seat.compareTo(b.seat));

    return Column(
      children: [
        SizedBox(height: topInset),
        if (room.pendingRequests.isNotEmpty)
          _buildPendingRequests(provider, room),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<_AdminPlayersView>(
            segments: const [
              ButtonSegment(
                  value: _AdminPlayersView.list,
                  icon: Icon(Icons.view_list, size: 16),
                  label: Text('List')),
              ButtonSegment(
                  value: _AdminPlayersView.circle,
                  icon: Icon(Icons.donut_large, size: 16),
                  label: Text('Circle')),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _view == _AdminPlayersView.list
              ? _buildListView(ordered)
              : _buildCircleView(context, ordered, provider),
        ),
      ],
    );
  }

  Widget _buildPendingRequests(GameProvider provider, RoomState room) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('Pending Join Requests',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 10,
                backgroundColor: Colors.orange,
                child: Text('${room.pendingRequests.length}',
                    style: const TextStyle(fontSize: 12, color: Colors.white)),
              ),
            ],
          ),
        ),
        for (final entry in room.pendingRequests.entries)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.orange.withOpacity(0.15),
            child: ListTile(
              leading: const Icon(Icons.person_add, color: Colors.orange),
              title: Text(entry.value.name),
              subtitle: const Text('Waiting for approval',
                  style: TextStyle(fontSize: 11)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.redAccent, size: 20),
                    tooltip: 'Decline',
                    onPressed: () => provider.declineJoinRequest(entry.key),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check,
                        color: Colors.greenAccent, size: 20),
                    tooltip: 'Approve',
                    onPressed: () => provider.approveJoinRequest(entry.key),
                  ),
                ],
              ),
            ),
          ),
        const Divider(),
      ],
    );
  }

  Widget _buildListView(List<Player> ordered) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('Players (${ordered.length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (ordered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: Text('No players yet',
                    style: TextStyle(color: Colors.grey))),
          ),
        for (final p in ordered)
          _AdminPlayerRow(
            player: p,
            onOpenDm: widget.onOpenDm,
            expanded: _expandedPlayerId == p.id,
            onToggle: () => setState(() {
              _expandedPlayerId = _expandedPlayerId == p.id ? null : p.id;
            }),
          ),
      ],
    );
  }

  Widget _buildCircleView(
      BuildContext context, List<Player> ordered, GameProvider provider) {
    if (ordered.isEmpty) {
      return const Center(
          child: Text('No players yet', style: TextStyle(color: Colors.grey)));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CircularSeatingView(
        itemCount: ordered.length,
        center: const Icon(Icons.auto_stories, color: Colors.white24, size: 30),
        itemBuilder: (context, index, avatarSize, showLabel) {
          final p = ordered[index];
          final charId = provider.room?.assignedCharacters[p.id];
          final char = (charId == null || charId.isEmpty)
              ? null
              : provider.characterById(charId);
          final alignment = provider.alignmentFor(p.id);
          final ringColor = !p.alive
              ? Colors.grey.shade600
              : (char != null
                  ? alignmentColor(alignment)
                  : Colors.deepPurpleAccent);

          return GestureDetector(
            onTap: () => _openPlayerSheet(context, p),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: p.alive ? 1 : 0.55,
                  child: char != null
                      ? CharacterAvatar(
                          character: char,
                          radius: avatarSize / 2,
                          ringColor: ringColor)
                      : Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF33334a),
                            border: Border.all(color: ringColor, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: avatarSize * 0.36),
                            ),
                          ),
                        ),
                ),
                if (showLabel)
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 10, color: Colors.white70)),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openPlayerSheet(BuildContext context, Player p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2A2A3D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 14),
                _AdminPlayerActions(player: p, onOpenDm: widget.onOpenDm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared action set — used by both the list row's inline expansion
/// and the circle view's tap-to-open bottom sheet.
class _AdminPlayerActions extends StatelessWidget {
  final Player player;
  final void Function(String playerId) onOpenDm;
  const _AdminPlayerActions({required this.player, required this.onOpenDm});

  Future<void> _confirmKick(BuildContext context, GameProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kick player?'),
        content: const Text('This will remove the player from the game.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kick')),
        ],
      ),
    );
    if (confirmed == true) provider.kickPlayer(player.id);
  }

  Future<void> _showSwapSeatDialog(
      BuildContext context, GameProvider provider) async {
    final seatedPlayers = provider.room?.seating ?? [];
    final others = seatedPlayers.where((id) => id != player.id).toList();
    if (others.isEmpty) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Swap seat with'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: others.length,
            itemBuilder: (ctx, index) {
              final targetId = others[index];
              final target = provider.room?.players[targetId];
              return ListTile(
                title: Text(target?.name ?? targetId),
                onTap: () {
                  provider.swapPlayerSeats(player.id, targetId);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<String?> _chooseAlignment(BuildContext context) => showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Choose alignment'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'good'),
              child: const Text('Good'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'evil'),
              child: const Text('Evil'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final p = player;
    final assignedId = provider.room?.assignedCharacters[p.id];
    final displayChar = (assignedId == null || assignedId.isEmpty)
        ? null
        : provider.characterById(assignedId);
    final alignment = provider.alignmentFor(p.id);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.chat_bubble_outline, size: 16),
          label: const Text('DM'),
          onPressed: () => onOpenDm(p.id),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.theater_comedy, size: 16),
          label: Text(
              displayChar == null ? 'Assign character' : 'Change character'),
          onPressed: () async {
            final chars = provider.room?.scriptCharacters ?? [];
            final result = await showCharacterPickerDialog(
              context,
              characters: chars,
              title: 'Assign character to ${p.name}',
              currentValue: assignedId,
            );
            if (result == null) return;
            if (!context.mounted) return;
            final alignment =
                result.isEmpty ? null : await _chooseAlignment(context);
            if (!context.mounted) return;
            if (result.isNotEmpty && alignment == null) return;
            final resolvedChar =
                result.isEmpty ? null : provider.characterById(result);
            provider.assignCharacterNow(p.id, result,
                characterData: resolvedChar, alignment: alignment);
            if (!context.mounted) return;
            final name = provider.characterById(result)?.name;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.isEmpty
                    ? 'Cleared ${p.name}\'s character.'
                    : 'Assigned ${name ?? result} to ${p.name}.'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.sticky_note_2_outlined, size: 16),
          label: const Text('Note'),
          onPressed: () => showPlayerNoteTextDialog(
            context,
            playerId: p.id,
            playerName: p.name,
            useAdminNotes: true,
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.label_outline, size: 16),
          label: const Text('Tags'),
          onPressed: () => showPlayerTagPickerDialog(
            context,
            playerId: p.id,
            playerName: p.name,
            useAdminNotes: true,
          ),
        ),
        OutlinedButton.icon(
          icon: Icon(Icons.circle, size: 12, color: alignmentColor(alignment)),
          label: Text(alignment == 'evil' ? 'Set Good' : 'Set Evil'),
          style: OutlinedButton.styleFrom(
            foregroundColor: alignmentColor(alignment),
            side: BorderSide(color: alignmentColor(alignment)),
          ),
          onPressed: () => provider.setPlayerAlignment(
              p.id, alignment == 'evil' ? 'good' : 'evil'),
        ),
        OutlinedButton.icon(
          icon: Icon(p.muted ? Icons.mic : Icons.mic_off,
              size: 16, color: Colors.orange),
          label: Text(p.muted ? 'Unmute' : 'Mute'),
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange)),
          onPressed: () => provider.mutePlayer(p.id, !p.muted),
        ),
        OutlinedButton.icon(
          icon: Icon(p.alive ? Icons.favorite_border : Icons.favorite,
              size: 16, color: Colors.redAccent),
          label: Text(p.alive ? 'Mark Dead' : 'Revive'),
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent)),
          onPressed: () => provider.setPlayerAlive(p.id, !p.alive),
        ),
        if (!p.alive)
          OutlinedButton.icon(
            icon: const Icon(Icons.how_to_vote, size: 16),
            label: Text(p.ghostVoteUsed
                ? 'Restore ghost vote'
                : 'Mark ghost vote used'),
            onPressed: () => provider.setGhostVoteUsed(p.id, !p.ghostVoteUsed),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.swap_horiz, size: 16),
          label: const Text('Swap seat'),
          onPressed: () => _showSwapSeatDialog(context, provider),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.remove_circle_outline,
              size: 16, color: Colors.red),
          label: const Text('Kick'),
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red)),
          onPressed: () => _confirmKick(context, provider),
        ),
      ],
    );
  }
}

class _AdminPlayerRow extends StatelessWidget {
  final Player player;
  final void Function(String playerId) onOpenDm;
  final bool expanded;
  final VoidCallback onToggle;
  const _AdminPlayerRow({
    required this.player,
    required this.onOpenDm,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final p = player;
    final disconnected = p.status == PlayerStatus.disconnected;
    final assignedId = provider.room?.assignedCharacters[p.id];
    final displayChar = (assignedId == null || assignedId.isEmpty)
        ? null
        : provider.characterById(assignedId);
    final hasUnreadDm = provider.hasUnreadDm(p.id);
    final note = provider.getAdminNoteFor(p.id);
    final alignment = provider.alignmentFor(p.id);
    final tagColorByName = <String, Color>{};
    for (final entry in ScriptCharacter.allTags(
        provider.room?.scriptCharacters ?? const [])) {
      tagColorByName[entry.key] = teamColor(entry.value.team);
    }

    return Column(
      children: [
        ListTile(
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              (!p.alive || displayChar == null)
                  ? CircleAvatar(
                      backgroundColor: !p.alive
                          ? Colors.grey.shade700
                          : disconnected
                              ? Colors.grey
                              : Colors.deepPurple,
                      child: Text(
                          !p.alive
                              ? '💀'
                              : p.name.isNotEmpty
                                  ? p.name[0].toUpperCase()
                                  : '?',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    )
                  : CharacterAvatar(
                      character: displayChar,
                      radius: 18,
                      ringColor: alignmentColor(alignment)),
              if (hasUnreadDm)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 1)),
                  ),
                ),
            ],
          ),
          title: Text('Seat ${p.seat + 1} · ${p.name}',
              style: TextStyle(color: disconnected ? Colors.grey : null)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (disconnected)
                  const _StatusPill(label: 'Offline', color: Colors.grey),
                if (!p.alive)
                  const _StatusPill(label: 'Dead', color: Color(0xFF616161)),
                if (!p.alive && p.ghostVoteUsed)
                  const _StatusPill(
                      label: 'Ghost vote used', color: Colors.blueGrey),
                if (p.muted)
                  const _StatusPill(label: 'Muted', color: Colors.orange),
                if (displayChar != null)
                  _StatusPill(
                    label: '${displayChar.name} · ${alignmentLabel(alignment)}',
                    color: alignmentColor(alignment),
                  ),
                for (final tag in note.tags)
                  _StatusPill(
                      label: tag,
                      color: tagColorByName[tag] ?? Colors.grey,
                      maxWidth: 140),
              ],
            ),
          ),
          trailing: IconButton(
            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onPressed: onToggle,
          ),
          onTap: onToggle,
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!note.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(note.text,
                        style:
                            const TextStyle(fontSize: 13, color: Colors.amber)),
                  ),
                _AdminPlayerActions(player: p, onOpenDm: onOpenDm),
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final double? maxWidth;
  const _StatusPill({required this.label, required this.color, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(label,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
              fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
    );
    if (maxWidth == null) return pill;
    return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!), child: pill);
  }
}
