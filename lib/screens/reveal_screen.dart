import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/script_character.dart';
import '../providers/game_provider.dart';
import '../widgets/character_ability_sheet.dart' show showCharacterAbilitySheet;
import '../widgets/character_picker_dialog.dart'
    show alignmentColor, alignmentLabel;
import '../widgets/character_avatar.dart';
import '../theme/profile_controller.dart';

/// End-of-game character reveal.
///
/// Deliberately NOT grouped by team — a flat, seat-ordered list of
/// frosted-glass cards instead:
///
///  - The STORYTELLER's own copy shows every name and character already
///    (they made every assignment themselves) — what's hidden is only
///    what the TABLE has been shown so far. Tapping an unopened card
///    broadcasts that one player's name + character to every other
///    device at once (HostServer.revealCard); tapping an already-opened
///    card reopens its ability sheet instead.
///  - Every PLAYER's copy renders NOTHING for an unopened card — not a
///    blurred name, not a hinted color, no data at all, because the data
///    itself never reaches that device until the storyteller's tap sends
///    it (see GameProvider._onClientMessage's gameReveal /
///    revealCardOpened handling). The frost lifts, with the same
///    animation, on every screen at the same moment.
class RevealScreen extends StatelessWidget {
  const RevealScreen({super.key});

  @override
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final isHost = provider.isHost;
    final room = provider.room;

    final winner = provider.winnerAlignment;
    if (winner != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final profile = context.read<ProfileController>();
        final playerAlignment = provider.myAlignment ?? 'unknown';
        profile.recordGame(
          gameId: '${room?.roomCode}-${provider.revealGeneration}',
          role: isHost
              ? 'Storyteller'
              : (provider.myCharacter?.name ?? 'Unknown role'),
          alignment: isHost ? 'storyteller' : playerAlignment,
          outcome: isHost
              ? 'hosted'
              : playerAlignment == winner
                  ? 'win'
                  : 'loss',
        );
      });
    }

    final order = room?.revealOrder ?? const <String>[];
    final revealedIds = room?.revealedCardIds ?? const <String>{};
    if (provider.consumeNewGameStarted()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
    }
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Game Over'),
          backgroundColor: Colors.deepPurple,
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
              children: [
                Text(
                  isHost
                      ? 'Tap a card to reveal it to the table'
                      : 'The Storyteller will reveal each player in turn',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                if (order.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No character assignments to reveal.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                for (final pid in order)
                  _RevealCard(
                    key: ValueKey(pid),
                    playerId: pid,
                    isHost: isHost,
                    isRevealed: revealedIds.contains(pid),
                  ),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isHost) ...[
                    // *** NEW: Start New Game button ***
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Start New Game'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepPurpleAccent,
                        side: const BorderSide(
                            color: Colors.deepPurpleAccent, width: 1.4),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Start a new game?'),
                            content: const Text(
                                'Every character, alignment, bluff, and the reveal will be cleared. Everyone stays connected and seated.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Start New Game')),
                            ],
                          ),
                        );
                        if (confirmed == true) provider.startNewGame();
                      },
                    ),
                    const SizedBox(height: 10),
                    // *** Existing Good/Evil row ***
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.shield, size: 18),
                            label: const Text('Good Wins'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: alignmentColor('good'),
                              side: BorderSide(
                                  color: alignmentColor('good'), width: 1.4),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            onPressed: () => provider.declareWinner('good'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.whatshot, size: 18),
                            label: const Text('Evil Wins'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: alignmentColor('evil'),
                              side: BorderSide(
                                  color: alignmentColor('evil'), width: 1.4),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            onPressed: () => provider.declareWinner('evil'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  FilledButton.icon(
                    icon: const Icon(Icons.home),
                    label: const Text('Leave Game'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.redAccent,
                    ),
                    onPressed: () async {
                      if (isHost) {
                        await provider.stopHosting();
                      } else {
                        await provider.leaveGame();
                      }
                      if (!context.mounted) return;
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevealCard extends StatelessWidget {
  final String playerId;
  final bool isHost;
  final bool isRevealed;

  const _RevealCard({
    super.key,
    required this.playerId,
    required this.isHost,
    required this.isRevealed,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<GameProvider>();
    final room = provider.room;

    // The host reads straight from the authoritative RoomState it already
    // has. A player reads from revealedCharacterIds, which is only ever
    // populated once isRevealed is true — before that there is nothing
    // here to read. That gap IS the security boundary, not a visual one.
    final playerName = room?.players[playerId]?.name ?? 'Unknown';
    final hostCharId = room?.assignedCharacters[playerId];
    final revealedCharId = room?.revealedCharacterIds[playerId];
    final charId = isHost ? hostCharId : revealedCharId;
    final ScriptCharacter? character = (charId == null || charId.isEmpty)
        ? null
        : provider.characterById(charId);
    final alignment = isHost
        ? room?.playerAlignments[playerId]
        : room?.revealedAlignments[playerId];

    final showContent = isHost || isRevealed;

    return GestureDetector(
      onTap: () {
        if (isHost) {
          if (!isRevealed) {
            provider.revealCard(playerId);
          } else if (character != null) {
            showCharacterAbilitySheet(context, character);
          }
        } else if (isRevealed && character != null) {
          showCharacterAbilitySheet(context, character);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRevealed ? Colors.deepPurpleAccent : Colors.white24,
            width: isRevealed ? 1.4 : 1,
          ),
          boxShadow: isRevealed
              ? [
                  BoxShadow(
                    color: Colors.deepPurpleAccent.withOpacity(0.35),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Frosted glass base — every card gets the same glossy look,
              // locked or open, so the reveal reads as "unfrosting" rather
              // than a plain content swap.
              BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  height: 78,
                  width: double.infinity,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: anim, child: child),
                ),
                child: showContent
                    ? _RevealedContent(
                        key: const ValueKey('open'),
                        playerName: playerName,
                        character: character,
                        alignment: alignment,
                        isHost: isHost,
                        alreadyShownToTable: isRevealed,
                      )
                    : const _LockedContent(key: ValueKey('locked')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedContent extends StatelessWidget {
  const _LockedContent({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Row(
        children: [
          const SizedBox(width: 16),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.12),
            ),
            child:
                const Icon(Icons.lock_outline, size: 16, color: Colors.white54),
          ),
          const SizedBox(width: 14),
          const Text(
            '? ? ?',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevealedContent extends StatelessWidget {
  final String playerName;
  final ScriptCharacter? character;
  final String? alignment;
  final bool isHost;
  final bool alreadyShownToTable;

  const _RevealedContent({
    super.key,
    required this.playerName,
    required this.character,
    required this.alignment,
    required this.isHost,
    required this.alreadyShownToTable,
  });

  @override
  Widget build(BuildContext context) {
    final hasCharacter = character != null;
    final accent = hasCharacter ? alignmentColor(alignment) : Colors.grey;
    return SizedBox(
      height: 78,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            hasCharacter
                ? CharacterAvatar(
                    character: character!, radius: 17, ringColor: accent)
                : CircleAvatar(
                    radius: 17,
                    backgroundColor: accent,
                    child: const Icon(Icons.help_outline,
                        size: 17, color: Colors.white),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playerName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(
                    hasCharacter
                        ? '${character!.name} · ${alignmentLabel(alignment)}'
                        : 'No character assigned',
                    style: TextStyle(fontSize: 12.5, color: accent),
                  ),
                ],
              ),
            ),
            if (isHost)
              Icon(
                alreadyShownToTable ? Icons.visibility : Icons.touch_app,
                size: 18,
                color: alreadyShownToTable ? Colors.greenAccent : Colors.amber,
              ),
          ],
        ),
      ),
    );
  } // NEW: glossy winner announcement — same visual language as the

// character reveal and Storyteller-announcement popups. Blue glow for
// Good, red glow for Evil. Shown on every device the instant the
// Storyteller declares a winner.
  void showWinnerPopup(BuildContext context, String alignment) {
    final accent = alignmentColor(alignment);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(
                    accent.withOpacity(0.3), const Color(0xFF1E1E2E)),
                const Color(0xFF1E1E2E),
              ],
              stops: const [0.0, 0.45],
            ),
            border: Border.all(color: accent.withOpacity(0.6), width: 1.4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.18),
                  border: Border.all(color: accent, width: 2.4),
                  boxShadow: [
                    BoxShadow(
                        color: accent.withOpacity(0.6),
                        blurRadius: 28,
                        spreadRadius: 2),
                  ],
                ),
                child: Icon(
                  alignment == 'evil' ? Icons.whatshot : Icons.shield,
                  color: accent,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${alignmentLabel(alignment).toUpperCase()} WINS',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: accent,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The game has ended.',
                style: TextStyle(fontSize: 13.5, color: Colors.white70),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// NEW: glossy winner announcement — same visual language as the
// character reveal and Storyteller-announcement popups. Blue glow for
// Good, red glow for Evil. Shown on every device the instant the
// Storyteller declares a winner.
