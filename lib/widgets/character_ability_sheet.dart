import 'package:flutter/material.dart';
import '../models/script_character.dart';
import 'character_avatar.dart';
import 'character_picker_dialog.dart' show teamColor;

void showCharacterAbilitySheet(
    BuildContext context, ScriptCharacter character) {
  final accent = teamColor(character.team);

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                  accent.withOpacity(0.22), const Color(0xFF1E1E2E)),
              const Color(0xFF1E1E2E),
            ],
            stops: const [0.0, 0.35],
          ),
          border: Border.all(color: accent.withOpacity(0.4), width: 1),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Centered hero icon
              Center(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.45),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: CharacterAvatar(character: character, radius: 42),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                character.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withOpacity(0.6)),
                  ),
                  child: Text(
                    ScriptCharacter.teamLabel(character.team).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accent,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Divider(color: accent.withOpacity(0.25), height: 1),
              const SizedBox(height: 18),
              Text(
                character.ability.isEmpty
                    ? 'No ability text available for this character.'
                    : character.ability,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.5,
                  color: Colors.white,
                ),
              ),
              if (character.flavor.trim().isNotEmpty) ...[
                const SizedBox(height: 20),
                Divider(color: accent.withOpacity(0.15), height: 1),
                const SizedBox(height: 16),
                Text(
                  character.flavor,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Colors.white.withOpacity(0.55),
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
