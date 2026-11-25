import 'package:flutter/material.dart';
import '../models/script_character.dart';
import '../services/character_icons.dart';
import 'character_picker_dialog.dart' show teamColor;

/// Drop-in replacement for the plain colored CircleAvatar used
/// everywhere a character is shown. Renders the matching icon from
/// assets/icons/ once resolved, and falls back to the original
/// colored circle-with-initial look otherwise — including while the
/// asset manifest is still loading.
///
/// Pass [ringColor] to draw a colored border around the icon instead
/// of tinting its background — used for alignment (good/evil) where
/// the character image itself should stay untinted.
class CharacterAvatar extends StatefulWidget {
  final ScriptCharacter character;
  final double radius;
  final Color? ringColor;
  const CharacterAvatar({
    super.key,
    required this.character,
    this.radius = 16,
    this.ringColor,
  });

  @override
  State<CharacterAvatar> createState() => _CharacterAvatarState();
}

class _CharacterAvatarState extends State<CharacterAvatar> {
  @override
  void initState() {
    super.initState();
    CharacterIcons.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = CharacterIcons.instance.assetPathFor(widget.character);
    final size = widget.radius * 2;

    if (path != null) {
      final image = CircleAvatar(
        radius: widget.radius,
        backgroundColor: Colors.transparent,
        backgroundImage: AssetImage(path),
      );
      if (widget.ringColor == null) return image;
      return Container(
        width: size + 4,
        height: size + 4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: widget.ringColor!, width: 2),
        ),
        child: Padding(padding: const EdgeInsets.all(1), child: image),
      );
    }

    final initial = widget.character.name.isNotEmpty
        ? widget.character.name[0].toUpperCase()
        : '?';
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.ringColor ?? teamColor(widget.character.team),
      child: Text(initial, style: const TextStyle(color: Colors.white)),
    );
  }
}
