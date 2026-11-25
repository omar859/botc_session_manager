import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/profile_controller.dart';
import '../widgets/appearance_settings.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  bool _nameEdited = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: context.read<ProfileController>().name,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileController>();
    if (!_nameEdited && _nameController.text != profile.name) {
      _nameController.text = profile.name;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Your name',
              hintText: 'Optional — you can still enter a name when joining',
              prefixIcon: Icon(Icons.person_outline),
            ),
            onChanged: (_) => _nameEdited = true,
            onSubmitted: profile.setName,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: () => profile.setName(_nameController.text),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save name'),
            ),
          ),
          const SizedBox(height: 16),
          _statsCard(context, profile),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Appearance',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 14),
                  const AppearanceSettingsPanel(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Game history', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (profile.history.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Your completed games will appear here.'),
              ),
            )
          else
            for (final game in profile.history) _historyTile(context, game),
        ],
      ),
    );
  }

  Widget _statsCard(BuildContext context, ProfileController profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 22,
          runSpacing: 14,
          children: [
            _stat('Games', '${profile.gamesPlayed}'),
            _stat('Wins', '${profile.wins}'),
            _stat('Losses', '${profile.losses}'),
            _stat('Most played', profile.mostPlayedRole ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _historyTile(BuildContext context, ProfileGameRecord game) {
    final resultColor = game.isWin
        ? Colors.green
        : game.isLoss
            ? Colors.redAccent
            : Theme.of(context).colorScheme.primary;
    final result = game.outcome == 'hosted'
        ? 'Hosted game'
        : game.isWin
            ? 'Won'
            : 'Lost';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: resultColor.withOpacity(0.16),
          child: Icon(Icons.sports_esports_outlined, color: resultColor),
        ),
        title: Text(game.role),
        subtitle: Text(
          '${game.alignment.toUpperCase()} • $result • ${_date(game.playedAt)}',
        ),
        trailing: Text(result, style: TextStyle(color: resultColor)),
      ),
    );
  }

  String _date(DateTime date) => '${date.day}/${date.month}/${date.year}';
}
