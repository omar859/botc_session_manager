import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/appearance_controller.dart';

class AppearanceSettingsPanel extends StatelessWidget {
  const AppearanceSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceController>();
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Theme', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment(
                  value: AppThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined)),
              ButtonSegment(
                  value: AppThemeMode.defaultTheme,
                  label: Text('Default'),
                  icon: Icon(Icons.brightness_6_outlined)),
              ButtonSegment(
                  value: AppThemeMode.white,
                  label: Text('White'),
                  icon: Icon(Icons.light_mode_outlined)),
            ],
            selected: {appearance.mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                appearance.setMode(selection.first),
          ),
        ),
        const SizedBox(height: 18),
        Text('Accent color', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final accent in AppAccent.values)
              ChoiceChip(
                label: Text(accent.label),
                avatar: CircleAvatar(
                    radius: 8, backgroundColor: Color(accent.value)),
                selected: appearance.accent == accent,
                selectedColor: Color(accent.value).withOpacity(0.24),
                onSelected: (_) => appearance.setAccent(accent),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'This setting only changes the interface on this device.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
