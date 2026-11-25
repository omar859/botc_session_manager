import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/player.dart';

import '../models/room_state.dart';
import '../widgets/player_note_dialog.dart';
import '../widgets/character_picker_dialog.dart';
import '../widgets/circular_seating_view.dart';
import '../widgets/team_distribution_row.dart';
import '../widgets/character_avatar.dart';
import '../widgets/character_ability_sheet.dart';
import '../models/script_character.dart';

enum _TableView { list, circle }

/// Helper to find the private chat a player is currently participating in,
/// using the public membership map broadcast to all devices.
({String chatId, List<String> participants})? _findBusyChat(
    GameProvider provider, String playerId) {
  for (final entry in provider.chatMembership.entries) {
    if (entry.value.contains(playerId)) {
      return (chatId: entry.key, participants: entry.value);
    }
  }
  return null;
}

class TableTab extends StatefulWidget {
  final void Function(String chatId) onOpenPrivateChat;
  const TableTab({super.key, required this.onOpenPrivateChat});

  @override
  State<TableTab> createState() => _TableTabState();
}

class _TableTabState extends State<TableTab> {
  _TableView _view = _TableView.list;
  String? _expandedPlayerId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final room = provider.room;
    final myId = provider.myPlayer?.id;
    if (room == null || myId == null) {
      return const Center(child: Text('Not seated yet.'));
    }
    final others = room.players.values.where((p) => p.id != myId).toList()
      ..sort((a, b) => a.seat.compareTo(b.seat));
    final allSeated = room.players.values.toList()
      ..sort((a, b) => a.seat.compareTo(b.seat));
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight + 8;

    return Column(
      children: [
        SizedBox(height: topInset),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<_TableView>(
            segments: const [
              ButtonSegment(
                  value: _TableView.list,
                  icon: Icon(Icons.view_list, size: 16),
                  label: Text('List')),
              ButtonSegment(
                  value: _TableView.circle,
                  icon: Icon(Icons.donut_large, size: 16),
                  label: Text('Circle')),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _view == _TableView.list
              ? _buildListView(room, others)
              : _buildCircleView(context, allSeated, myId, provider),
        ),
      ],
    );
  }

  Widget _buildListView(RoomState room, List<Player> others) {
    return ListView(
      children: [
        TeamDistributionRow(room: room),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('Players (${others.length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (others.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: Text('No other players yet',
                    style: TextStyle(color: Colors.grey))),
          ),
        for (final p in others)
          _PlayerRow(
            player: p,
            expanded: _expandedPlayerId == p.id,
            onToggle: () => setState(() {
              _expandedPlayerId = _expandedPlayerId == p.id ? null : p.id;
            }),
            onOpenPrivateChat: widget.onOpenPrivateChat,
          ),
      ],
    );
  }

  Widget _buildCircleView(BuildContext context, List<Player> allPlayers,
      String myId, GameProvider provider) {
    if (allPlayers.isEmpty) {
      return const Center(
          child: Text('No players yet', style: TextStyle(color: Colors.grey)));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CircularSeatingView(
        itemCount: allPlayers.length,
        center: Icon(Icons.remove_red_eye_outlined,
            color: Colors.white.withOpacity(0.15), size: 30),
        itemBuilder: (context, index, avatarSize, showLabel) {
          final p = allPlayers[index];
          final isSelf = p.id == myId;
          final guessId = isSelf ? null : provider.getGuessFor(p.id);
          final guessChar = (guessId == null || guessId.isEmpty)
              ? null
              : provider.characterById(guessId);
          final myChar = isSelf ? provider.myCharacter : null;
          final showChar = isSelf ? myChar : guessChar;

          Color ringColor;
          if (!p.alive) {
            ringColor = Colors.grey.shade600;
          } else if (isSelf && myChar != null) {
            ringColor = alignmentColor(provider.myAlignment);
          } else if (guessChar != null) {
            ringColor = Colors.amber; // guessed, not confirmed
          } else {
            ringColor = Colors.deepPurpleAccent;
          }

          final avatar = showChar != null
              ? Opacity(
                  opacity: p.alive ? 1 : 0.55,
                  child: CharacterAvatar(
                      character: showChar,
                      radius: avatarSize / 2,
                      ringColor: ringColor),
                )
              : Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF33334a),
                    border: Border.all(color: ringColor, width: 2),
                  ),
                  child: Center(
                    child: p.alive
                        ? Text(
                            p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: avatarSize * 0.36))
                        : const Text('💀'),
                  ),
                );

          return GestureDetector(
            onTap: isSelf ? null : () => _openPlayerSheet(context, p),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                avatar,
                if (showLabel)
                  Text(
                    isSelf ? '${p.name} (You)' : p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelf ? Colors.amber : Colors.white70,
                      fontWeight: isSelf ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
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
                _PlayerActionsRow(
                    player: p, onOpenPrivateChat: widget.onOpenPrivateChat),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared action row (guess / note / private-chat) — used by both the
/// list view's inline expansion and the circle view's tap-to-open
/// bottom sheet, so the two views never drift out of sync.
class _PlayerActionsRow extends StatelessWidget {
  final Player player;
  final void Function(String chatId) onOpenPrivateChat;
  const _PlayerActionsRow(
      {required this.player, required this.onOpenPrivateChat});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final p = player;

    final busy = _findBusyChat(provider, p.id);
    final isBusy = busy != null;
    final guessId = provider.getGuessFor(p.id);
    final guessChar = (guessId == null || guessId.isEmpty)
        ? null
        : provider.characterById(guessId);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.theater_comedy, size: 16),
          label: Text(guessChar == null ? 'Guess' : guessChar.name),
          onPressed: () => _openGuessGrid(context, provider, p.id, p.name),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.sticky_note_2_outlined, size: 16),
          label: const Text('Note'),
          onPressed: () => showPlayerNoteTextDialog(
            context,
            playerId: p.id,
            playerName: p.name,
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.label_outline, size: 16),
          label: const Text('Tags'),
          onPressed: () => showPlayerTagPickerDialog(
            context,
            playerId: p.id,
            playerName: p.name,
          ),
        ),
        Builder(builder: (_) {
          if (provider.neighborRestriction) {
            return const Text('Private chats disabled',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic));
          }
          final myId = provider.myPlayer?.id;
          final sameChatAsMe =
              isBusy && myId != null && busy.participants.contains(myId);
          if (sameChatAsMe) {
            return const SizedBox
                .shrink(); // already together in this exact chat
          }
          if (provider.isInAnyPrivateChat) {
            return const SizedBox.shrink();
          }
          final myTarget = isBusy ? busy.chatId : p.id;
          final pending = provider.pendingOutgoingRequestId == myTarget;
          return OutlinedButton.icon(
            icon: Icon(
              pending
                  ? Icons.hourglass_top
                  : (isBusy ? Icons.groups : Icons.chat_bubble_outline),
              size: 16,
            ),
            label: Text(pending
                ? 'Request sent'
                : (isBusy ? 'Join chat' : 'Private chat')),
            onPressed: (pending || provider.hasAnyPendingRequest)
                ? null
                : () {
                    if (isBusy) {
                      provider.requestJoinChat(busy.chatId);
                    } else {
                      provider.requestPrivateChat(p.id);
                    }
                  },
          );
        }),
      ],
    );
  }
}

/// Full-screen guess picker with icons, long-press info, clear slot, and team color.
Future<void> _openGuessGrid(
  BuildContext context,
  GameProvider provider,
  String playerId,
  String playerName,
) async {
  final chars = provider.room?.scriptCharacters ?? [];
  final current = provider.getGuessFor(playerId);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E1E2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Guess for $playerName',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                controller: controller,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: chars.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    // Empty slot — clears the guess.
                    return GestureDetector(
                      onTap: () {
                        provider.setGuessFor(playerId, null);
                        Navigator.pop(sheetContext);
                      },
                      child: Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.grey, width: 1.5),
                            ),
                            child: const Icon(Icons.close, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          const Text('None',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    );
                  }
                  final c = chars[i - 1];
                  final selected = c.id == current;
                  return GestureDetector(
                    onTap: () {
                      provider.setGuessFor(playerId, c.id);
                      Navigator.pop(sheetContext);
                    },
                    onLongPress: () => showCharacterAbilitySheet(context, c),
                    child: Column(
                      children: [
                        CharacterAvatar(
                          character: c,
                          radius: 26,
                          ringColor:
                              selected ? Colors.amber : teamColor(c.team),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PlayerRow extends StatelessWidget {
  final Player player;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(String chatId) onOpenPrivateChat;
  const _PlayerRow({
    required this.player,
    required this.expanded,
    required this.onToggle,
    required this.onOpenPrivateChat,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final p = player;

    final busy = _findBusyChat(provider, p.id);
    final isBusy = busy != null;
    final guessId = provider.getGuessFor(p.id);
    final guessChar = (guessId == null || guessId.isEmpty)
        ? null
        : provider.characterById(guessId);
    final note = provider.getNoteFor(p.id);

    String? busyLabel;
    if (isBusy) {
      final partners = busy.participants
          .where((id) => id != p.id)
          .map((id) => provider.room?.players[id]?.name ?? '?')
          .toList();
      busyLabel = partners.isEmpty
          ? 'In a private chat'
          : 'In a private chat with ${partners.join(', ')}';
    }
    final statusLabel = [
      if (busyLabel != null) busyLabel,
      if (p.muted) 'Muted',
      if (!p.alive) 'Dead',
      if (!p.alive && p.ghostVoteUsed) 'Ghost vote used',
      if (guessChar != null) 'Guess: ${guessChar.name}',
    ].join(' · ');

    return Column(
      children: [
        ListTile(
          leading: !p.alive
              ? const Text('💀', style: TextStyle(fontSize: 20))
              : (guessChar != null
                  ? CharacterAvatar(
                      character: guessChar, radius: 18, ringColor: Colors.amber)
                  : const Icon(Icons.person)),
          title: Text(p.name),
          subtitle: (statusLabel.isEmpty && note.tags.isEmpty)
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (statusLabel.isNotEmpty)
                        Text(statusLabel,
                            style: const TextStyle(
                                fontSize: 12, fontStyle: FontStyle.italic)),
                      if (note.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final tag in note.tags)
                                _TagPill(
                                    label: tag,
                                    color: _tagColor(
                                        tag,
                                        provider.room?.scriptCharacters ??
                                            const [])),
                            ],
                          ),
                        ),
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
                if (note.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child:
                        Text(note.text, style: const TextStyle(fontSize: 13)),
                  ),
                _PlayerActionsRow(
                    player: p, onOpenPrivateChat: onOpenPrivateChat),
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

Color _tagColor(String tag, List<ScriptCharacter> characters) {
  for (final entry in ScriptCharacter.allTags(characters)) {
    if (entry.key == tag) return teamColor(entry.value.team);
  }
  return Colors.grey;
}

class _TagPill extends StatelessWidget {
  final String label;
  final Color color;
  const _TagPill({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
